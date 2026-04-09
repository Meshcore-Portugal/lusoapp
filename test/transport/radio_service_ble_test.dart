import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lusoapp/protocol/protocol.dart';
import 'package:lusoapp/services/radio_service.dart';

import 'mock_radio_transport.dart';

void main() {
  late MockRadioTransport transport;
  late RadioService service;

  setUp(() {
    // BLE mode: usesFraming = false
    transport = MockRadioTransport(usesFraming: false, displayName: 'BLE Mock');
    service = RadioService(transport);
  });

  tearDown(() async {
    await service.dispose();
  });

  // =========================================================================
  // BLE send — strips 3-byte header
  // =========================================================================

  group('RadioService - BLE send (non-framed)', () {
    test('connect strips direction+length header from APP_START', () async {
      await service.connect(appName: 'Test');

      // APP_START should have header stripped: just [cmd][payload...]
      final appStart = transport.sentData[0];
      expect(
        appStart[0],
        cmdAppStart,
        reason: 'first byte should be command, not direction',
      );
      // Should NOT start with dirAppToRadio
      expect(appStart[0], isNot(dirAppToRadio));
    });

    test('command frames have no direction+length header', () async {
      await service.connect();
      transport.sentData.clear();

      await service.requestContacts();
      final frame = transport.sentData[0];

      // BLE: first byte is command directly
      expect(frame[0], cmdGetContacts);
      // No direction byte prefix
      expect(frame[0], isNot(dirAppToRadio));
    });

    test('setTxPower sends command byte + power byte only', () async {
      await service.connect();
      transport.sentData.clear();

      await service.setTxPower(22);
      final frame = transport.sentData[0];

      expect(frame[0], cmdSetTxPower);
      expect(frame[1], 22);
      expect(frame.length, 2); // cmd + power
    });
  });

  // =========================================================================
  // BLE receive — each notification is a complete frame
  // =========================================================================

  group('RadioService - BLE receive (non-framed)', () {
    setUp(() async {
      await service.connect();
      transport.sentData.clear();
    });

    test('decodes raw companion payload without framing', () async {
      final responses = <CompanionResponse>[];
      service.responses.listen(responses.add);

      // BLE: inject raw [cmd] directly (no direction/length wrapper)
      transport.injectData(Uint8List.fromList([respOk]));
      await Future<void>.delayed(Duration.zero);

      expect(responses.length, 1);
      expect(responses[0], isA<OkResponse>());
    });

    test('decodes Error response from raw payload', () async {
      final responses = <CompanionResponse>[];
      service.responses.listen(responses.add);

      transport.injectData(Uint8List.fromList([respErr, 0x03]));
      await Future<void>.delayed(Duration.zero);

      expect(responses.length, 1);
      expect(responses[0], isA<ErrorResponse>());
      expect((responses[0] as ErrorResponse).errorCode, 0x03);
    });

    test('each BLE notification is treated as one complete frame', () async {
      final responses = <CompanionResponse>[];
      service.responses.listen(responses.add);

      // Two separate notifications
      transport.injectData(Uint8List.fromList([respOk]));
      transport.injectData(Uint8List.fromList([respSent]));
      await Future<void>.delayed(Duration.zero);

      expect(responses.length, 2);
      expect(responses[0], isA<OkResponse>());
      expect(responses[1], isA<SentResponse>());
    });

    test('BattAndStorage updates state from raw BLE payload', () async {
      transport.injectData(
        Uint8List.fromList([
          respBattAndStorage,
          0x68, 0x10, // 4200 LE (uint16)
        ]),
      );
      await Future<void>.delayed(Duration.zero);

      expect(service.batteryMv, 4200);
    });

    test('MsgWaitingPush triggers syncNext in BLE mode', () async {
      transport.injectData(Uint8List.fromList([pushMsgWaiting]));
      await Future<void>.delayed(Duration.zero);

      // Should have sent SYNC_NEXT (without framing header)
      expect(transport.sentData.length, 1);
      expect(transport.sentData[0][0], cmdSyncNext);
    });
  });

  // =========================================================================
  // Connection loss in BLE mode
  // =========================================================================

  group('RadioService - BLE connection loss', () {
    test('propagates connectionLost in BLE mode', () async {
      await service.connect();

      var lostFired = false;
      service.connectionLost.listen((_) => lostFired = true);

      transport.injectConnectionLost();
      await Future<void>.delayed(Duration.zero);

      expect(lostFired, true);
    });
  });
}
