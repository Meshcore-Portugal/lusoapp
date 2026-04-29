import 'dart:convert';
import 'dart:typed_data';

import 'package:logger/logger.dart';

import 'commands.dart';
import 'companion_responses.dart';
import 'models.dart';

export 'companion_responses.dart';

final _log = Logger(printer: SimplePrinter(printTime: false));

/// Parses companion protocol responses (Radio → App).
class CompanionDecoder {
  /// Decode radio bytes to a Dart string and replace any lone UTF-16
  /// surrogates with U+FFFD.  WTF-8 sequences (e.g. 0xED 0xA0 0x80 = U+D800)
  /// survive [utf8.decode] with allowMalformed:true as real lone surrogates,
  /// which Flutter's TextPainter rejects with "not well-formed UTF-16".
  static String _decodeRadioString(List<int> bytes) {
    final s = utf8.decode(bytes, allowMalformed: true);
    // Fast path: scan once; if no surrogate range found, return as-is.
    for (var i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (c >= 0xD800 && c <= 0xDFFF) {
        // Slow path: rebuild, replacing every lone surrogate with U+FFFD.
        final buf = StringBuffer();
        for (var j = 0; j < s.length; j++) {
          final u = s.codeUnitAt(j);
          if (u >= 0xD800 && u <= 0xDBFF) {
            // High surrogate — valid only when followed by a low surrogate.
            if (j + 1 < s.length) {
              final u2 = s.codeUnitAt(j + 1);
              if (u2 >= 0xDC00 && u2 <= 0xDFFF) {
                buf.write(s[j]);
                buf.write(s[j + 1]);
                j++;
                continue;
              }
            }
            buf.writeCharCode(0xFFFD);
          } else if (u >= 0xDC00 && u <= 0xDFFF) {
            buf.writeCharCode(0xFFFD); // lone low surrogate
          } else {
            buf.write(s[j]);
          }
        }
        return buf.toString();
      }
    }
    return s;
  }

  /// Decode a raw response frame payload (after direction + length stripped).
  /// Returns a [CompanionResponse] or null if unrecognized.
  static CompanionResponse? decode(Uint8List payload) {
    if (payload.isEmpty) return null;
    final code = payload[0];
    final data = payload.length > 1 ? payload.sublist(1) : Uint8List(0);

    switch (code) {
      case respOk:
        return const OkResponse();
      case respErr:
        return ErrorResponse(data.isNotEmpty ? data[0] : 0);
      case respContactsStart:
        return const ContactsStartResponse();
      case respContact:
        return _parseContact(data);
      case respEndContacts:
        return const EndContactsResponse();
      case respSelfInfo:
        return _parseSelfInfo(data);
      case respSent:
        return _parseSentResponse(data);
      case respContactMsgRecv:
        return _parsePrivateMessage(data);
      case respContactMsgRecvV3:
        return _parsePrivateMessageV3(data);
      case respChannelMsgRecv:
        return _parseChannelMessage(data);
      case respChannelMsgRecvV3:
        return _parseChannelMessageV3(data);
      case respCurrTime:
        return _parseCurrTime(data);
      case respNoMoreMessages:
        return const NoMoreMessagesResponse();
      case respBattAndStorage:
        return _parseBattAndStorage(data);
      case respDeviceInfo:
        return _parseDeviceInfo(data);
      case respPrivateKey:
        return _parsePrivateKey(data);
      case respChannelInfo:
        return _parseChannelInfo(data);
      case respSignature:
        return _parseSignature(data);
      case respStats:
        return _parseStats(data);
      // Unsolicited push codes
      case pushAdvert:
      case pushNewAdvert:
        return _parseAdvertPush(data, isNew: code == pushNewAdvert);
      case pushPathUpdated:
        return PathUpdatedPush(data);
      case pushSendConfirmed:
        return const SendConfirmedPush();
      case pushMsgWaiting:
        return const MsgWaitingPush();
      case pushLoginSuccess:
        return const LoginSuccessPush();
      case pushLoginFail:
        return const LoginFailPush();
      case pushTraceData:
        return TraceDataPush(data);
      case pushTelemetryResponse:
        return TelemetryPush(data);
      case pushBinaryResponse:
        return _parseBinaryResponse(data);
      case pushPathDiscoveryResponse:
        return _parsePathDiscovery(data);
      case pushControlData:
        return _parseControlData(data);
      case pushContactDeleted:
        return const ContactDeletedPush();
      case pushContactsFull:
        return const ContactsFullPush();
      case pushLogRxData:
        return LogRxDataPush(data);
      case pushStatusResponse:
        return StatusResponsePush(data);
      case pushRawData:
        return RawDataPush(data);
      case respAutoAddConfig:
        if (data.length < 2) return null;
        return AutoAddConfigResponse(bitmask: data[0], maxHops: data[1]);
      default:
        _log.w('Unknown response code: 0x${code.toRadixString(16)}');
        return UnknownResponse(code, data);
    }
  }

