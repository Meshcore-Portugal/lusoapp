import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:logger/logger.dart';

import '../protocol/protocol.dart';
import '../transport/radio_transport.dart';

final _log = Logger(printer: SimplePrinter(printTime: false));

/// High-level service for communicating with a MeshCore radio.
///
/// Wraps a [RadioTransport] and provides typed command/response methods
/// using the companion protocol encoder/decoder.
class RadioService {
  RadioService(this._transport);

  final RadioTransport _transport;
  StreamSubscription<Uint8List>? _dataSub;
  final _responseController = StreamController<CompanionResponse>.broadcast();
  Uint8List _rxBuffer = Uint8List(0);

  // Public state
  SelfInfo? selfInfo;
  final List<Contact> contacts = [];
  final List<ChannelInfo> channels = [];
  RadioConfig? radioConfig;
  DeviceInfo? deviceInfo;
  int? batteryMv;

  /// Stream of parsed responses from the radio.
  Stream<CompanionResponse> get responses => _responseController.stream;

  /// Emits when the transport connection is lost unexpectedly.
  Stream<void> get connectionLost => _transport.connectionLost;

  /// Whether transport is connected.
  bool get isConnected => _transport.isConnected;

  /// Connect to the radio and start the companion session.
  Future<bool> connect({String appName = 'lusoapp'}) async {
    final ok = await _transport.connect();
    if (!ok) return false;

    _dataSub = _transport.dataStream.listen(_onData);

    // Send APP_START to initialize the companion session
    await _send(CompanionEncoder.appStart(appName));

    // Sync time
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _send(CompanionEncoder.setDeviceTime(now));

    return true;
  }

  /// Disconnect from the radio.
  Future<void> disconnect() async {
    await _dataSub?.cancel();
    _dataSub = null;
    await _transport.disconnect();
    _rxBuffer = Uint8List(0);
  }

  /// Dispose service and transport.
  Future<void> dispose() async {
    await disconnect();
    await _responseController.close();
    await _transport.dispose();
  }

  // --- Commands ---

  Future<void> requestContacts({int? sinceTimestamp}) async {
    await _send(CompanionEncoder.getContacts(sinceTimestamp: sinceTimestamp));
  }

  Future<void> sendPrivateMessage(
    Uint8List recipientPrefix,
    String text, {
    int attempt = 0,
    int? timestamp,
  }) async {
    await _send(
      CompanionEncoder.sendMessage(
        recipientPrefix,
        text,
        attempt: attempt,
        timestamp: timestamp,
      ),
    );
  }

  Future<void> sendChannelMessage(
    int channelIndex,
    String text, {
    int? timestamp,
  }) async {
    await _send(
      CompanionEncoder.sendChannelMessage(
        channelIndex,
        text,
        timestamp: timestamp,
      ),
    );
  }

  Future<void> syncNextMessage() async {
    await _send(CompanionEncoder.syncNext());
  }

  Future<void> sendAdvert({bool flood = false}) async {
    await _send(CompanionEncoder.sendAdvert(flood: flood));
  }

  Future<void> setAdvertName(String name) async {
    await _send(CompanionEncoder.setAdvertName(name));
  }

  Future<void> setRadioParams(RadioConfig config) async {
    await _send(CompanionEncoder.setRadioParams(config));
  }

  Future<void> setTxPower(int powerDbm) async {
    await _send(CompanionEncoder.setTxPower(powerDbm));
  }

  /// Experimental: change the wire-level path hash size used by sendFlood.
  /// [mode] is 0 (1-byte hops, default), 1 (2-byte), 2 (3-byte).
  /// Firmware v10+ only — older firmwares answer with ERR.
  Future<void> setPathHashMode(int mode) async {
    await _send(CompanionEncoder.setPathHashMode(mode));
  }

  Future<void> requestDeviceInfo({int appVersion = 3}) async {
    await _send(CompanionEncoder.deviceQuery(appVersion: appVersion));
  }

  Future<void> requestBattAndStorage() async {
    await _send(CompanionEncoder.getBattAndStorage());
  }

