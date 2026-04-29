import 'dart:convert';
import 'dart:typed_data';

import 'commands.dart';
import 'models.dart';

/// Encodes companion protocol frames (App → Radio).
///
/// Frame format: `[direction '<'][lengthLSB][lengthMSB][payload...]`
class CompanionEncoder {
  /// Build a raw companion frame.
  static Uint8List _frame(int command, [Uint8List? payload]) {
    final payloadData = payload ?? Uint8List(0);
    final totalLen = 1 + payloadData.length; // command + payload
    if (totalLen > maxPayload) {
      throw ArgumentError('Payload exceeds max size ($maxPayload bytes)');
    }
    final buf = BytesBuilder();
    buf.addByte(dirAppToRadio);
    buf.addByte(totalLen & 0xFF);
    buf.addByte((totalLen >> 8) & 0xFF);
    buf.addByte(command);
    buf.add(payloadData);
    return buf.toBytes();
  }

  /// APP_START — initialize connection with the radio.
  static Uint8List appStart(String appName) {
    final reserved = Uint8List(7);
    final nameBytes = utf8.encode(appName);
    final payload = BytesBuilder();
    payload.add(reserved);
    payload.add(nameBytes);
    return _frame(cmdAppStart, payload.toBytes());
  }

  /// SEND_MSG (CLI) — send a remote admin command to a peer node.
  /// Uses TXT_TYPE_CLI_DATA (1) so the receiving firmware routes it to
  /// handleCommand() instead of displaying it as chat text.
  static Uint8List sendAdminCommand(
    Uint8List recipientPrefix,
    String command, {
    int? timestamp,
  }) {
    final ts = timestamp ?? _nowEpoch();
    final payload = BytesBuilder();
    payload.addByte(txtCliData);
    payload.addByte(0); // attempt
    payload.add(_uint32LE(ts));
    payload.add(recipientPrefix.sublist(0, 6));
    payload.add(utf8.encode(command));
    return _frame(cmdSendMsg, payload.toBytes());
  }

  /// SEND_MSG — send a private text message.
  static Uint8List sendMessage(
    Uint8List recipientPrefix,
    String text, {
    int attempt = 0,
    int? timestamp,
  }) {
    final ts = timestamp ?? _nowEpoch();
    final payload = BytesBuilder();
    payload.addByte(txtPlain);
    payload.addByte(attempt);
    payload.add(_uint32LE(ts));
    payload.add(recipientPrefix.sublist(0, 6));
    payload.add(utf8.encode(text));
    return _frame(cmdSendMsg, payload.toBytes());
  }

  /// SEND_CHAN_MSG — send a channel text message.
  static Uint8List sendChannelMessage(
    int channelIndex,
    String text, {
    int? timestamp,
  }) {
    final ts = timestamp ?? _nowEpoch();
    final payload = BytesBuilder();
    payload.addByte(txtPlain);
    payload.addByte(channelIndex);
    payload.add(_uint32LE(ts));
    payload.add(utf8.encode(text));
    return _frame(cmdSendChanMsg, payload.toBytes());
  }

  /// GET_CONTACTS — request the full contact list.
  static Uint8List getContacts({int? sinceTimestamp}) {
    if (sinceTimestamp != null) {
      return _frame(cmdGetContacts, _uint32LE(sinceTimestamp));
    }
    return _frame(cmdGetContacts);
  }

  /// GET_DEVICE_TIME — query the radio's clock.
  static Uint8List getDeviceTime() => _frame(cmdGetDeviceTime);

  /// SET_DEVICE_TIME — set the radio's clock.
  static Uint8List setDeviceTime(int timestamp) {
    return _frame(cmdSetDeviceTime, _uint32LE(timestamp));
  }

  /// SEND_ADVERT — broadcast node identity.
  static Uint8List sendAdvert({bool flood = false}) {
    return _frame(cmdSendAdvert, Uint8List.fromList([flood ? 1 : 0]));
  }

  /// SET_ADVERT_NAME — set display name.
  static Uint8List setAdvertName(String name) {
    return _frame(cmdSetAdvertName, Uint8List.fromList(utf8.encode(name)));
  }

  /// SYNC_NEXT — get next pending message.
  static Uint8List syncNext() => _frame(cmdSyncNext);

  /// SET_RADIO_PARAMS — configure LoRa radio.
  static Uint8List setRadioParams(RadioConfig config) {
    final payload = BytesBuilder();
    payload.add(_uint32LE(config.frequencyHz));
    payload.add(_uint32LE(config.bandwidthHz));
    payload.addByte(config.spreadingFactor);
    payload.addByte(config.codingRate);
    return _frame(cmdSetRadioParams, payload.toBytes());
  }