  /// Extract frames from a raw byte stream.
  /// Returns (frames, remainingBytes).
  static (List<Uint8List>, Uint8List) extractFrames(Uint8List buffer) {
    final frames = <Uint8List>[];
    var offset = 0;

    while (offset < buffer.length) {
      // Find direction marker
      if (buffer[offset] != dirRadioToApp) {
        offset++;
        continue;
      }
      if (offset + 3 > buffer.length) break; // Need at least dir + 2 len bytes

      final lenLSB = buffer[offset + 1];
      final lenMSB = buffer[offset + 2];
      final payloadLen = lenLSB | (lenMSB << 8);

      if (payloadLen == 0 || payloadLen > maxPayload) {
        offset++;
        continue;
      }

      final frameEnd = offset + 3 + payloadLen;
      if (frameEnd > buffer.length) break; // Incomplete frame

      frames.add(buffer.sublist(offset + 3, frameEnd));
      offset = frameEnd;
    }

    final remaining =
        offset < buffer.length ? buffer.sublist(offset) : Uint8List(0);
    return (frames, remaining);
  }

  // --- Private parsers ---

  static ContactResponse? _parseContact(Uint8List data) {
    if (data.length < 78) return null; // Minimum contact size
    final pubKey = Uint8List.fromList(data.sublist(0, 32));
    final type = data[32];
    final flags = data[33];
    final pathLen = data[34];
    // Path is 64 bytes at offset 35..98
    final nameEnd = _findNullTerminator(data, 99, 131);
    final name = _decodeRadioString(data.sublist(99, nameEnd));
    final lastAdvert = _readUint32LE(data, 131);
    double? lat;
    double? lon;
    if (data.length >= 143) {
      lat = _readInt32LE(data, 135) / 1e6;
      lon = _readInt32LE(data, 139) / 1e6;
    }
    int? lastMod;
    if (data.length >= 147) {
      lastMod = _readUint32LE(data, 143);
    }
    return ContactResponse(
      Contact(
        publicKey: pubKey,
        type: type,
        flags: flags,
        pathLen: pathLen,
        name: name.trim(),
        lastAdvertTimestamp: lastAdvert,
        latitude: lat,
        longitude: lon,
        lastModified: lastMod,
      ),
    );
  }

