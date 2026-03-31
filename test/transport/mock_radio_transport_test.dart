import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'mock_radio_transport.dart';

void main() {
  group('MockRadioTransport', () {
    test('starts disconnected', () {
      final mock = MockRadioTransport();
      expect(mock.isConnected, false);
    });

    test('connect sets isConnected to true', () async {
      final mock = MockRadioTransport();
      final ok = await mock.connect();
      expect(ok, true);
      expect(mock.isConnected, true);
    });

    test('connect returns false when configured to fail', () async {
      final mock = MockRadioTransport(connectResult: false);
      final ok = await mock.connect();
      expect(ok, false);
      expect(mock.isConnected, false);
    });

    test('disconnect sets isConnected to false', () async {
      final mock = MockRadioTransport();
      await mock.connect();
      await mock.disconnect();
      expect(mock.isConnected, false);
    });

    test('send records data in sentData list', () async {
      final mock = MockRadioTransport();
      await mock.send(Uint8List.fromList([0x01, 0x02]));
      await mock.send(Uint8List.fromList([0x03]));
      expect(mock.sentData.length, 2);
      expect(mock.sentData[0], Uint8List.fromList([0x01, 0x02]));
      expect(mock.sentData[1], Uint8List.fromList([0x03]));
    });

    test('injectData delivers bytes on dataStream', () async {
      final mock = MockRadioTransport();
      final received = <Uint8List>[];
      mock.dataStream.listen(received.add);
      mock.injectData(Uint8List.fromList([0xAA, 0xBB]));
      await Future<void>.delayed(Duration.zero);
      expect(received.length, 1);
      expect(received[0], Uint8List.fromList([0xAA, 0xBB]));
    });

    test('injectConnectionLost fires connectionLost stream', () async {
      final mock = MockRadioTransport();
      var fired = false;
      mock.connectionLost.listen((_) => fired = true);
      mock.injectConnectionLost();
      await Future<void>.delayed(Duration.zero);
      expect(fired, true);
    });

    test('usesFraming defaults to true', () {
      expect(MockRadioTransport().usesFraming, true);
    });

    test('usesFraming can be set to false (BLE mode)', () {
      final mock = MockRadioTransport(usesFraming: false);
      expect(mock.usesFraming, false);
    });

    test('displayName returns configured name', () {
      final mock = MockRadioTransport(displayName: 'Test BLE');
      expect(mock.displayName, 'Test BLE');
    });

    test('dispose marks as disposed', () async {
      final mock = MockRadioTransport();
      await mock.dispose();
      expect(mock.isDisposed, true);
    });
  });
}
