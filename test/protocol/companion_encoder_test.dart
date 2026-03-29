import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcapppt/protocol/commands.dart';
import 'package:mcapppt/protocol/companion_encoder.dart';

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
  // =========================================================================
  // Task 1: Contact management commands
  // =========================================================================

  group('CompanionEncoder - addUpdateContact', () {
    test('addUpdateContact encodes full contact payload', () {
      final pubKey = Uint8List.fromList(List.generate(32, (i) => i));
      final outPath = Uint8List(64);
      final frame = CompanionEncoder.addUpdateContact(
        publicKey: pubKey,
        type: 0x01,
        flags: 0x02,
        outPathLen: 3,
        outPath: outPath,
        name: 'TestNode',
        lastAdvert: 1000000,
      );
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

    test('addUpdateContact with lat/lon appends int32 LE values', () {
      final pubKey = Uint8List.fromList(List.generate(32, (i) => i));
      final outPath = Uint8List(64);
      final frame = CompanionEncoder.addUpdateContact(
        publicKey: pubKey,
        type: 0x01,
        flags: 0x00,
        outPathLen: 0,
        outPath: outPath,
        name: 'GpsNode',
        lastAdvert: 500000,
        latitude: 38.736946,
        longitude: -9.142685,
      );
      // lat/lon at offset 139..146
      final lat = readInt32LE(frame, 139);
      final lon = readInt32LE(frame, 143);
      expect(lat, closeTo(38736946, 1));
      expect(lon, closeTo(-9142685, 1));
    });

    test('addUpdateContact without lat/lon has shorter frame', () {
      final pubKey = Uint8List.fromList(List.generate(32, (i) => i));
      final outPath = Uint8List(64);
      final withoutGps = CompanionEncoder.addUpdateContact(
        publicKey: pubKey,
        type: 0x01,
        flags: 0x00,
        outPathLen: 0,
        outPath: outPath,
        name: 'NoGps',
        lastAdvert: 100,
      );
      final withGps = CompanionEncoder.addUpdateContact(
        publicKey: pubKey,
        type: 0x01,
        flags: 0x00,
        outPathLen: 0,
        outPath: outPath,
        name: 'NoGps',
        lastAdvert: 100,
        latitude: 0.0,
        longitude: 0.0,
      );
      // With GPS should be 8 bytes longer (2 x int32)
      expect(withGps.length - withoutGps.length, 8);
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
    test('setTuningParams encodes rxdelay, airtime factor, and reserved bytes',
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
    });
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
}
