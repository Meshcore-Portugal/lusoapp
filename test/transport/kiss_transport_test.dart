import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcapppt/protocol/kiss.dart';
import 'package:mcapppt/transport/kiss_transport.dart';

import 'mock_radio_transport.dart';

void main() {
  late MockRadioTransport inner;
  late KissTransport kiss;

  setUp(() {
    inner = MockRadioTransport();
    kiss = KissTransport(inner);
  });

  tearDown(() async {
    await kiss.dispose();
  });

  group('KissTransport - properties', () {
    test('displayName appends [KISS] to inner name', () {
      expect(kiss.displayName, 'Mock Transport [KISS]');
    });

    test('usesFraming is always true', () {
      expect(kiss.usesFraming, true);
    });

    test('isConnected delegates to inner transport', () async {
      expect(kiss.isConnected, false);
      await kiss.connect();
      expect(kiss.isConnected, true);
    });
  });

  group('KissTransport - connect/disconnect', () {
    test('connect delegates to inner and returns result', () async {
      final ok = await kiss.connect();
      expect(ok, true);
      expect(inner.isConnected, true);
    });

    test('connect returns false when inner fails', () async {
      final failInner = MockRadioTransport(connectResult: false);
      final failKiss = KissTransport(failInner);
      final ok = await failKiss.connect();
      expect(ok, false);
      await failKiss.dispose();
    });

    test('disconnect delegates to inner', () async {
      await kiss.connect();
      await kiss.disconnect();
      expect(inner.isConnected, false);
    });
  });

  group('KissTransport - send (outbound framing)', () {
    test('send wraps payload in KISS data frame', () async {
      await kiss.connect();
      final payload = Uint8List.fromList([0x01, 0x02, 0x03]);
      await kiss.send(payload);

      expect(inner.sentData.length, 1);
      final sent = inner.sentData[0];
      // KISS frame: FEND, command(0x00), data..., FEND
      expect(sent[0], Kiss.fend);
      expect(sent[1], 0x00); // command byte = data frame
      expect(sent.last, Kiss.fend);

      // Verify inner bytes: strip FENDs, decode command+data
      // FEND is at index 0 and last; command at index 1; data in between
      final inner_ = sent.sublist(1, sent.length - 1);
      final decoded = Kiss.decode(inner_);
      expect(decoded, isNotNull);
      expect(decoded!.command, 0x00);
      expect(decoded!.data, payload);
    });

    test('send escapes FEND bytes in payload', () async {
      await kiss.connect();
      final payload = Uint8List.fromList([Kiss.fend, 0x42]);
      await kiss.send(payload);

      final sent = inner.sentData[0];
      // FEND in data should become FESC TFEND
      expect(sent.contains(Kiss.fesc), true);
    });
  });

  group('KissTransport - receive (inbound deframing)', () {
    test('decodes complete KISS frame from inner and emits payload', () async {
      await kiss.connect();

      final received = <Uint8List>[];
      kiss.dataStream.listen(received.add);

      // Inject a KISS-encoded frame into the inner transport
      final originalPayload = Uint8List.fromList([0xAA, 0xBB, 0xCC]);
      final kissFrame = Kiss.encode(0x00, originalPayload);
      inner.injectData(kissFrame);

      await Future<void>.delayed(Duration.zero);

      expect(received.length, 1);
      expect(received[0], originalPayload);
    });

    test('handles split KISS frames across multiple data events', () async {
      await kiss.connect();

      final received = <Uint8List>[];
      kiss.dataStream.listen(received.add);

      final payload = Uint8List.fromList([0x01, 0x02, 0x03]);
      final kissFrame = Kiss.encode(0x00, payload);

      // Split frame in half
      final mid = kissFrame.length ~/ 2;
      inner.injectData(kissFrame.sublist(0, mid));
      await Future<void>.delayed(Duration.zero);
      expect(received, isEmpty, reason: 'incomplete frame should not emit');

      inner.injectData(kissFrame.sublist(mid));
      await Future<void>.delayed(Duration.zero);
      expect(received.length, 1);
      expect(received[0], payload);
    });

    test('decodes multiple KISS frames from single data event', () async {
      await kiss.connect();

      final received = <Uint8List>[];
      kiss.dataStream.listen(received.add);

      final frame1 = Kiss.encode(0x00, Uint8List.fromList([0x01]));
      final frame2 = Kiss.encode(0x00, Uint8List.fromList([0x02]));
      final combined = Uint8List.fromList([...frame1, ...frame2]);
      inner.injectData(combined);

      await Future<void>.delayed(Duration.zero);

      expect(received.length, 2);
      expect(received[0], Uint8List.fromList([0x01]));
      expect(received[1], Uint8List.fromList([0x02]));
    });

    test('ignores non-data KISS frames', () async {
      await kiss.connect();

      final received = <Uint8List>[];
      kiss.dataStream.listen(received.add);

      // Command 0x06 = SetHardware, not a data frame
      final nonDataFrame = Kiss.encode(0x06, Uint8List.fromList([0xFF]));
      inner.injectData(nonDataFrame);

      await Future<void>.delayed(Duration.zero);

      expect(received, isEmpty);
    });
  });

  group('KissTransport - connectionLost', () {
    test('propagates connectionLost from inner transport', () async {
      await kiss.connect();

      var lostFired = false;
      kiss.connectionLost.listen((_) => lostFired = true);

      inner.injectConnectionLost();
      await Future<void>.delayed(Duration.zero);

      expect(lostFired, true);
    });
  });
}
