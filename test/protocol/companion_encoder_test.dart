import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lusoapp/protocol/commands.dart';
import 'package:lusoapp/protocol/companion_encoder.dart';
import 'package:lusoapp/protocol/models.dart';

/// Read uint32 little-endian from frame at offset.
int readUint32LE(Uint8List data, int offset) {
  return data[offset] |
      (data[offset + 1] << 8) |
      (data[offset + 2] << 16) |
      (data[offset + 3] << 24);
}

/// Read int32 little-endian from frame at offset.
int readInt32LE(Uint8List data, int offset) {
  final bd = ByteData.sublistView(data, offset, offset + 4);
  return bd.getInt32(0, Endian.little);
}

void main() {
  group('CompanionEncoder - command-only frames', () {
    test('getDeviceTime sends correct command with no payload', () {
      final frame = CompanionEncoder.getDeviceTime();
      expect(frame[0], dirAppToRadio);
      final len = frame[1] | (frame[2] << 8);
      expect(len, 1);
      expect(frame[3], cmdGetDeviceTime);
      expect(frame.length, 4);
    });

    test('syncNext sends correct command with no payload', () {
      final frame = CompanionEncoder.syncNext();
      expect(frame[0], dirAppToRadio);
      final len = frame[1] | (frame[2] << 8);
      expect(len, 1);
      expect(frame[3], cmdSyncNext);
      expect(frame.length, 4);
    });

    test('getBattAndStorage sends correct command with no payload', () {
      final frame = CompanionEncoder.getBattAndStorage();
      expect(frame[0], dirAppToRadio);
      final len = frame[1] | (frame[2] << 8);
      expect(len, 1);
      expect(frame[3], cmdGetBattAndStorage);
      expect(frame.length, 4);
    });
  });

  group('CompanionEncoder - timestamp and data methods', () {
    test('setDeviceTime encodes timestamp as uint32 LE', () {
      final frame = CompanionEncoder.setDeviceTime(0x12345678);
      expect(frame[0], dirAppToRadio);
      expect(frame[3], cmdSetDeviceTime);
      expect(readUint32LE(frame, 4), 0x12345678);
    });

    test('getContacts with sinceTimestamp encodes uint32 LE', () {
      final frame = CompanionEncoder.getContacts(sinceTimestamp: 1000000);
      expect(frame[0], dirAppToRadio);
      expect(frame[3], cmdGetContacts);
      expect(readUint32LE(frame, 4), 1000000);
    });

    test('deviceQuery encodes appVersion byte', () {
      final frame = CompanionEncoder.deviceQuery();
      expect(frame[0], dirAppToRadio);
      expect(frame[3], cmdDeviceQuery);
      expect(frame[4], 3);
    });

    test('deviceQuery encodes custom appVersion', () {
      final frame = CompanionEncoder.deviceQuery(appVersion: 5);
      expect(frame[4], 5);
    });

    test('getChannel encodes channel index', () {
      final frame = CompanionEncoder.getChannel(2);
      expect(frame[0], dirAppToRadio);
      expect(frame[3], cmdGetChannel);
      expect(frame[4], 2);
    });
  });

  group('CompanionEncoder - string and identity methods', () {
    test('sendAdvert with flood=false sends 0x00', () {
      final frame = CompanionEncoder.sendAdvert();
      expect(frame[0], dirAppToRadio);
      expect(frame[3], cmdSendAdvert);
      expect(frame[4], 0);
    });

    test('sendAdvert with flood=true sends 0x01', () {
      final frame = CompanionEncoder.sendAdvert(flood: true);
      expect(frame[4], 1);
    });

    test('setAdvertName encodes UTF-8 name', () {
      final frame = CompanionEncoder.setAdvertName('CT1ABC');
      expect(frame[0], dirAppToRadio);
      expect(frame[3], cmdSetAdvertName);
      final nameBytes = frame.sublist(4);
      expect(utf8.decode(nameBytes), 'CT1ABC');
    });

    test('sendLogin encodes peer public key and UTF-8 password', () {
      final pubKey = Uint8List.fromList(List.generate(32, (i) => i));
      final frame = CompanionEncoder.sendLogin(pubKey, 'secret123');
      expect(frame[0], dirAppToRadio);
      expect(frame[3], cmdSendLogin);
      expect(frame.sublist(4, 36), pubKey);
      final passBytes = frame.sublist(36);
      expect(utf8.decode(passBytes), 'secret123');
    });
  });

  group('CompanionEncoder - public key methods', () {
    test('removeContact passes public key as payload', () {
      final pubKey = Uint8List.fromList(List.generate(32, (i) => i));
      final frame = CompanionEncoder.removeContact(pubKey);
      expect(frame[0], dirAppToRadio);
      expect(frame[3], cmdRemoveContact);
      expect(frame.sublist(4), pubKey);
    });

    test('resetPath passes public key as payload', () {
      final pubKey = Uint8List.fromList(List.generate(32, (i) => 0xFF - i));
      final frame = CompanionEncoder.resetPath(pubKey);
      expect(frame[0], dirAppToRadio);
      expect(frame[3], cmdResetPath);
      expect(frame.sublist(4), pubKey);
    });

    test('sendTracePath encodes tag, authCode, flags, and optional path', () {
      final path = Uint8List.fromList([0xAA, 0xBB, 0xCC]);
      final frame = CompanionEncoder.sendTracePath(
        tag: 0x12345678,
        authCode: 0x00ABCDEF,
        path: path,
      );
      expect(frame[0], dirAppToRadio);
      expect(frame[3], cmdSendTracePath);
      // tag (4 bytes LE) + authCode (4 bytes LE) + flags (1 byte) + path
      expect(frame.sublist(4, 8), [0x78, 0x56, 0x34, 0x12]); // tag LE
      expect(frame.sublist(8, 12), [0xEF, 0xCD, 0xAB, 0x00]); // authCode LE
      expect(frame[12], 0); // flags
      expect(frame.sublist(13), path);
    });
  });

  group('CompanionEncoder - complex payloads', () {
    test('setAdvertLatLon encodes lat/lon scaled by 1e6 as int32 LE', () {
      final frame = CompanionEncoder.setAdvertLatLon(38.736946, -9.142685);
      expect(frame[0], dirAppToRadio);
      expect(frame[3], cmdSetAdvertLatLon);
      final lat = readInt32LE(frame, 4);
      final lon = readInt32LE(frame, 8);
      expect(lat, closeTo(38736946, 1));
      expect(lon, closeTo(-9142685, 1));
    });

    test('setChannel encodes index, 32-byte padded name, 16-byte secret', () {
      final secret = Uint8List.fromList(List.generate(16, (i) => i + 0xA0));
      final frame = CompanionEncoder.setChannel(3, 'Emergency', secret);
      expect(frame[0], dirAppToRadio);
      expect(frame[3], cmdSetChannel);
      expect(frame[4], 3);
      final nameBytes = frame.sublist(5, 37);
      final nameStr = utf8.decode(
        nameBytes.sublist(
          0,
          nameBytes.contains(0) ? nameBytes.indexOf(0) : nameBytes.length,
        ),
      );
      expect(nameStr, 'Emergency');
      expect(frame.sublist(37, 53), secret);
    });

    test('setChannel throws if secret is not 16 bytes', () {
      expect(
        () => CompanionEncoder.setChannel(0, 'Test', Uint8List(10)),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('sendMessage encodes attempt, timestamp, 6-byte prefix, text', () {
      final prefix = Uint8List.fromList([
        0xA1,
        0xB2,
        0xC3,
        0xD4,
        0xE5,
        0xF6,
        0x07,
        0x08,
      ]);
      final frame = CompanionEncoder.sendMessage(
        prefix,
        'Ola mundo',
        attempt: 2,
        timestamp: 1700000000,
      );
      expect(frame[0], dirAppToRadio);
      expect(frame[3], cmdSendMsg);
      expect(frame[4], txtPlain);
      expect(frame[5], 2);
      expect(readUint32LE(frame, 6), 1700000000);
      expect(frame.sublist(10, 16), prefix.sublist(0, 6));
      final text = utf8.decode(frame.sublist(16));
      expect(text, 'Ola mundo');
    });

    test('sendChannelMessage encodes timestamp and text', () {
      final frame = CompanionEncoder.sendChannelMessage(
        5,
        'Hello channel',
        timestamp: 1700000000,
      );
      expect(frame[4], txtPlain);
      expect(frame[5], 5);
      expect(readUint32LE(frame, 6), 1700000000);
      final text = utf8.decode(frame.sublist(10));
      expect(text, 'Hello channel');
    });

    test(
      'setRadioParams encodes freq and bw as uint32 LE, sf and cr as bytes',
      () {
        const config = RadioConfig(
          frequencyHz: 869618,
          bandwidthHz: 62500,
          spreadingFactor: 10,
          codingRate: 5,
          txPowerDbm: 14,
        );
        final frame = CompanionEncoder.setRadioParams(config);
        expect(readUint32LE(frame, 4), 869618);
        expect(readUint32LE(frame, 8), 62500);
        expect(frame[12], 10);
        expect(frame[13], 5);
      },
    );

    test('appStart includes 7 reserved bytes then UTF-8 name', () {
      final frame = CompanionEncoder.appStart('MCApp');
      expect(frame[3], cmdAppStart);
      for (var i = 4; i < 11; i++) {
        expect(frame[i], 0, reason: 'reserved byte at offset $i');
      }
      final name = utf8.decode(frame.sublist(11));
      expect(name, 'MCApp');
    });
  });

  group('CompanionEncoder - frame limits', () {
    test('_frame throws ArgumentError when payload exceeds maxPayload', () {
      final longName = 'A' * 200;
      expect(
        () => CompanionEncoder.setAdvertName(longName),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  // =========================================================================
  // Task 1: Contact management commands
  // =========================================================================

  group('CompanionEncoder - addUpdateContact', () {
    test('addUpdateContact encodes full contact payload', () {
      final pubKey = Uint8List.fromList(List.generate(32, (i) => i));
      final contact = Contact(
        publicKey: pubKey,
        type: 0x01,
        flags: 0x02,
        pathLen: 3,
        name: 'TestNode',
        lastAdvertTimestamp: 1000000,
      );
      final frame = CompanionEncoder.addUpdateContact(contact);
      expect(frame[0], dirAppToRadio);
      expect(frame[3], cmdAddUpdateContact);
      expect(frame.sublist(4, 36), pubKey); // pub_key
      expect(frame[36], 0x01); // type
      expect(frame[37], 0x02); // flags
      expect(frame[38], 3); // out_path_len
      // outPath at offset 39..102 (64 bytes)
      // name at offset 103..134 (32 bytes)
      // lastAdvert at offset 135..138 (uint32 LE)
      expect(readUint32LE(frame, 135), 1000000);
    });

    test('addUpdateContact with lat/lon encodes int32 LE values', () {
      final pubKey = Uint8List.fromList(List.generate(32, (i) => i));
      final contact = Contact(
        publicKey: pubKey,
        type: 0x01,
        flags: 0x00,
        pathLen: 0,
        name: 'GpsNode',
        lastAdvertTimestamp: 500000,
        latitude: 38.736946,
        longitude: -9.142685,
      );
      final frame = CompanionEncoder.addUpdateContact(contact);
      // lat at offset 139 (after lastAdvert at 135)
      final lat = readInt32LE(frame, 139);
      final lon = readInt32LE(frame, 143);
      expect(lat, closeTo(38736946, 1));
      expect(lon, closeTo(-9142685, 1));
    });
  });

  group('CompanionEncoder - shareContact', () {
    test('shareContact passes public key as payload', () {
      final pubKey = Uint8List.fromList(List.generate(32, (i) => i));
      final frame = CompanionEncoder.shareContact(pubKey);
      expect(frame[0], dirAppToRadio);
      expect(frame[3], cmdShareContact);
      expect(frame.sublist(4), pubKey);
    });
  });

  group('CompanionEncoder - exportContact', () {
    test('exportContact with public key', () {
      final pubKey = Uint8List.fromList(List.generate(32, (i) => i));
      final frame = CompanionEncoder.exportContact(pubKey);
      expect(frame[0], dirAppToRadio);
      expect(frame[3], cmdExportContact);
      expect(frame.sublist(4), pubKey);
    });

    test('exportContact without key exports self', () {
      final frame = CompanionEncoder.exportContact();
      expect(frame[0], dirAppToRadio);
      expect(frame[3], cmdExportContact);
      expect(frame.length, 4); // header only, no payload beyond command
    });
  });

  // =========================================================================
  // Task 2: importContact, setTuningParams, sendStatusReq
  // =========================================================================

  group('CompanionEncoder - importContact', () {
    test('importContact passes card data as payload', () {
      final cardData = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final frame = CompanionEncoder.importContact(cardData);
      expect(frame[0], dirAppToRadio);
      expect(frame[3], cmdImportContact);
      expect(frame.sublist(4), cardData);
    });
  });

  group('CompanionEncoder - setTuningParams', () {
    test(
      'setTuningParams encodes rxdelay, airtime factor, and reserved bytes',
      () {
        final frame = CompanionEncoder.setTuningParams(
          rxDelayBase: 1500, // raw uint32 (already *1000)
          airtimeFactor: 2500, // raw uint32 (already *1000)
        );
        expect(frame[0], dirAppToRadio);
        expect(frame[3], cmdSetTuningParams);
        // rxDelayBase LE at offset 4
        expect(frame[4], 0xDC); // 1500 & 0xFF
        expect(frame[5], 0x05); // (1500 >> 8) & 0xFF
        expect(frame[6], 0x00);
        expect(frame[7], 0x00);
        // airtimeFactor LE at offset 8
        expect(frame[8], 0xC4); // 2500 & 0xFF
        expect(frame[9], 0x09); // (2500 >> 8) & 0xFF
        expect(frame[10], 0x00);
        expect(frame[11], 0x00);
        // 8 reserved zero bytes at offset 12
        expect(frame.sublist(12, 20), List.filled(8, 0));
      },
    );
  });

  group('CompanionEncoder - sendStatusReq', () {
    test('sendStatusReq passes public key as payload', () {
      final pubKey = Uint8List.fromList(List.generate(32, (i) => 0xAA));
      final frame = CompanionEncoder.sendStatusReq(pubKey);
      expect(frame[0], dirAppToRadio);
      expect(frame[3], cmdSendStatusReq);
      expect(frame.sublist(4), pubKey);
    });
  });

  // =========================================================================
  // Task 3: getByKey, signData/signFinish, sendTelemetryReq, sendBinaryReq,
  //         sendControlData
  // =========================================================================

  group('CompanionEncoder - getByKey', () {
    test('getByKey passes public key as payload', () {
      final pubKey = Uint8List.fromList(List.generate(32, (i) => i));
      final frame = CompanionEncoder.getByKey(pubKey);
      expect(frame[0], dirAppToRadio);
      expect(frame[3], cmdGetByKey);
      expect(frame.sublist(4), pubKey);
    });
  });

  group('CompanionEncoder - signData and signFinish', () {
    test('signData passes data chunk as payload', () {
      final data = Uint8List.fromList([0x01, 0x02, 0x03, 0x04]);
      final frame = CompanionEncoder.signData(data);
      expect(frame[0], dirAppToRadio);
      expect(frame[3], cmdSignData);
      expect(frame.sublist(4), data);
    });

    test('signFinish sends empty command', () {
      final frame = CompanionEncoder.signFinish();
      expect(frame[0], dirAppToRadio);
      expect(frame[3], cmdSignFinish);
      expect(frame.length, 4); // header only
    });
  });

  group('CompanionEncoder - sendTelemetryReq', () {
    test('sendTelemetryReq encodes reserved bytes then public key', () {
      final pubKey = Uint8List.fromList(List.generate(32, (i) => i));
      final frame = CompanionEncoder.sendTelemetryReq(pubKey);
      expect(frame[0], dirAppToRadio);
      expect(frame[3], cmdSendTelemetryReq);
      expect(frame.sublist(4, 7), [0, 0, 0]); // 3 reserved bytes
      expect(frame.sublist(7, 39), pubKey);
    });
  });

  group('CompanionEncoder - sendBinaryReq', () {
    test('sendBinaryReq encodes public key then request data', () {
      final pubKey = Uint8List.fromList(List.generate(32, (i) => i));
      final reqData = Uint8List.fromList([0xAA, 0xBB, 0xCC]);
      final frame = CompanionEncoder.sendBinaryReq(pubKey, reqData);
      expect(frame[0], dirAppToRadio);
      expect(frame[3], cmdSendBinaryReq);
      expect(frame.sublist(4, 36), pubKey);
      expect(frame.sublist(36), reqData);
    });
  });

  group('CompanionEncoder - sendControlData', () {
    test('sendControlData encodes flags, subType, and payload', () {
      final payload = Uint8List.fromList([0x01, 0x02]);
      final frame = CompanionEncoder.sendControlData(
        subType: 0x80,
        payload: payload,
      );
      expect(frame[0], dirAppToRadio);
      expect(frame[3], cmdSendControlData);
      expect(frame[4], 0x00); // flags = 0
      expect(frame[5], 0x80); // subType
      expect(frame.sublist(6), payload);
    });

    test('sendControlData without payload has only flags and subType', () {
      final frame = CompanionEncoder.sendControlData(subType: 0x01);
      expect(frame[0], dirAppToRadio);
      expect(frame[3], cmdSendControlData);
      expect(frame[4], 0x00); // flags = 0
      expect(frame[5], 0x01); // subType
      expect(frame.length, 6); // header(3) + cmd(1) + flags(1) + subType(1)
    });
  });
}
