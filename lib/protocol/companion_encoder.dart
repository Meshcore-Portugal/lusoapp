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

  /// GET_BATT_AND_STORAGE — query battery and storage info.
  static Uint8List getBattAndStorage() => _frame(cmdGetBattAndStorage);

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

  /// ADD_UPDATE_CONTACT — add or update a contact entry.
  /// Spec: {code, pub_key(32), type, flags, out_path_len, out_path(64),
  ///        adv_name(32, null-padded), last_advert(uint32),
  ///        adv_lat(int32, opt), adv_lon(int32, opt)}
  static Uint8List addUpdateContact({
    required Uint8List publicKey,
    required int type,
    required int flags,
    required int outPathLen,
    required Uint8List outPath,
    required String name,
    required int lastAdvert,
    double? latitude,
    double? longitude,
  }) {
    final payload = BytesBuilder();
    payload.add(publicKey.sublist(0, 32));
    payload.addByte(type);
    payload.addByte(flags);
    payload.addByte(outPathLen & 0xFF);
    final pathBuf = Uint8List(64);
    final copyLen = outPath.length < 64 ? outPath.length : 64;
    pathBuf.setRange(0, copyLen, outPath);
    payload.add(pathBuf);
    final nameBytes = utf8.encode(name);
    final nameBuf = Uint8List(32);
    final nameCopyLen = nameBytes.length < 32 ? nameBytes.length : 32;
    nameBuf.setRange(0, nameCopyLen, nameBytes);
    payload.add(nameBuf);
    payload.add(_uint32LE(lastAdvert));
    if (latitude != null && longitude != null) {
      payload.add(_int32LE((latitude * 1e6).round()));
      payload.add(_int32LE((longitude * 1e6).round()));
    }
    return _frame(cmdAddUpdateContact, payload.toBytes());
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