  static SelfInfoResponse? _parseSelfInfo(Uint8List data) {
    // Spec layout (after packet type 0x05 stripped):
    // data[0] = adv_type, data[1] = tx_power, data[2] = max_tx_power
    // data[3..34] = public_key (32 bytes)
    // data[35..38] = latitude (int32 LE, /1e6)
    // data[39..42] = longitude (int32 LE, /1e6)
    // data[43] = multi_acks, data[44] = adv_loc_policy
    // data[45] = telemetry_mode, data[46] = manual_add_contacts
    // data[47..50] = radio_freq (uint32 LE)
    // data[51..54] = radio_bw (uint32 LE)
    // data[55] = radio_sf, data[56] = radio_cr
    // data[57+] = device name (UTF-8)
    if (data.length < 57) return null;

    final advType = data[0];
    final txPower = data[1];
    final maxTxPower = data[2];
    final pubKey = Uint8List.fromList(data.sublist(3, 35));
    final lat = _readInt32LE(data, 35) / 1e6;
    final lon = _readInt32LE(data, 39) / 1e6;

    final radioFreq = _readUint32LE(data, 47);
    final radioBw = _readUint32LE(data, 51);
    final radioSf = data[55];
    final radioCr = data[56];

    String name = '';
    if (data.length > 57) {
      final nameEnd = _findNullTerminator(data, 57, data.length);
      name = _decodeRadioString(data.sublist(57, nameEnd)).trim();
    }

    final config = RadioConfig(
      frequencyHz: radioFreq,
      bandwidthHz: radioBw,
      spreadingFactor: radioSf,
      codingRate: radioCr,
      txPowerDbm: txPower,
    );

    return SelfInfoResponse(
      SelfInfo(
        publicKey: pubKey,
        name: name,
        radioConfig: config,
        advType: advType,
        txPower: txPower,
        maxTxPower: maxTxPower,
        latitude: lat,
        longitude: lon,
      ),
    );
  }

  /// Parse RESP_CODE_SENT (0x06): route_flag, expected_ack, est_timeout
  static SentResponse _parseSentResponse(Uint8List data) {
    final routeFlag = data.isNotEmpty ? data[0] : 0;
    return SentResponse(routeFlag: routeFlag);
  }

  static PrivateMessageResponse _parsePrivateMessageV3(Uint8List data) {
    // V3 format (after packet type 0x10 stripped):
    // data[0] = SNR (signed byte, /4.0)
    // data[1..2] = Reserved
    // data[3..8] = Public Key Prefix (6 bytes)
    // data[9] = Path Length
    // data[10] = Text Type
    // data[11..14] = Timestamp (uint32 LE)
    // data[15..18] = Signature (4 bytes, only if txt_type == 2)
    // data[15+] or data[19+] = Message Text
    if (data.length < 15) {
      return const PrivateMessageResponse(
        ChatMessage(text: '', timestamp: 0, isOutgoing: false),
      );
    }

    final snrByte = data[0];
    final snr = (snrByte < 128 ? snrByte : snrByte - 256) / 4.0;
    final senderKey = Uint8List.fromList(data.sublist(3, 9));
    final pathLen = data[9];
    final txtType = data[10];
    final timestamp = _readUint32LE(data, 11);

    var textOffset = 15;
    if (txtType == 2 && data.length >= 19) {
      textOffset = 19; // skip 4-byte signature
    }

    final text =
        data.length > textOffset
            ? _decodeRadioString(data.sublist(textOffset))
            : '';

    return PrivateMessageResponse(
      ChatMessage(
        text: text,
        timestamp: timestamp,
        isOutgoing: false,
        senderKey: senderKey,
        snr: snr,
        pathLen: pathLen,
        isCliResponse: txtType == 1,
      ),
    );
  }

  static PrivateMessageResponse _parsePrivateMessage(Uint8List data) {
    // Standard format (after packet type 0x07 stripped):
    // data[0..5] = Public Key Prefix (6 bytes)
    // data[6] = Path Length
    // data[7] = Text Type
    // data[8..11] = Timestamp (uint32 LE)
    // data[12..15] = Signature (4 bytes, only if txt_type == 2)
    // data[12+] or data[16+] = Message Text
    if (data.length < 12) {
      return const PrivateMessageResponse(
        ChatMessage(text: '', timestamp: 0, isOutgoing: false),
      );
    }

    final senderKey = Uint8List.fromList(data.sublist(0, 6));
    final pathLen = data[6];
    final txtType = data[7];
    final timestamp = _readUint32LE(data, 8);

    var textOffset = 12;
    if (txtType == 2 && data.length >= 16) {
      textOffset = 16; // skip 4-byte signature
    }

    final text =
        data.length > textOffset
            ? _decodeRadioString(data.sublist(textOffset))
            : '';

    return PrivateMessageResponse(
      ChatMessage(
        text: text,
        timestamp: timestamp,
        isOutgoing: false,
        senderKey: senderKey,
        pathLen: pathLen,
        isCliResponse: txtType == 1,
      ),
    );
  }

