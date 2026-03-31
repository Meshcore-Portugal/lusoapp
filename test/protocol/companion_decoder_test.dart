import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcapppt/protocol/commands.dart';
import 'package:mcapppt/protocol/companion_decoder.dart';

/// Build a uint32 LE byte list.
Uint8List uint32LE(int value) {
  final data = ByteData(4)..setUint32(0, value, Endian.little);
  return data.buffer.asUint8List();
}

/// Build an int32 LE byte list.
Uint8List int32LE(int value) {
  final data = ByteData(4)..setInt32(0, value, Endian.little);
  return data.buffer.asUint8List();
}

/// Build a uint16 LE byte list.
Uint8List uint16LE(int value) {
  final data = ByteData(2)..setUint16(0, value, Endian.little);
  return data.buffer.asUint8List();
}

void main() {
  group('CompanionDecoder - simple responses', () {
    test('decode empty payload returns null', () {
      expect(CompanionDecoder.decode(Uint8List(0)), isNull);
    });

    test('decode EndContacts response', () {
      final resp = CompanionDecoder.decode(Uint8List.fromList([respEndContacts]));
      expect(resp, isA<EndContactsResponse>());
    });

    test('decode Sent response', () {
      final resp = CompanionDecoder.decode(Uint8List.fromList([respSent]));
      expect(resp, isA<SentResponse>());
    });

    test('decode Error with no error code defaults to 0', () {
      final resp = CompanionDecoder.decode(Uint8List.fromList([respErr]));
      expect(resp, isA<ErrorResponse>());
      expect((resp as ErrorResponse).errorCode, 0);
    });
  });

  group('CompanionDecoder - push codes without data', () {
    test('decode SendConfirmedPush', () {
      final resp = CompanionDecoder.decode(Uint8List.fromList([pushSendConfirmed]));
      expect(resp, isA<SendConfirmedPush>());
    });

    test('decode MsgWaitingPush', () {
      final resp = CompanionDecoder.decode(Uint8List.fromList([pushMsgWaiting]));
      expect(resp, isA<MsgWaitingPush>());
    });

    test('decode LoginSuccessPush', () {
      final resp = CompanionDecoder.decode(Uint8List.fromList([pushLoginSuccess]));
      expect(resp, isA<LoginSuccessPush>());
    });

    test('decode LoginFailPush', () {
      final resp = CompanionDecoder.decode(Uint8List.fromList([pushLoginFail]));
      expect(resp, isA<LoginFailPush>());
    });

    test('decode ContactDeletedPush', () {
      final resp = CompanionDecoder.decode(Uint8List.fromList([pushContactDeleted]));
      expect(resp, isA<ContactDeletedPush>());
    });

    test('decode ContactsFullPush', () {
      final resp = CompanionDecoder.decode(Uint8List.fromList([pushContactsFull]));
      expect(resp, isA<ContactsFullPush>());
    });
  });

  group('CompanionDecoder - push codes with data', () {
    test('decode PathUpdatedPush preserves data', () {
      final payload = Uint8List.fromList([pushPathUpdated, 0x01, 0x02, 0x03]);
      final resp = CompanionDecoder.decode(payload);
      expect(resp, isA<PathUpdatedPush>());
      expect((resp as PathUpdatedPush).data, Uint8List.fromList([0x01, 0x02, 0x03]));
    });

    test('decode TraceDataPush preserves data', () {
      final payload = Uint8List.fromList([pushTraceData, 0xAA, 0xBB]);
      final resp = CompanionDecoder.decode(payload);
      expect(resp, isA<TraceDataPush>());
      expect((resp as TraceDataPush).data, Uint8List.fromList([0xAA, 0xBB]));
    });

    test('decode TelemetryPush preserves data', () {
      final payload = Uint8List.fromList([pushTelemetryResponse, 0x10, 0x20]);
      final resp = CompanionDecoder.decode(payload);
      expect(resp, isA<TelemetryPush>());
      expect((resp as TelemetryPush).data, Uint8List.fromList([0x10, 0x20]));
    });

    test('decode LogRxDataPush preserves data', () {
      final payload = Uint8List.fromList([pushLogRxData, 0x01]);
      final resp = CompanionDecoder.decode(payload);
      expect(resp, isA<LogRxDataPush>());
    });

    test('decode StatusResponsePush preserves data', () {
      final payload = Uint8List.fromList([pushStatusResponse, 0x05, 0x06]);
      final resp = CompanionDecoder.decode(payload);
      expect(resp, isA<StatusResponsePush>());
    });

    test('decode RawDataPush preserves data', () {
      final payload = Uint8List.fromList([pushRawData, 0xFF]);
      final resp = CompanionDecoder.decode(payload);
      expect(resp, isA<RawDataPush>());
      expect((resp as RawDataPush).data, Uint8List.fromList([0xFF]));
    });
  });

  group('CompanionDecoder - CurrTime', () {
    test('decode CurrTime parses uint32 LE timestamp', () {
      final payload = Uint8List.fromList([respCurrTime, ...uint32LE(1700000000)]);
      final resp = CompanionDecoder.decode(payload);
      expect(resp, isA<CurrTimeResponse>());
      expect((resp as CurrTimeResponse).timestamp, 1700000000);
    });

    test('decode CurrTime with short data returns 0', () {
      final resp = CompanionDecoder.decode(Uint8List.fromList([respCurrTime, 0x01]));
      expect(resp, isA<CurrTimeResponse>());
      expect((resp as CurrTimeResponse).timestamp, 0);
    });
  });

  group('CompanionDecoder - BattAndStorage', () {
    test('decode BattAndStorage with full data', () {
      final payload = Uint8List.fromList([
        respBattAndStorage,
        ...uint16LE(3700),
        ...uint32LE(500000),
        ...uint32LE(4000000),
      ]);
      final resp = CompanionDecoder.decode(payload);
      expect(resp, isA<BattAndStorageResponse>());
      final batt = resp as BattAndStorageResponse;
      expect(batt.batteryMv, 3700);
      expect(batt.storageUsed, 500000);
      expect(batt.storageTotal, 4000000);
    });

    test('decode BattAndStorage with only battery (no storage)', () {
      final payload = Uint8List.fromList([
        respBattAndStorage,
        ...uint16LE(4200),
      ]);
      final resp = CompanionDecoder.decode(payload) as BattAndStorageResponse;
      expect(resp.batteryMv, 4200);
      expect(resp.storageUsed, isNull);
      expect(resp.storageTotal, isNull);
    });

    test('decode BattAndStorage with battery and used (no total)', () {
      final payload = Uint8List.fromList([
        respBattAndStorage,
        ...uint16LE(3800),
        ...uint32LE(100000),
      ]);
      final resp = CompanionDecoder.decode(payload) as BattAndStorageResponse;
      expect(resp.batteryMv, 3800);
      expect(resp.storageUsed, 100000);
      expect(resp.storageTotal, isNull);
    });
  });

  group('CompanionDecoder - Contact', () {
    /// Build a contact payload (after the response code byte).
    Uint8List buildContactPayload({
      List<int>? pubKey,
      int type = 1,
      int flags = 0,
      int pathLen = 0,
      String name = 'TestNode',
      int lastAdvert = 1700000000,
      double? lat,
      double? lon,
      int? lastMod,
    }) {
      final builder = BytesBuilder();
      final pk = pubKey ?? List.generate(32, (i) => i);
      builder.add(Uint8List.fromList(pk));
      builder.addByte(type);
      builder.addByte(flags);
      builder.addByte(pathLen);
      builder.add(Uint8List(64)); // path
      final nameBytes = utf8.encode(name);
      final nameBuf = Uint8List(32);
      nameBuf.setRange(0, nameBytes.length.clamp(0, 32), nameBytes);
      builder.add(nameBuf);
      builder.add(uint32LE(lastAdvert));
      if (lat != null && lon != null) {
        builder.add(int32LE((lat * 1e6).round()));
        builder.add(int32LE((lon * 1e6).round()));
      }
      if (lastMod != null) {
        builder.add(uint32LE(lastMod));
      }
      return builder.toBytes();
    }

    test('decode full contact with lat/lon and lastModified', () {
      final data = buildContactPayload(
        name: 'CT1ABC',
        type: 1,
        lat: 38.736946,
        lon: -9.142685,
        lastMod: 1700001000,
      );
      final payload = Uint8List.fromList([respContact, ...data]);
      final resp = CompanionDecoder.decode(payload);
      expect(resp, isA<ContactResponse>());
      final contact = (resp as ContactResponse).contact;
      expect(contact.name, 'CT1ABC');
      expect(contact.type, 1);
      expect(contact.isChat, true);
      expect(contact.latitude, closeTo(38.736946, 0.001));
      expect(contact.longitude, closeTo(-9.142685, 0.001));
      expect(contact.lastModified, 1700001000);
    });

    test('decode minimal contact without lat/lon', () {
      final data = buildContactPayload(name: 'MinNode', type: 2);
      final payload = Uint8List.fromList([respContact, ...data]);
      final resp = CompanionDecoder.decode(payload);
      expect(resp, isA<ContactResponse>());
      final contact = (resp as ContactResponse).contact;
      expect(contact.name, 'MinNode');
      expect(contact.isRepeater, true);
      expect(contact.latitude, isNull);
      expect(contact.longitude, isNull);
      expect(contact.lastModified, isNull);
    });

    test('decode contact with data too short returns null', () {
      final payload = Uint8List.fromList([respContact, ...Uint8List(50)]);
      final resp = CompanionDecoder.decode(payload);
      expect(resp, isNull);
    });
  });

  group('CompanionDecoder - SelfInfo', () {
    Uint8List buildSelfInfoPayload({
      int advType = 1,
      int txPower = 14,
      int maxTxPower = 22,
      int radioFreq = 869618,
      int radioBw = 62500,
      int radioSf = 10,
      int radioCr = 5,
      double lat = 38.736946,
      double lon = -9.142685,
      String name = 'MyRadio',
    }) {
      final builder = BytesBuilder();
      builder.addByte(advType);
      builder.addByte(txPower);
      builder.addByte(maxTxPower);
      builder.add(Uint8List.fromList(List.generate(32, (i) => i)));
      builder.add(int32LE((lat * 1e6).round()));
      builder.add(int32LE((lon * 1e6).round()));
      builder.addByte(0); // multi_acks
      builder.addByte(0); // adv_loc_policy
      builder.addByte(0); // telemetry_mode
      builder.addByte(0); // manual_add_contacts
      builder.add(uint32LE(radioFreq));
      builder.add(uint32LE(radioBw));
      builder.addByte(radioSf);
      builder.addByte(radioCr);
      builder.add(Uint8List.fromList(utf8.encode(name)));
      return builder.toBytes();
    }

    test('decode full SelfInfo with radio config and name', () {
      final data = buildSelfInfoPayload();
      final payload = Uint8List.fromList([respSelfInfo, ...data]);
      final resp = CompanionDecoder.decode(payload);
      expect(resp, isA<SelfInfoResponse>());
      final info = (resp as SelfInfoResponse).info;
      expect(info.name, 'MyRadio');
      expect(info.advType, 1);
      expect(info.txPower, 14);
      expect(info.maxTxPower, 22);
      expect(info.radioConfig.frequencyHz, 869618);
      expect(info.radioConfig.bandwidthHz, 62500);
      expect(info.radioConfig.spreadingFactor, 10);
      expect(info.radioConfig.codingRate, 5);
      expect(info.latitude, closeTo(38.736946, 0.001));
      expect(info.longitude, closeTo(-9.142685, 0.001));
    });

    test('decode SelfInfo with no name (exactly 57 bytes)', () {
      final data = buildSelfInfoPayload(name: '');
      final trimmed = data.sublist(0, 57);
      final payload = Uint8List.fromList([respSelfInfo, ...trimmed]);
      final resp = CompanionDecoder.decode(payload);
      expect(resp, isA<SelfInfoResponse>());
      expect((resp as SelfInfoResponse).info.name, isEmpty);
    });

    test('decode SelfInfo with short data returns null', () {
      final payload = Uint8List.fromList([respSelfInfo, ...Uint8List(30)]);
      final resp = CompanionDecoder.decode(payload);
      expect(resp, isNull);
    });
  });

  group('CompanionDecoder - PrivateMessage V1', () {
    test('decode private message with text', () {
      final builder = BytesBuilder();
      builder.add(Uint8List.fromList([0xA1, 0xB2, 0xC3, 0xD4, 0xE5, 0xF6]));
      builder.addByte(3);
      builder.addByte(txtPlain);
      builder.add(uint32LE(1700000000));
      builder.add(Uint8List.fromList(utf8.encode('Hello')));
      final payload = Uint8List.fromList([respContactMsgRecv, ...builder.toBytes()]);
      final resp = CompanionDecoder.decode(payload);
      expect(resp, isA<PrivateMessageResponse>());
      final msg = (resp as PrivateMessageResponse).message;
      expect(msg.text, 'Hello');
      expect(msg.timestamp, 1700000000);
      expect(msg.isOutgoing, false);
      expect(msg.pathLen, 3);
      expect(msg.senderKey, Uint8List.fromList([0xA1, 0xB2, 0xC3, 0xD4, 0xE5, 0xF6]));
    });

    test('decode private message V1 with signature (txtType==2) skips 4 bytes', () {
      final builder = BytesBuilder();
      builder.add(Uint8List(6));
      builder.addByte(0);
      builder.addByte(2);
      builder.add(uint32LE(1700000000));
      builder.add(Uint8List(4));
      builder.add(Uint8List.fromList(utf8.encode('Signed msg')));
      final payload = Uint8List.fromList([respContactMsgRecv, ...builder.toBytes()]);
      final resp = CompanionDecoder.decode(payload) as PrivateMessageResponse;
      expect(resp.message.text, 'Signed msg');
    });

    test('decode private message V1 with short data returns empty fallback', () {
      final payload = Uint8List.fromList([respContactMsgRecv, ...Uint8List(5)]);
      final resp = CompanionDecoder.decode(payload) as PrivateMessageResponse;
      expect(resp.message.text, isEmpty);
      expect(resp.message.timestamp, 0);
    });
  });

  group('CompanionDecoder - PrivateMessage V3', () {
    test('decode V3 private message with SNR and text', () {
      final builder = BytesBuilder();
      builder.addByte(40);
      builder.add(Uint8List(2));
      builder.add(Uint8List.fromList([0x01, 0x02, 0x03, 0x04, 0x05, 0x06]));
      builder.addByte(2);
      builder.addByte(txtPlain);
      builder.add(uint32LE(1700000000));
      builder.add(Uint8List.fromList(utf8.encode('V3 msg')));
      final payload = Uint8List.fromList([respContactMsgRecvV3, ...builder.toBytes()]);
      final resp = CompanionDecoder.decode(payload) as PrivateMessageResponse;
      expect(resp.message.text, 'V3 msg');
      expect(resp.message.snr, 10.0);
      expect(resp.message.pathLen, 2);
      expect(resp.message.timestamp, 1700000000);
    });

    test('decode V3 private message with negative SNR', () {
      final builder = BytesBuilder();
      builder.addByte(0xF0);
      builder.add(Uint8List(2));
      builder.add(Uint8List(6));
      builder.addByte(0);
      builder.addByte(txtPlain);
      builder.add(uint32LE(1700000000));
      builder.add(Uint8List.fromList(utf8.encode('Weak signal')));
      final payload = Uint8List.fromList([respContactMsgRecvV3, ...builder.toBytes()]);
      final resp = CompanionDecoder.decode(payload) as PrivateMessageResponse;
      expect(resp.message.snr, -4.0);
    });

    test('decode V3 private message with signature (txtType==2)', () {
      final builder = BytesBuilder();
      builder.addByte(0);
      builder.add(Uint8List(2));
      builder.add(Uint8List(6));
      builder.addByte(0);
      builder.addByte(2);
      builder.add(uint32LE(1700000000));
      builder.add(Uint8List(4));
      builder.add(Uint8List.fromList(utf8.encode('Signed V3')));
      final payload = Uint8List.fromList([respContactMsgRecvV3, ...builder.toBytes()]);
      final resp = CompanionDecoder.decode(payload) as PrivateMessageResponse;
      expect(resp.message.text, 'Signed V3');
    });

    test('decode V3 private message with short data returns empty fallback', () {
      final payload = Uint8List.fromList([respContactMsgRecvV3, ...Uint8List(5)]);
      final resp = CompanionDecoder.decode(payload) as PrivateMessageResponse;
      expect(resp.message.text, isEmpty);
      expect(resp.message.timestamp, 0);
    });
  });

  group('CompanionDecoder - ChannelMessage V1', () {
    test('decode channel message with text', () {
      final builder = BytesBuilder();
      builder.addByte(2);
      builder.addByte(1);
      builder.addByte(txtPlain);
      builder.add(uint32LE(1700000000));
      builder.add(Uint8List.fromList(utf8.encode('Chan msg')));
      final payload = Uint8List.fromList([respChannelMsgRecv, ...builder.toBytes()]);
      final resp = CompanionDecoder.decode(payload) as ChannelMessageResponse;
      expect(resp.message.text, 'Chan msg');
      expect(resp.message.channelIndex, 2);
      expect(resp.message.pathLen, 1);
      expect(resp.message.timestamp, 1700000000);
    });

    test('decode channel message V1 with short data returns empty fallback', () {
      final payload = Uint8List.fromList([respChannelMsgRecv, ...Uint8List(3)]);
      final resp = CompanionDecoder.decode(payload) as ChannelMessageResponse;
      expect(resp.message.text, isEmpty);
      expect(resp.message.channelIndex, 0);
    });
  });

  group('CompanionDecoder - ChannelMessage V3', () {
    test('decode V3 channel message with SNR', () {
      final builder = BytesBuilder();
      builder.addByte(20);
      builder.add(Uint8List(2));
      builder.addByte(3);
      builder.addByte(2);
      builder.addByte(txtPlain);
      builder.add(uint32LE(1700000000));
      builder.add(Uint8List.fromList(utf8.encode('V3 chan')));
      final payload = Uint8List.fromList([respChannelMsgRecvV3, ...builder.toBytes()]);
      final resp = CompanionDecoder.decode(payload) as ChannelMessageResponse;
      expect(resp.message.text, 'V3 chan');
      expect(resp.message.channelIndex, 3);
      expect(resp.message.snr, 5.0);
      expect(resp.message.pathLen, 2);
    });

    test('decode V3 channel message with short data returns empty fallback', () {
      final payload = Uint8List.fromList([respChannelMsgRecvV3, ...Uint8List(5)]);
      final resp = CompanionDecoder.decode(payload) as ChannelMessageResponse;
      expect(resp.message.text, isEmpty);
      expect(resp.message.channelIndex, 0);
    });
  });

  group('CompanionDecoder - DeviceInfo', () {
    test('decode DeviceInfo firmware v3+ with full fields', () {
      final builder = BytesBuilder();
      builder.addByte(3);
      builder.addByte(50);
      builder.addByte(8);
      builder.add(uint32LE(123456));
      final fwBuild = Uint8List(12);
      final fwBytes = utf8.encode('abc123');
      fwBuild.setRange(0, fwBytes.length, fwBytes);
      builder.add(fwBuild);
      final model = Uint8List(40);
      final modelBytes = utf8.encode('T-Beam Supreme');
      model.setRange(0, modelBytes.length, modelBytes);
      builder.add(model);
      final version = Uint8List(20);
      final verBytes = utf8.encode('3.0.1');
      version.setRange(0, verBytes.length, verBytes);
      builder.add(version);
      final payload = Uint8List.fromList([respDeviceInfo, ...builder.toBytes()]);
      final resp = CompanionDecoder.decode(payload) as DeviceInfoResponse;
      expect(resp.info.firmwareVersion, 3);
      expect(resp.info.maxContacts, 100);
      expect(resp.info.maxChannels, 8);
      expect(resp.info.blePin, 123456);
      expect(resp.info.firmwareBuild, 'abc123');
      expect(resp.info.model, 'T-Beam Supreme');
      expect(resp.info.versionString, '3.0.1');
      expect(resp.info.deviceName, 'T-Beam Supreme');
    });

    test('decode DeviceInfo old firmware fallback', () {
      final builder = BytesBuilder();
      builder.addByte(1);
      builder.add(Uint8List.fromList(utf8.encode('OldRadio')));
      builder.addByte(0);
      final payload = Uint8List.fromList([respDeviceInfo, ...builder.toBytes()]);
      final resp = CompanionDecoder.decode(payload) as DeviceInfoResponse;
      expect(resp.info.firmwareVersion, 1);
      expect(resp.info.deviceName, 'OldRadio');
    });

    test('decode DeviceInfo with empty data returns null', () {
      final payload = Uint8List.fromList([respDeviceInfo]);
      final resp = CompanionDecoder.decode(payload);
      expect(resp, isNull);
    });
  });

  group('CompanionDecoder - ChannelInfo', () {
    test('decode ChannelInfo with name and secret', () {
      final builder = BytesBuilder();
      builder.addByte(2);
      final nameBuf = Uint8List(32);
      final nameBytes = utf8.encode('Emergency');
      nameBuf.setRange(0, nameBytes.length, nameBytes);
      builder.add(nameBuf);
      builder.add(Uint8List.fromList(List.generate(16, (i) => i + 0xA0)));
      final payload = Uint8List.fromList([respChannelInfo, ...builder.toBytes()]);
      final resp = CompanionDecoder.decode(payload) as ChannelInfoResponse;
      expect(resp.channel.index, 2);
      expect(resp.channel.name, 'Emergency');
      expect(resp.channel.secret, isNotNull);
      expect(resp.channel.secret!.length, 16);
    });

    test('decode ChannelInfo without secret (short data)', () {
      final builder = BytesBuilder();
      builder.addByte(0);
      final nameBuf = Uint8List(32);
      final nameBytes = utf8.encode('General');
      nameBuf.setRange(0, nameBytes.length, nameBytes);
      builder.add(nameBuf);
      final payload = Uint8List.fromList([respChannelInfo, ...builder.toBytes()]);
      final resp = CompanionDecoder.decode(payload) as ChannelInfoResponse;
      expect(resp.channel.name, 'General');
      expect(resp.channel.secret, isNull);
    });

    test('decode ChannelInfo with too-short data returns null', () {
      final payload = Uint8List.fromList([respChannelInfo]);
      final resp = CompanionDecoder.decode(payload);
      expect(resp, isNull);
    });
  });

  group('CompanionDecoder - AdvertPush', () {
    test('decode AdvertPush with pubkey, type, and name', () {
      final builder = BytesBuilder();
      builder.add(Uint8List.fromList(List.generate(32, (i) => i)));
      builder.addByte(1);
      builder.add(Uint8List.fromList(utf8.encode('NewNode')));
      final payload = Uint8List.fromList([pushAdvert, ...builder.toBytes()]);
      final resp = CompanionDecoder.decode(payload);
      expect(resp, isA<AdvertPush>());
      final advert = resp as AdvertPush;
      expect(advert.name, 'NewNode');
      expect(advert.type, 1);
      expect(advert.publicKey.length, 32);
    });

    test('decode NewAdvert uses same parser as Advert', () {
      final builder = BytesBuilder();
      builder.add(Uint8List(32));
      builder.addByte(2);
      builder.add(Uint8List.fromList(utf8.encode('Repeater1')));
      final payload = Uint8List.fromList([pushNewAdvert, ...builder.toBytes()]);
      final resp = CompanionDecoder.decode(payload);
      expect(resp, isA<AdvertPush>());
      expect((resp as AdvertPush).name, 'Repeater1');
    });

    test('decode AdvertPush with short data returns null', () {
      final payload = Uint8List.fromList([pushAdvert, ...Uint8List(20)]);
      final resp = CompanionDecoder.decode(payload);
      expect(resp, isNull);
    });
  });

  group('CompanionDecoder - extractFrames edge cases', () {
    test('empty buffer returns empty list', () {
      final (frames, remaining) = CompanionDecoder.extractFrames(Uint8List(0));
      expect(frames, isEmpty);
      expect(remaining, isEmpty);
    });

    test('skips bytes with invalid direction marker', () {
      final buffer = Uint8List.fromList([
        0x00, 0x00,
        dirRadioToApp, 1, 0, respOk,
      ]);
      final (frames, remaining) = CompanionDecoder.extractFrames(buffer);
      expect(frames.length, 1);
      expect(frames[0], Uint8List.fromList([respOk]));
    });

    test('skips frame with payloadLen == 0', () {
      final buffer = Uint8List.fromList([
        dirRadioToApp, 0, 0,
        dirRadioToApp, 1, 0, respOk,
      ]);
      final (frames, remaining) = CompanionDecoder.extractFrames(buffer);
      expect(frames.length, 1);
    });

    test('skips frame with payloadLen > maxPayload', () {
      final buffer = Uint8List.fromList([
        dirRadioToApp, 0xFF, 0xFF,
        dirRadioToApp, 1, 0, respOk,
      ]);
      final (frames, remaining) = CompanionDecoder.extractFrames(buffer);
      expect(frames.length, 1);
    });
  });

  // -----------------------------------------------------------------------
  // Task 4: SignatureResponse (0x14) and StatsResponse (0x18)
  // -----------------------------------------------------------------------

  group('SignatureResponse (0x14)', () {
    test('parses 64-byte signature from payload', () {
      final signature = List<int>.generate(64, (i) => i + 1);
      final payload = Uint8List.fromList([respSignature, ...signature]);

      final result = CompanionDecoder.decode(payload);

      expect(result, isA<SignatureResponse>());
      final resp = result as SignatureResponse;
      expect(resp.signature.length, 64);
      expect(resp.signature[0], 1);
      expect(resp.signature[63], 64);
    });

    test('returns null for short signature data (< 64 bytes)', () {
      final payload = Uint8List.fromList([respSignature, ...List.filled(32, 0)]);

      final result = CompanionDecoder.decode(payload);

      expect(result, isNull);
    });

    test('ignores extra bytes beyond 64-byte signature', () {
      final signature = List<int>.generate(64, (i) => 0xAA);
      final payload = Uint8List.fromList([
        respSignature,
        ...signature,
        0xFF,
        0xFF, // extra bytes
      ]);

      final result = CompanionDecoder.decode(payload);

      expect(result, isA<SignatureResponse>());
      final resp = result as SignatureResponse;
      expect(resp.signature.length, 64);
    });
  });

  group('StatsResponse (0x18)', () {
    test('parses sub_type and variable-length data', () {
      final statsData = [0x01, 0x02, 0x03, 0x04];
      final payload = Uint8List.fromList([
        respStats,
        0x05, // sub_type
        ...statsData,
      ]);

      final result = CompanionDecoder.decode(payload);

      expect(result, isA<StatsResponse>());
      final resp = result as StatsResponse;
      expect(resp.subType, 0x05);
      expect(resp.data.length, 4);
      expect(resp.data[0], 0x01);
    });

    test('handles empty data after sub_type', () {
      final payload = Uint8List.fromList([respStats, 0x02]);

      final result = CompanionDecoder.decode(payload);

      expect(result, isA<StatsResponse>());
      final resp = result as StatsResponse;
      expect(resp.subType, 0x02);
      expect(resp.data.length, 0);
    });

    test('returns null when no sub_type present', () {
      final payload = Uint8List.fromList([respStats]);

      final result = CompanionDecoder.decode(payload);

      expect(result, isNull);
    });
  });

  // -----------------------------------------------------------------------
  // Task 5: BinaryResponsePush (0x8C), PathDiscoveryPush (0x8D),
  //         ControlDataPush (0x8E)
  // -----------------------------------------------------------------------

  group('BinaryResponsePush (0x8C)', () {
    test('parses tag and response data', () {
      // Layout: code(0x8C), reserved(1), tag(uint32 LE), response_data(variable)
      final payload = Uint8List.fromList([
        pushBinaryResponse,
        0x00, // reserved
        0x78, 0x56, 0x34, 0x12, // tag = 0x12345678 LE
        0xAA, 0xBB, 0xCC, // response data
      ]);

      final result = CompanionDecoder.decode(payload);

      expect(result, isA<BinaryResponsePush>());
      final resp = result as BinaryResponsePush;
      expect(resp.tag, 0x12345678);
      expect(resp.responseData.length, 3);
      expect(resp.responseData[0], 0xAA);
      expect(resp.responseData[2], 0xCC);
    });

    test('handles empty response data', () {
      final payload = Uint8List.fromList([
        pushBinaryResponse,
        0x00, // reserved
        0x01, 0x00, 0x00, 0x00, // tag = 1
      ]);

      final result = CompanionDecoder.decode(payload);

      expect(result, isA<BinaryResponsePush>());
      final resp = result as BinaryResponsePush;
      expect(resp.tag, 1);
      expect(resp.responseData.length, 0);
    });

    test('returns null when data too short for tag', () {
      final payload = Uint8List.fromList([
        pushBinaryResponse,
        0x00, // reserved
        0x01, 0x02, // only 2 bytes for tag, need 4
      ]);

      final result = CompanionDecoder.decode(payload);

      expect(result, isNull);
    });
  });

  group('PathDiscoveryPush (0x8D)', () {
    test('parses pub key prefix, out path, and in path', () {
      // Layout: code(0x8D), reserved(1), pub_key_prefix(6),
      //         out_path_len, out_path(out_path_len*4 bytes),
      //         in_path_len, in_path(in_path_len*4 bytes)
      final payload = Uint8List.fromList([
        pushPathDiscoveryResponse,
        0x00, // reserved
        0x01, 0x02, 0x03, 0x04, 0x05, 0x06, // pub_key_prefix (6 bytes)
        0x02, // out_path_len = 2 (2*4 = 8 bytes)
        // out_path: 2 uint32 LE values
        0x0A, 0x00, 0x00, 0x00, // hop 1 = 10
        0x14, 0x00, 0x00, 0x00, // hop 2 = 20
        0x01, // in_path_len = 1 (1*4 = 4 bytes)
        // in_path: 1 uint32 LE value
        0x1E, 0x00, 0x00, 0x00, // hop 1 = 30
      ]);

      final result = CompanionDecoder.decode(payload);

      expect(result, isA<PathDiscoveryPush>());
      final resp = result as PathDiscoveryPush;
      expect(resp.pubKeyPrefix.length, 6);
      expect(resp.pubKeyPrefix[0], 0x01);
      expect(resp.pubKeyPrefix[5], 0x06);
      expect(resp.outPath.length, 2);
      expect(resp.outPath[0], 10);
      expect(resp.outPath[1], 20);
      expect(resp.inPath.length, 1);
      expect(resp.inPath[0], 30);
    });

    test('handles zero-length paths', () {
      final payload = Uint8List.fromList([
        pushPathDiscoveryResponse,
        0x00, // reserved
        0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, // pub_key_prefix
        0x00, // out_path_len = 0
        0x00, // in_path_len = 0
      ]);

      final result = CompanionDecoder.decode(payload);

      expect(result, isA<PathDiscoveryPush>());
      final resp = result as PathDiscoveryPush;
      expect(resp.outPath, isEmpty);
      expect(resp.inPath, isEmpty);
    });

    test('returns null when data too short for header', () {
      // Need at least: reserved(1) + pub_key_prefix(6) + out_path_len(1) = 8
      final payload = Uint8List.fromList([
        pushPathDiscoveryResponse,
        0x00, 0x01, 0x02, // only 3 bytes of data
      ]);

      final result = CompanionDecoder.decode(payload);

      expect(result, isNull);
    });
  });

  group('ControlDataPush (0x8E)', () {
    test('parses SNR, RSSI, path length, and payload', () {
      // Layout: code(0x8E), SNR*4(signed byte), RSSI(signed byte),
      //         path_len(byte), payload(variable)
      final payload = Uint8List.fromList([
        pushControlData,
        40, // SNR*4 = 40 => SNR = 10.0
        0xD6, // RSSI = -42 (0xD6 as signed byte)
        0x03, // path_len = 3 (metadata only)
        0x48, 0x65, 0x6C, 0x6C, 0x6F, // "Hello"
      ]);

      final result = CompanionDecoder.decode(payload);

      expect(result, isA<ControlDataPush>());
      final resp = result as ControlDataPush;
      expect(resp.snr, 10.0);
      expect(resp.rssi, -42);
      expect(resp.pathLen, 3);
      expect(resp.payload.length, 5);
      expect(resp.payload[0], 0x48); // 'H'
    });

    test('parses negative SNR correctly', () {
      // SNR*4 byte = 0xF0 = 240 unsigned => signed = 240 - 256 = -16
      // SNR = -16 / 4.0 = -4.0
      final payload = Uint8List.fromList([
        pushControlData,
        0xF0, // SNR*4 = -16 signed
        0x80, // RSSI = -128 signed
        0x00, // path_len
      ]);

      final result = CompanionDecoder.decode(payload);

      expect(result, isA<ControlDataPush>());
      final resp = result as ControlDataPush;
      expect(resp.snr, -4.0);
      expect(resp.rssi, -128);
      expect(resp.pathLen, 0);
      expect(resp.payload, isEmpty);
    });

    test('returns null when data too short for header', () {
      // Need at least: SNR(1) + RSSI(1) + path_len(1) = 3 bytes
      final payload = Uint8List.fromList([
        pushControlData,
        40, // SNR only
      ]);

      final result = CompanionDecoder.decode(payload);

      expect(result, isNull);
    });
  });
}