  /// SET_TX_POWER — set transmit power.
  static Uint8List setTxPower(int powerDbm) {
    return _frame(cmdSetTxPower, Uint8List.fromList([powerDbm & 0xFF]));
  }

  /// SET_PATH_HASH_MODE — experimental path hash width.
  /// [mode] is 0 (1-byte), 1 (2-byte) or 2 (3-byte). Firmware rejects >= 3.
  /// Wire format: `[cmd, 0x00 reserved, mode]`.
  static Uint8List setPathHashMode(int mode) {
    return _frame(cmdSetPathHashMode, Uint8List.fromList([0x00, mode & 0xFF]));
  }

  /// GET_BATT_AND_STORAGE — query battery and storage info.
  static Uint8List getBattAndStorage() => _frame(cmdGetBattAndStorage);

  /// GET_STATS — request statistics from the radio.
  ///
  /// [subType] must be one of [statsTypeCore], [statsTypeRadio], or
  /// [statsTypePackets].
  static Uint8List getStats(int subType) {
    return _frame(cmdGetStats, Uint8List.fromList([subType]));
  }

  /// DEVICE_QUERY — get device info.
  static Uint8List deviceQuery({int appVersion = 3}) {
    return _frame(cmdDeviceQuery, Uint8List.fromList([appVersion]));
  }

  /// GET_CHANNEL — get channel info by index.
  static Uint8List getChannel(int index) {
    return _frame(cmdGetChannel, Uint8List.fromList([index]));
  }

  /// SET_CHANNEL — create or update a channel.
  /// Name is null-padded to 32 bytes; secret must be exactly 16 bytes.
  static Uint8List setChannel(int index, String name, Uint8List secret) {
    if (secret.length != 16) {
      throw ArgumentError('Channel secret must be exactly 16 bytes');
    }
    final payload = BytesBuilder();
    payload.addByte(index);
    final nameBytes = utf8.encode(name);
    final nameBuf = Uint8List(32);
    final copyLen = nameBytes.length < 32 ? nameBytes.length : 32;
    nameBuf.setRange(0, copyLen, nameBytes);
    payload.add(nameBuf);
    payload.add(secret);
    return _frame(cmdSetChannel, payload.toBytes());
  }

  /// REBOOT — restart the radio.
  /// Spec: cmd byte followed by ASCII text "reboot".
  static Uint8List reboot() =>
      _frame(cmdReboot, Uint8List.fromList(utf8.encode('reboot')));

  /// ADD_UPDATE_CONTACT — manually add or update a contact entry on the radio.
  /// Builds the full 147-byte contact struct that mirrors the radio's storage layout.
  static Uint8List addUpdateContact(Contact contact) {
    final payload = BytesBuilder();
    // bytes 0-31: public key (32 bytes, zero-padded if shorter)
    final pubKeyBuf = Uint8List(32);
    final keyLen =
        contact.publicKey.length < 32 ? contact.publicKey.length : 32;
    pubKeyBuf.setRange(0, keyLen, contact.publicKey);
    payload.add(pubKeyBuf);
    // byte 32: type
    payload.addByte(contact.type);
    // byte 33: flags
    payload.addByte(contact.flags);
    // byte 34: pathLen
    payload.addByte(contact.pathLen);
    // bytes 35-98: path (64 bytes, zeros for manually added contacts)
    payload.add(Uint8List(64));
    // bytes 99-130: name (UTF-8, null-padded to 32 bytes)
    final nameBytes = utf8.encode(contact.name);
    final nameBuf = Uint8List(32);
    final nameCopyLen = nameBytes.length < 32 ? nameBytes.length : 32;
    nameBuf.setRange(0, nameCopyLen, nameBytes);
    payload.add(nameBuf);
    // bytes 131-134: lastAdvert timestamp
    payload.add(_uint32LE(contact.lastAdvertTimestamp));
    // bytes 135-138: latitude (int32 LE, scaled by 1e6)
    payload.add(_int32LE(((contact.latitude ?? 0.0) * 1e6).round()));
    // bytes 139-142: longitude (int32 LE, scaled by 1e6)
    payload.add(_int32LE(((contact.longitude ?? 0.0) * 1e6).round()));
    // bytes 143-146: lastModified
    payload.add(_uint32LE(contact.lastModified ?? _nowEpoch()));
    return _frame(cmdAddUpdateContact, payload.toBytes());
  }

  /// REMOVE_CONTACT — delete a contact by public key.
  static Uint8List removeContact(Uint8List publicKey) {
    return _frame(cmdRemoveContact, publicKey);
  }