  /// Request one stats sub-type from the radio.
  ///
  /// Use [statsTypeCore], [statsTypeRadio], or [statsTypePackets].
  Future<void> requestStats(int subType) async {
    await _send(CompanionEncoder.getStats(subType));
  }

  Future<void> requestChannel(int index) async {
    await _send(CompanionEncoder.getChannel(index));
  }

  Future<void> setChannel(int index, String name, Uint8List secret) async {
    await _send(CompanionEncoder.setChannel(index, name, secret));
  }

  Future<void> addUpdateContact(Contact contact) async {
    await _send(CompanionEncoder.addUpdateContact(contact));
  }

  Future<void> removeContact(Uint8List publicKey) async {
    await _send(CompanionEncoder.removeContact(publicKey));
  }

  Future<void> resetPath(Uint8List publicKey) async {
    await _send(CompanionEncoder.resetPath(publicKey));
  }

  Future<void> sendPathDiscovery(Uint8List publicKey) async {
    await _send(CompanionEncoder.sendPathDiscoveryReq(publicKey));
  }

  Future<void> tracePath(int tag, {int authCode = 0, Uint8List? path}) async {
    await _send(
      CompanionEncoder.sendTracePath(tag: tag, authCode: authCode, path: path),
    );
  }

  Future<void> setLocation(double lat, double lon) async {
    await _send(CompanionEncoder.setAdvertLatLon(lat, lon));
  }

  /// Update the bundled "other params" frame (manual-add, telemetry mode,
  /// adv-loc-policy, multi-acks). All four are written atomically — the
  /// caller is responsible for passing the radio's current values for the
  /// fields it does not want to change.
  Future<void> setOtherParams({
    required int manualAddContacts,
    required int telemetryMode,
    required int advLocPolicy,
    required int multiAcks,
  }) async {
    await _send(
      CompanionEncoder.setOtherParams(
        manualAddContacts: manualAddContacts,
        telemetryMode: telemetryMode,
        advLocPolicy: advLocPolicy,
        multiAcks: multiAcks,
      ),
    );
  }

  Future<void> reboot() async {
    await _send(CompanionEncoder.reboot());
  }

  Future<void> requestAutoAddConfig() async {
    await _send(CompanionEncoder.getAutoAddConfig());
  }

  Future<void> setAutoAddConfig(int bitmask, int maxHops) async {
    await _send(CompanionEncoder.setAutoAddConfig(bitmask, maxHops));
  }

