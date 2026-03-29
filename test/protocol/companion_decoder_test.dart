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
}