  /// RESET_PATH — clear cached path to a contact.
  static Uint8List resetPath(Uint8List publicKey) {
    return _frame(cmdResetPath, publicKey);
  }

  /// SEND_TRACE_PATH — initiate a trace along a given path.
  /// Spec: {code, tag: int32, auth_code: int32, flags: byte, path: bytes}
  /// [tag] is a random 32-bit value set by the initiator, reflected in PUSH_CODE_TRACE_DATA.
  /// [authCode] is optional authentication (use 0 for unauthenticated traces).
  /// [path] is the sequence of path-hashes the trace should follow (empty = direct).
  static Uint8List sendTracePath({
    required int tag,
    int authCode = 0,
    Uint8List? path,
  }) {
    final payload = BytesBuilder();
    payload.add(_int32LE(tag));
    payload.add(_int32LE(authCode));
    payload.addByte(0); // flags: zero for now
    if (path != null) {
      payload.add(path);
    }
    return _frame(cmdSendTracePath, payload.toBytes());
  }

  /// SET_ADVERT_LATLON — set GPS coordinates.
  static Uint8List setAdvertLatLon(double lat, double lon) {
    final payload = BytesBuilder();
    payload.add(_int32LE((lat * 1e6).round()));
    payload.add(_int32LE((lon * 1e6).round()));
    return _frame(cmdSetAdvertLatLon, payload.toBytes());
  }

  /// SET_OTHER_PARAMS (0x26) — update the four bundled radio prefs in one frame.
  ///
  /// Layout (per `MyMesh.cpp` `CMD_SET_OTHER_PARAMS`):
  ///   [0] cmd                        (handled by `_frame`)
  ///   [1] manualAddContacts          (uint8, 0/1)
  ///   [2] telemetryMode bitfield     (env<<4 | loc<<2 | base)
  ///   [3] advLocPolicy               (0 = never, 1 = every advert)
  ///   [4] multiAcks                  (uint8, v7+)
  ///
  /// Callers MUST pass the radio's current values for fields they don't
  /// want to change — this is a write-all command, not a partial update.
  static Uint8List setOtherParams({
    required int manualAddContacts,
    required int telemetryMode,
    required int advLocPolicy,
    required int multiAcks,
  }) {
    final payload = BytesBuilder();
    payload.addByte(manualAddContacts & 0xFF);
    payload.addByte(telemetryMode & 0xFF);
    payload.addByte(advLocPolicy & 0xFF);
    payload.addByte(multiAcks & 0xFF);
    return _frame(cmdSetOtherParams, payload.toBytes());
  }

  /// SHARE_CONTACT — share a contact via radio broadcast.
  static Uint8List shareContact(Uint8List publicKey) {
    return _frame(cmdShareContact, publicKey.sublist(0, 32));
  }

  /// EXPORT_CONTACT — export a contact card. Omit key to export self.
  static Uint8List exportContact([Uint8List? publicKey]) {
    if (publicKey != null) {
      return _frame(cmdExportContact, publicKey.sublist(0, 32));
    }
    return _frame(cmdExportContact);
  }

  /// IMPORT_CONTACT — import a contact from card data.
  static Uint8List importContact(Uint8List cardData) {
    return _frame(cmdImportContact, cardData);
  }

  /// SET_TUNING_PARAMS — configure timing parameters.
  /// Spec: {code, rxdelay_base: uint32, airtime_factor: uint32, reserved: 8 zero bytes}
  /// Values are pre-multiplied by 1000 (e.g. rxDelay of 1.5 -> pass 1500).
  static Uint8List setTuningParams({
    required int rxDelayBase,
    required int airtimeFactor,
  }) {
    final payload = BytesBuilder();
    payload.add(_uint32LE(rxDelayBase));
    payload.add(_uint32LE(airtimeFactor));
    payload.add(Uint8List(8)); // reserved
    return _frame(cmdSetTuningParams, payload.toBytes());
  }

  /// SEND_STATUS_REQ — request status from a node.
  static Uint8List sendStatusReq(Uint8List publicKey) {
    return _frame(cmdSendStatusReq, publicKey.sublist(0, 32));
  }

  /// SEND_LOGIN — authenticate with a repeater or room server.
  /// Spec: {code, pub_key: bytes(32), password: varchar}
  /// [peerPublicKey] is the 32-byte public key of the target repeater/room server.
  static Uint8List sendLogin(Uint8List peerPublicKey, String password) {
    if (peerPublicKey.length < 32) {
      throw ArgumentError('peerPublicKey must be at least 32 bytes');
    }
    final payload = BytesBuilder();
    payload.add(peerPublicKey.sublist(0, 32));
    payload.add(utf8.encode(password));
    return _frame(cmdSendLogin, payload.toBytes());
  }