  static ChannelMessageResponse _parseChannelMessageV3(Uint8List data) {
    // V3 format (after packet type 0x11 stripped):
    // data[0] = SNR (signed byte, /4.0)
    // data[1..2] = Reserved
    // data[3] = Channel Index
    // data[4] = Path Length
    // data[5] = Text Type
    // data[6..9] = Timestamp (uint32 LE)
    // data[10+] = Message Text
    if (data.length < 10) {
      return const ChannelMessageResponse(
        ChatMessage(text: '', timestamp: 0, isOutgoing: false, channelIndex: 0),
      );
    }

    final snrByte = data[0];
    final snr = (snrByte < 128 ? snrByte : snrByte - 256) / 4.0;
    final channelIdx = data[3];
    final pathLen = data[4];
    final timestamp = _readUint32LE(data, 6);
    final text = data.length > 10 ? _decodeRadioString(data.sublist(10)) : '';

    return ChannelMessageResponse(
      ChatMessage(
        text: text,
        timestamp: timestamp,
        isOutgoing: false,
        channelIndex: channelIdx,
        snr: snr,
        pathLen: pathLen,
      ),
    );
  }

  static ChannelMessageResponse _parseChannelMessage(Uint8List data) {
    // Standard format (after packet type 0x08 stripped):
    // data[0] = Channel Index
    // data[1] = Path Length
    // data[2] = Text Type
    // data[3..6] = Timestamp (uint32 LE)
    // data[7+] = Message Text
    if (data.length < 7) {
      return const ChannelMessageResponse(
        ChatMessage(text: '', timestamp: 0, isOutgoing: false, channelIndex: 0),
      );
    }

    final channelIdx = data[0];
    final pathLen = data[1];
    final timestamp = _readUint32LE(data, 3);
    final text = data.length > 7 ? _decodeRadioString(data.sublist(7)) : '';

    return ChannelMessageResponse(
      ChatMessage(
        text: text,
        timestamp: timestamp,
        isOutgoing: false,
        channelIndex: channelIdx,
        pathLen: pathLen,
      ),
    );
  }

  static CurrTimeResponse _parseCurrTime(Uint8List data) {
    final ts = data.length >= 4 ? _readUint32LE(data, 0) : 0;
    return CurrTimeResponse(ts);
  }

  static BattAndStorageResponse _parseBattAndStorage(Uint8List data) {
    final batt = data.length >= 2 ? _readUint16LE(data, 0) : 0;
    final used = data.length >= 6 ? _readUint32LE(data, 2) : null;
    final total = data.length >= 10 ? _readUint32LE(data, 6) : null;
    return BattAndStorageResponse(batt, used, total);
  }

  static DeviceInfoResponse? _parseDeviceInfo(Uint8List data) {
    // Spec layout (after packet type 0x0D stripped):
    // data[0] = Firmware Version
    // For fw >= 3 and data.length >= 80:
    //   data[1] = Max Contacts Raw (actual = value * 2)
    //   data[2] = Max Channels
    //   data[3..6] = BLE PIN (uint32 LE)
    //   data[7..18] = Firmware Build (12 bytes, null-padded)
    //   data[19..58] = Model (40 bytes, null-padded)
    //   data[59..78] = Version (20 bytes, null-padded)
    if (data.isEmpty) return null;
    final version = data[0];

    if (version >= 3 && data.length >= 79) {
      final maxContacts = data[1] * 2;
      final maxChannels = data[2];
      final blePin = _readUint32LE(data, 3);
      final fwBuildEnd = _findNullTerminator(data, 7, 19);
      final fwBuild = _decodeRadioString(data.sublist(7, fwBuildEnd)).trim();
      final modelEnd = _findNullTerminator(data, 19, 59);
      final model = _decodeRadioString(data.sublist(19, modelEnd)).trim();
      final versionEnd = _findNullTerminator(data, 59, 79);
      final versionStr =
          _decodeRadioString(data.sublist(59, versionEnd)).trim();

      return DeviceInfoResponse(
        DeviceInfo(
          firmwareVersion: version,
          deviceName: model.isNotEmpty ? model : fwBuild,
          batteryMillivolts: 0,
          maxContacts: maxContacts,
          maxChannels: maxChannels,
          blePin: blePin,
          firmwareBuild: fwBuild,
          model: model,
          versionString: versionStr,
        ),
      );
    }

    // Fallback for older firmware versions
    final nameEnd = _findNullTerminator(data, 1, data.length);
    final name = _decodeRadioString(data.sublist(1, nameEnd));
    return DeviceInfoResponse(
      DeviceInfo(
        firmwareVersion: version,
        deviceName: name.trim(),
        batteryMillivolts: 0,
      ),
    );
  }

