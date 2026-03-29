import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcapppt/protocol/commands.dart';
import 'package:mcapppt/protocol/companion_decoder.dart';

void main() {
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
