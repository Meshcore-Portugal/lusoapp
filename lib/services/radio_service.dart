import 'dart:async';
import 'dart:typed_data';

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
  Future<bool> connect({String appName = 'MCAPPPT'}) async {
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
  }) async {
    await _send(
      CompanionEncoder.sendMessage(recipientPrefix, text, attempt: attempt),
    );
  }

  Future<void> sendChannelMessage(int channelIndex, String text) async {
    await _send(CompanionEncoder.sendChannelMessage(channelIndex, text));
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

  Future<void> requestDeviceInfo({int appVersion = 3}) async {
    await _send(CompanionEncoder.deviceQuery(appVersion: appVersion));
  }

  Future<void> requestBattAndStorage() async {
    await _send(CompanionEncoder.getBattAndStorage());
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

  Future<void> tracePath(int tag, {int authCode = 0, Uint8List? path}) async {
    await _send(
      CompanionEncoder.sendTracePath(tag: tag, authCode: authCode, path: path),
    );
  }

  Future<void> setLocation(double lat, double lon) async {
    await _send(CompanionEncoder.setAdvertLatLon(lat, lon));
  }

  Future<void> reboot() async {
    await _send(CompanionEncoder.reboot());
  }

  Future<void> login(Uint8List peerPublicKey, String password) async {
    await _send(CompanionEncoder.sendLogin(peerPublicKey, password));
  }

  Future<void> sendStatusRequest(Uint8List pubKey) async {
    final payload = BytesBuilder();
    payload.add(pubKey.sublist(0, pubKey.length < 32 ? pubKey.length : 32));
    // Pad to 32 bytes
    if (pubKey.length < 32) payload.add(Uint8List(32 - pubKey.length));
    await _send(_buildFrame(cmdSendStatusReq, payload.toBytes()));
  }

  /// Build a raw companion frame without going through CompanionEncoder.
  Uint8List _buildFrame(int command, Uint8List payload) {
    final totalLen = 1 + payload.length;
    final buf = BytesBuilder();
    buf.addByte(dirAppToRadio);
    buf.addByte(totalLen & 0xFF);
    buf.addByte((totalLen >> 8) & 0xFF);
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
        syncNextMessage();
      case PrivateMessageResponse():
      case ChannelMessageResponse():
        // Continue draining — firmware sends one message per syncNext.
        // Keep calling until NoMoreMessagesResponse.
        syncNextMessage();
      case NoMoreMessagesResponse():
        // Queue drained — nothing to do.
        break;
      default:
        break;
    }
  }

  bool _keysEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