  static ChannelInfoResponse? _parseChannelInfo(Uint8List data) {
    // Spec layout (after packet type 0x12 stripped):
    // data[0] = Channel Index
    // data[1..32] = Channel Name (32 bytes, null-padded)
    // data[33..48] = Secret (16 bytes)
    if (data.length < 2) return null;
    final idx = data[0];

    final nameMaxEnd = data.length >= 33 ? 33 : data.length;
    final nameEnd = _findNullTerminator(data, 1, nameMaxEnd);
    final name = _decodeRadioString(data.sublist(1, nameEnd)).trim();

    Uint8List? secret;
    if (data.length >= 49) {
      secret = Uint8List.fromList(data.sublist(33, 49));
    }

    return ChannelInfoResponse(
      ChannelInfo(index: idx, name: name, secret: secret),
    );
  }

  static AdvertPush? _parseAdvertPush(Uint8List data, {required bool isNew}) {
    if (data.length < 32) return null;
    final pubKey = Uint8List.fromList(data.sublist(0, 32));

    // The firmware emits two different push frames:
    //
    //   PUSH_CODE_ADVERT     (0x80) — payload = pubkey (32 bytes only).
    //                                  Sent for path/profile updates of an
    //                                  already-known contact.
    //
    //   PUSH_CODE_NEW_ADVERT (0x8A) — payload = full RESP_CODE_CONTACT frame
    //                                  body (pubkey, type, flags, path_len,
    //                                  out_path[64], name[32 null-padded],
    //                                  last_advert_timestamp, gps_lat,
    //                                  gps_lon, lastmod). Sent for newly
    //                                  discovered contacts (firmware uses
    //                                  writeContactRespFrame).
    //
    // Use the full-contact layout for the 0x8A case so we get the real name.
    if (isNew && data.length >= 131) {
      final type = data[32];
      // flags @33, path_len @34, path @35..98 are not surfaced here.
      final nameEnd = _findNullTerminator(data, 99, 131);
      final name = _decodeRadioString(data.sublist(99, nameEnd));
      return AdvertPush(pubKey, type, name.trim(), isNew: isNew);
    }

    // PUSH_CODE_ADVERT (0x80) — pubkey only, no type/name carried.
    return AdvertPush(pubKey, 0, '', isNew: isNew);
  }

  static BinaryResponsePush? _parseBinaryResponse(Uint8List data) {
    // data layout: reserved(1), tag(uint32 LE), response_data(variable)
    if (data.length < 5) return null; // 1 reserved + 4 tag
    final tag = _readUint32LE(data, 1);
    final responseData = data.length > 5 ? data.sublist(5) : Uint8List(0);
    return BinaryResponsePush(tag, responseData);
  }