  /// Request the persisted default flood scope (firmware v11+).
  /// Returns null when unsupported, timed out, or no valid response arrived.
  Future<DefaultFloodScopeResponse?> requestDefaultFloodScope({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final wait = _waitForResponseWhere(
      (r) => r is DefaultFloodScopeResponse || r is ErrorResponse,
      timeout: timeout,
    );
    await _send(CompanionEncoder.getDefaultFloodScope());
    final resp = await wait;
    return resp is DefaultFloodScopeResponse ? resp : null;
  }

  /// Persist default flood scope region name (firmware v11+).
  ///
  /// Pass null/empty [regionName] to clear the persisted default scope.
  Future<bool> setDefaultFloodScope(
    String? regionName, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final trimmed = regionName?.trim() ?? '';
    final scopeKey = _deriveFloodScopeKey(trimmed);

    final wait = _waitForResponseWhere(
      (r) => r is OkResponse || r is ErrorResponse,
      timeout: timeout,
    );
    await _send(
      CompanionEncoder.setDefaultFloodScope(name: trimmed, scopeKey: scopeKey),
    );
    final resp = await wait;
    return resp is OkResponse;
  }

  /// Query a repeater for its configured region list via CMD_SEND_ANON_REQ.
  ///
  /// Returns null on timeout/parse errors; empty list means a valid reply with
  /// no discoverable regions.
  Future<List<String>?> requestRegions(
    Uint8List publicKey, {
    int pathLen = 0,
    Uint8List? pathBytes,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (publicKey.length < 32) {
      throw ArgumentError('publicKey must be at least 32 bytes');
    }

    final sentWait = _waitForResponseWhere(
      (r) => r is SentResponse || r is ErrorResponse,
      timeout: const Duration(seconds: 4),
    );
    await _send(
      CompanionEncoder.sendAnonRegionsReq(
        publicKey,
        pathLen: pathLen,
        pathBytes: pathBytes,
      ),
    );

    final sent = await sentWait;
    if (sent is! SentResponse) return null;
    if (!sent.expectsAck) return null;

    final binary = await _waitForResponseWhere(
      (r) => r is BinaryResponsePush && r.tag == sent.expectedAck,
      timeout:
          sent.suggestedTimeoutMs > 0
              ? Duration(milliseconds: sent.suggestedTimeoutMs + 3000)
              : timeout,
    );
    if (binary is! BinaryResponsePush) return null;
    return CompanionDecoder.parseRegionsFromBinaryResponse(binary.responseData);
  }

  /// Re-send APP_START so the radio replies with a fresh [SelfInfoResponse].
  /// Use this after operations that change the radio's identity (e.g. key import).
  Future<void> requestSelfInfo({String appName = 'lusoapp'}) async {
    await _send(CompanionEncoder.appStart(appName));
  }

  Future<void> requestPrivateKeyExport() async {
    await _send(CompanionEncoder.exportPrivateKey());
  }

  Future<void> importPrivateKey(Uint8List privateKey) async {
    await _send(CompanionEncoder.importPrivateKey(privateKey));
  }

  Future<void> login(Uint8List peerPublicKey, String password) async {
    await _send(CompanionEncoder.sendLogin(peerPublicKey, password));
  }

  /// Send a CLI admin command to a remote peer node.
  /// Must be called after a successful [login] to that peer.
  /// The response arrives as a [PrivateMessageResponse] on [responses].
  Future<void> sendAdminCommand(Uint8List pubKey, String command) async {
    final prefix = pubKey.sublist(0, pubKey.length < 6 ? pubKey.length : 6);
    await _send(CompanionEncoder.sendAdminCommand(prefix, command));
  }

  Future<void> sendStatusRequest(Uint8List pubKey) async {
    final payload = BytesBuilder();
    payload.add(pubKey.sublist(0, pubKey.length < 32 ? pubKey.length : 32));
    // Pad to 32 bytes
    if (pubKey.length < 32) payload.add(Uint8List(32 - pubKey.length));
    await _send(_buildFrame(cmdSendStatusReq, payload.toBytes()));
  }

  Future<void> sendTelemetryRequest(Uint8List pubKey) async {
    await _send(CompanionEncoder.sendTelemetryReq(pubKey));
  }

  /// Build a raw companion frame without going through CompanionEncoder.
  Uint8List _buildFrame(int command, Uint8List payload) {
    final totalLen = 1 + payload.length;
    final buf = BytesBuilder();
    buf.addByte(dirAppToRadio);
    final lenLsb = totalLen & 0xFF;
    final lenMsb = (totalLen >> 8) & 0xFF;
    if ((lenLsb | (lenMsb << 8)) != totalLen) {
      throw StateError('Invalid frame length encoding for $totalLen bytes');
    }
    buf.addByte(lenLsb);
    buf.addByte(lenMsb);
    buf.addByte(command);
    buf.add(payload);
    return buf.toBytes();
  }

  // --- Internal ---

  Future<void> _send(Uint8List data) async {
    Uint8List toSend;
    if (_transport.usesFraming) {
      // Serial/USB: send the full frame with direction+length header.
      toSend = data;
    } else {
      // BLE: strip the 3-byte direction+length header.
      // Encoder produces [dir][len_lsb][len_msb][cmd][payload...]
      // Firmware expects  [cmd][payload...]
      toSend = data.length > 3 ? data.sublist(3) : data;
    }
    _log.d(
      'TX: ${toSend.length} bytes, cmd=0x${toSend.isNotEmpty ? toSend[0].toRadixString(16).padLeft(2, "0") : "??"}',
    );
    await _transport.send(toSend);
  }

  void _onData(Uint8List data) {
    final hex = data
        .take(16)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(' ');
    _log.d('RX: ${data.length} bytes [$hex${data.length > 16 ? " ..." : ""}]');

    if (_transport.usesFraming) {
      // Serial/USB: accumulate bytes and extract direction+length frames.
      final newBuf = Uint8List(_rxBuffer.length + data.length);
      newBuf.setAll(0, _rxBuffer);
      newBuf.setAll(_rxBuffer.length, data);
      _rxBuffer = newBuf;

      final (frames, remaining) = CompanionDecoder.extractFrames(_rxBuffer);
      _rxBuffer = remaining;

      for (final frame in frames) {
        _decodeAndProcess(frame);
      }
    } else {
      // BLE: each notification IS one complete companion protocol frame.
      // No direction byte, no length header — just [cmd][payload...].
      _decodeAndProcess(data);
    }
  }

  void _decodeAndProcess(Uint8List frame) {
    _log.d(
      'Frame [${frame.length}B]: 0x${frame.isNotEmpty ? frame[0].toRadixString(16).padLeft(2, "0") : "--"}',
    );
    final response = CompanionDecoder.decode(frame);
    if (response != null) {
      _log.i('Decoded: ${response.runtimeType}');
      _processResponse(response);
      _responseController.add(response);
    }
  }

  void _processResponse(CompanionResponse response) {
    switch (response) {
      case SelfInfoResponse(:final info):
        selfInfo = info;
        radioConfig = info.radioConfig;
        _log.i('Self: ${info.name}');
      case ContactsStartResponse():
        contacts.clear();
      case ContactResponse(:final contact):
        final idx = contacts.indexWhere(
          (c) => _keysEqual(c.publicKey, contact.publicKey),
        );
        if (idx >= 0) {
          contacts[idx] = contact;
        } else {
          contacts.add(contact);
        }
      case ContactDeletedPush():
        // Radio confirmed deletion — handled in the provider layer.
        break;
      case ChannelInfoResponse(:final channel):
        final idx = channels.indexWhere((c) => c.index == channel.index);
        if (idx >= 0) {
          channels[idx] = channel;
        } else {
          channels.add(channel);
        }
      case BattAndStorageResponse(:final batteryMv):
        this.batteryMv = batteryMv;
      case DeviceInfoResponse(:final info):
        deviceInfo = info;
      case MsgWaitingPush():
        // Start draining the offline queue.
        _safeSyncNextMessage();
      case PrivateMessageResponse():
      case ChannelMessageResponse():
        // Continue draining — firmware sends one message per syncNext.
        // Keep calling until NoMoreMessagesResponse.
        _safeSyncNextMessage();
      case NoMoreMessagesResponse():
        // Queue drained — nothing to do.
        break;
      default:
        break;
    }
  }

  /// Fire-and-forget syncNext for queue draining. Disconnect races are expected
  /// here, so "Not connected" errors are swallowed to avoid unhandled async
  /// exceptions in the VM error log.
  void _safeSyncNextMessage() {
    unawaited(_syncNextMessageGuarded());
  }

  Future<void> _syncNextMessageGuarded() async {
    if (!isConnected) return;
    try {
      await syncNextMessage();
    } catch (e) {
      // During teardown, a late RX frame may still trigger queue draining
      // after transport has disconnected. Treat as benign.
      if (e is StateError && !isConnected) return;
      rethrow;
    }
  }

  Future<CompanionResponse?> _waitForResponseWhere(
    bool Function(CompanionResponse) matcher, {
    required Duration timeout,
  }) async {
    final completer = Completer<CompanionResponse?>();
    late final StreamSubscription<CompanionResponse> sub;
    sub = responses.listen((response) {
      if (!completer.isCompleted && matcher(response)) {
        completer.complete(response);
        sub.cancel();
      }
    });
    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      await sub.cancel();
      return null;
    }
  }

  Uint8List _deriveFloodScopeKey(String regionName) {
    final trimmed = regionName.trim();
    if (trimmed.isEmpty) return Uint8List(16);
    final normalized = trimmed.startsWith('#') ? trimmed : '#$trimmed';
    final digest = sha256.convert(utf8.encode(normalized));
    return Uint8List.fromList(digest.bytes.sublist(0, 16));
  }

  bool _keysEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