  /// GET_BY_KEY — look up a contact by public key.
  static Uint8List getByKey(Uint8List publicKey) {
    return _frame(cmdGetByKey, publicKey.sublist(0, 32));
  }

  /// SIGN_DATA — send a chunk of data to be signed.
  /// Call multiple times for large payloads, then call signFinish().
  static Uint8List signData(Uint8List data) {
    return _frame(cmdSignData, data);
  }

  /// SIGN_FINISH — finalize signing and get RESP_CODE_SIGNATURE back.
  static Uint8List signFinish() => _frame(cmdSignFinish);

  /// EXPORT_PRIVATE_KEY — request the radio to return its 64-byte private key.
  /// Requires the firmware to be compiled with ENABLE_PRIVATE_KEY_EXPORT=1.
  /// Radio replies with RESP_CODE_PRIVATE_KEY (0x0E) containing 64 raw bytes,
  /// or RESP_CODE_ERR if the feature is disabled.
  static Uint8List exportPrivateKey() => _frame(cmdExportPrivateKey);

  /// IMPORT_PRIVATE_KEY — write a 64-byte private key to the radio.
  /// Requires the firmware to be compiled with ENABLE_PRIVATE_KEY_IMPORT=1.
  /// [privateKey] must be exactly 64 bytes.
  /// Radio replies with RESP_CODE_OK on success, or RESP_CODE_ERR on failure.
  static Uint8List importPrivateKey(Uint8List privateKey) {
    if (privateKey.length != 64) {
      throw ArgumentError('Private key must be exactly 64 bytes');
    }
    return _frame(cmdImportPrivateKey, privateKey);
  }

  /// SEND_TELEMETRY_REQ — request telemetry from a node.
  /// Spec: {code, reserved(3), pub_key(32)}
  static Uint8List sendTelemetryReq(Uint8List publicKey) {
    final payload = BytesBuilder();
    payload.add(Uint8List(3)); // reserved
    payload.add(publicKey.sublist(0, 32));
    return _frame(cmdSendTelemetryReq, payload.toBytes());
  }

  /// SEND_BINARY_REQ — send a binary request to a node.
  /// Spec: {code, pub_key(32), request_code_and_params(variable)}
  static Uint8List sendBinaryReq(Uint8List publicKey, Uint8List requestData) {
    final payload = BytesBuilder();
    payload.add(publicKey.sublist(0, 32));
    payload.add(requestData);
    return _frame(cmdSendBinaryReq, payload.toBytes());
  }

  /// SEND_PATH_DISCOVERY_REQ — flood the network to discover a path to a contact.
  /// Spec: {code, reserved(1)=0, pub_key(32)}
  /// The radio responds with RESP_CODE_SENT, then later with
  /// PUSH_CODE_PATH_DISCOVERY_RESPONSE (0x8D) when a response is received.
  static Uint8List sendPathDiscoveryReq(Uint8List publicKey) {
    final payload = BytesBuilder();
    payload.addByte(0); // reserved
    payload.add(publicKey.sublist(0, 32));
    return _frame(cmdSendPathDiscoveryReq, payload.toBytes());
  }

  /// SEND_CONTROL_DATA — send control data with a sub-type.
  /// Spec: {code, flags(0), sub_type, payload(variable)}
  static Uint8List sendControlData({required int subType, Uint8List? payload}) {
    final buf = BytesBuilder();
    buf.addByte(0); // flags: must be zero
    buf.addByte(subType);
    if (payload != null) {
      buf.add(payload);
    }
    return _frame(cmdSendControlData, buf.toBytes());
  }

  /// GET_AUTOADD_CONFIG — read the radio's auto-add bitmask and max-hops.
  static Uint8List getAutoAddConfig() => _frame(cmdGetAutoAddConfig);

  /// SET_AUTOADD_CONFIG — write the radio's auto-add bitmask and max-hops.
  ///
  /// [bitmask] is a combination of [autoAddChat], [autoAddRepeater], etc.
  /// [maxHops] : 0 = no limit, 1 = direct only (0 hops), N = up to N-1 hops.
  static Uint8List setAutoAddConfig(int bitmask, int maxHops) {
    return _frame(
      cmdSetAutoAddConfig,
      Uint8List.fromList([bitmask & 0xFF, maxHops & 0xFF]),
    );
  }

  // --- Utility ---

  static int _nowEpoch() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  static Uint8List _uint32LE(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    return data.buffer.asUint8List();
  }

  static Uint8List _int32LE(int value) {
    final data = ByteData(4)..setInt32(0, value, Endian.little);
    return data.buffer.asUint8List();
  }
}