  static PathDiscoveryPush? _parsePathDiscovery(Uint8List data) {
    // data layout: reserved(1), pub_key_prefix(6), out_path_len(1),
    //              out_path(out_path_len*4), in_path_len(1), in_path(in_path_len*4)
    if (data.length < 8) return null; // 1+6+1 minimum
    final pubKeyPrefix = Uint8List.fromList(data.sublist(1, 7));
    final outPathLen = data[7];
    var offset = 8;
    final outPath = <int>[];
    for (var i = 0; i < outPathLen && offset + 4 <= data.length; i++) {
      outPath.add(_readUint32LE(data, offset));
      offset += 4;
    }
    if (offset >= data.length) {
      return PathDiscoveryPush(pubKeyPrefix, outPath, const []);
    }
    final inPathLen = data[offset];
    offset++;
    final inPath = <int>[];
    for (var i = 0; i < inPathLen && offset + 4 <= data.length; i++) {
      inPath.add(_readUint32LE(data, offset));
      offset += 4;
    }
    return PathDiscoveryPush(pubKeyPrefix, outPath, inPath);
  }

  static ControlDataPush? _parseControlData(Uint8List data) {
    // data layout: SNR*4(signed byte), RSSI(signed byte), path_len(byte), payload(variable)
    if (data.length < 3) return null;
    final snrByte = data[0];
    final snr = (snrByte < 128 ? snrByte : snrByte - 256) / 4.0;
    final rssiByte = data[1];
    final rssi = rssiByte < 128 ? rssiByte : rssiByte - 256;
    final pathLen = data[2];
    final payload = data.length > 3 ? data.sublist(3) : Uint8List(0);
    return ControlDataPush(snr, rssi, pathLen, payload);
  }

  static SignatureResponse? _parseSignature(Uint8List data) {
    if (data.length < 64) return null;
    return SignatureResponse(Uint8List.fromList(data.sublist(0, 64)));
  }

  static PrivateKeyResponse? _parsePrivateKey(Uint8List data) {
    if (data.length < 64) return null;
    return PrivateKeyResponse(Uint8List.fromList(data.sublist(0, 64)));
  }

  static CompanionResponse? _parseStats(Uint8List data) {
    if (data.isEmpty) return null;
    final subType = data[0];
    final d = data.length > 1 ? data.sublist(1) : Uint8List(0);
    switch (subType) {
      case statsTypeCore:
        if (d.length < 9) return null;
        return StatsCoreResponse(
          batteryMv: _readUint16LE(d, 0),
          uptimeSecs: _readUint32LE(d, 2),
          errors: _readUint16LE(d, 6),
          queueLen: d[8],
        );
      case statsTypeRadio:
        if (d.length < 12) return null;
        final bd = ByteData.sublistView(d);
        return StatsRadioResponse(
          noiseFloor: bd.getInt16(0, Endian.little),
          lastRssi: bd.getInt8(2),
          lastSnrDb: bd.getInt8(3) / 4.0,
          txAirSecs: _readUint32LE(d, 4),
          rxAirSecs: _readUint32LE(d, 8),
        );
      case statsTypePackets:
        if (d.length < 24) return null;
        return StatsPacketsResponse(
          recv: _readUint32LE(d, 0),
          sent: _readUint32LE(d, 4),
          floodTx: _readUint32LE(d, 8),
          directTx: _readUint32LE(d, 12),
          floodRx: _readUint32LE(d, 16),
          directRx: _readUint32LE(d, 20),
          recvErrors: d.length >= 28 ? _readUint32LE(d, 24) : null,
        );
      default:
        return null;
    }
  }

  // --- Utility ---

  static int _readUint32LE(Uint8List data, int offset) {
    return data[offset] |
        (data[offset + 1] << 8) |
        (data[offset + 2] << 16) |
        (data[offset + 3] << 24);
  }

  static int _readInt32LE(Uint8List data, int offset) {
    final bd = ByteData.sublistView(data, offset, offset + 4);
    return bd.getInt32(0, Endian.little);
  }

  static int _readUint16LE(Uint8List data, int offset) {
    return data[offset] | (data[offset + 1] << 8);
  }

  static int _findNullTerminator(Uint8List data, int start, int maxEnd) {
    final end = maxEnd.clamp(start, data.length);
    for (var i = start; i < end; i++) {
      if (data[i] == 0) return i;
    }
    return end;
  }
}
