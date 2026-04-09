import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lusoapp/protocol/kiss.dart';

void main() {
  group('Kiss', () {
    test('encode wraps data in FEND delimiters with command byte', () {
      final data = Uint8List.fromList([0x01, 0x02, 0x03]);
      final frame = Kiss.encode(0x00, data);

      expect(frame.first, Kiss.fend);
      expect(frame.last, Kiss.fend);
      expect(frame[1], 0x00); // command byte
      expect(frame.sublist(2, 5), data);
    });

    test('encode escapes FEND bytes in data', () {
      final data = Uint8List.fromList([0xAA, Kiss.fend, 0xBB]);
      final frame = Kiss.encode(0x00, data);

      // After command: 0xAA, FESC, TFEND, 0xBB
      expect(frame[2], 0xAA);
      expect(frame[3], Kiss.fesc);
      expect(frame[4], Kiss.tfend);
      expect(frame[5], 0xBB);
    });

    test('encode escapes FESC bytes in data', () {
      final data = Uint8List.fromList([0xAA, Kiss.fesc, 0xBB]);
      final frame = Kiss.encode(0x00, data);

      expect(frame[3], Kiss.fesc);
      expect(frame[4], Kiss.tfesc);
    });

    test('decode reverses encode', () {
      final original = Uint8List.fromList([0x01, Kiss.fend, Kiss.fesc, 0xFF]);
      final encoded = Kiss.encode(0x06, original);

      // Strip FEND delimiters to get the inner frame
      final inner = encoded.sublist(1, encoded.length - 1);
      final decoded = Kiss.decode(inner);

      expect(decoded, isNotNull);
      expect(decoded!.command, 0x06);
      expect(decoded.data, original);
    });

    test('decode returns null for empty frame', () {
      expect(Kiss.decode(Uint8List(0)), isNull);
    });

    test('commandType extracts lower nibble', () {
      final frame = KissFrame(command: 0x36, data: Uint8List(0));
      expect(frame.commandType, 0x06);
      expect(frame.port, 0x03);
    });

    test('isSetHardware detects 0x06 command', () {
      final frame = KissFrame(command: 0x06, data: Uint8List(0));
      expect(frame.isSetHardware, true);
      expect(frame.isData, false);
    });
  });

  group('KissFrameAccumulator', () {
    test('extracts single complete frame', () {
      final acc = KissFrameAccumulator();
      final data = Uint8List.fromList([Kiss.fend, 0x00, 0x01, 0x02, Kiss.fend]);

      final frames = acc.feed(data);
      expect(frames.length, 1);
      expect(frames[0], Uint8List.fromList([0x00, 0x01, 0x02]));
    });

    test('handles split data across calls', () {
      final acc = KissFrameAccumulator();

      // First part: start of frame
      var frames = acc.feed(Uint8List.fromList([Kiss.fend, 0x00, 0x01]));
      expect(frames, isEmpty);

      // Second part: rest of frame
      frames = acc.feed(Uint8List.fromList([0x02, Kiss.fend]));
      expect(frames.length, 1);
      expect(frames[0], Uint8List.fromList([0x00, 0x01, 0x02]));
    });

    test('extracts multiple frames from one buffer', () {
      final acc = KissFrameAccumulator();
      final data = Uint8List.fromList([
        Kiss.fend,
        0x00,
        0xAA,
        Kiss.fend,
        Kiss.fend,
        0x06,
        0xBB,
        Kiss.fend,
      ]);

      final frames = acc.feed(data);
      expect(frames.length, 2);
      expect(frames[0], Uint8List.fromList([0x00, 0xAA]));
      expect(frames[1], Uint8List.fromList([0x06, 0xBB]));
    });

    test('reset clears accumulator state', () {
      final acc = KissFrameAccumulator();
      acc.feed(Uint8List.fromList([Kiss.fend, 0x00, 0x01]));
      acc.reset();
      // After reset, partial frame should be gone
      final frames = acc.feed(Uint8List.fromList([0x02, Kiss.fend]));
      expect(frames, isEmpty);
    });
  });
}
