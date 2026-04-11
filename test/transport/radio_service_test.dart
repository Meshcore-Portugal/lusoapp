import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lusoapp/protocol/protocol.dart';
import 'package:lusoapp/services/radio_service.dart';

import 'mock_radio_transport.dart';

/// Build a framed Radio→App response: [dir][len_lsb][len_msb][payload...]
Uint8List framedResponse(List<int> payload) {
  final len = payload.length;
  return Uint8List.fromList([
    dirRadioToApp,
    len & 0xFF,
    (len >> 8) & 0xFF,
    ...payload,
  ]);
}

void main() {
  late MockRadioTransport transport;
  late RadioService service;

  setUp(() {
    transport = MockRadioTransport(usesFraming: true);
    service = RadioService(transport);
  });

  tearDown(() async {
    await service.dispose();
  });

  // =========================================================================
  // Connection flow
  // =========================================================================

  group('RadioService - connect', () {
    test('connect sends APP_START and SET_DEVICE_TIME', () async {
      await service.connect(appName: 'TestApp');

      expect(transport.sentData.length, 2);

      // First frame: APP_START
      final appStart = transport.sentData[0];
      expect(appStart[0], dirAppToRadio); // direction
      expect(appStart[3], cmdAppStart); // command

      // Second frame: SET_DEVICE_TIME
      final setTime = transport.sentData[1];
      expect(setTime[0], dirAppToRadio);
      expect(setTime[3], cmdSetDeviceTime);
      // Payload should be 4 bytes (uint32 LE timestamp)
      expect(setTime.length - 4, 4); // 4 header bytes + 4 payload
    });

    test('connect returns true on success', () async {
      final ok = await service.connect();
      expect(ok, true);
      expect(service.isConnected, true);
    });

    test('connect returns false when transport fails', () async {
      final failTransport = MockRadioTransport(connectResult: false);
      final failService = RadioService(failTransport);
      final ok = await failService.connect();
      expect(ok, false);
      expect(
        failTransport.sentData,
        isEmpty,
        reason: 'no commands sent on failed connect',
      );
      await failService.dispose();
    });
  });

  // =========================================================================
  // Command methods → correct frames
  // =========================================================================

  group('RadioService - commands (framed/serial mode)', () {
    setUp(() async {
      await service.connect();
      transport.sentData.clear(); // clear APP_START + SET_TIME
    });

    test('requestContacts sends GET_CONTACTS command', () async {
      await service.requestContacts();
      expect(transport.sentData.length, 1);
      expect(transport.sentData[0][3], cmdGetContacts);
    });

    test('sendPrivateMessage sends SEND_MSG command', () async {
      final prefix = Uint8List.fromList([0x01, 0x02, 0x03, 0x04, 0x05, 0x06]);
      await service.sendPrivateMessage(prefix, 'Hello');
      expect(transport.sentData.length, 1);
      expect(transport.sentData[0][3], cmdSendMsg);
    });

    test('sendChannelMessage sends SEND_CHAN_MSG command', () async {
      await service.sendChannelMessage(2, 'Test msg');
      expect(transport.sentData.length, 1);
      expect(transport.sentData[0][3], cmdSendChanMsg);
    });

    test('syncNextMessage sends SYNC_NEXT command', () async {
      await service.syncNextMessage();
      expect(transport.sentData.length, 1);
      expect(transport.sentData[0][3], cmdSyncNext);
    });

    test('requestDeviceInfo sends DEVICE_QUERY command', () async {
      await service.requestDeviceInfo();
      expect(transport.sentData.length, 1);
      expect(transport.sentData[0][3], cmdDeviceQuery);
    });

    test('requestBattAndStorage sends GET_BATT_AND_STORAGE command', () async {
      await service.requestBattAndStorage();
      expect(transport.sentData.length, 1);
      expect(transport.sentData[0][3], cmdGetBattAndStorage);
    });

    test('setTxPower sends SET_TX_POWER command', () async {
      await service.setTxPower(14);
      expect(transport.sentData.length, 1);
      expect(transport.sentData[0][3], cmdSetTxPower);
      expect(transport.sentData[0][4], 14); // power byte
    });

    test('reboot sends REBOOT command', () async {
      await service.reboot();
      expect(transport.sentData.length, 1);
      expect(transport.sentData[0][3], cmdReboot);
    });

    test('setLocation sends SET_ADVERT_LATLON command', () async {
      await service.setLocation(38.736946, -9.142685);
      expect(transport.sentData.length, 1);
      expect(transport.sentData[0][3], cmdSetAdvertLatLon);
    });

    test('framed mode sends full frame with direction+length header', () async {
      await service.requestContacts();
      final frame = transport.sentData[0];
      expect(frame[0], dirAppToRadio); // direction byte present
      // length bytes
      final payloadLen = frame[1] | (frame[2] << 8);
      expect(payloadLen, frame.length - 3);
    });
  });

  // =========================================================================
  // Response decoding and routing
  // =========================================================================

  group('RadioService - response decoding (framed)', () {
    setUp(() async {
      await service.connect();
      transport.sentData.clear();
    });

    test('decodes OK response from framed data', () async {
      final responses = <CompanionResponse>[];
      service.responses.listen(responses.add);

      transport.injectData(framedResponse([respOk]));
      await Future<void>.delayed(Duration.zero);

      expect(responses.length, 1);
      expect(responses[0], isA<OkResponse>());
    });

    test('decodes Error response with error code', () async {
      final responses = <CompanionResponse>[];
      service.responses.listen(responses.add);

      transport.injectData(framedResponse([respErr, 0x05]));
      await Future<void>.delayed(Duration.zero);

      expect(responses.length, 1);
      expect(responses[0], isA<ErrorResponse>());
      expect((responses[0] as ErrorResponse).errorCode, 0x05);
    });

    test('decodes multiple frames from a single data chunk', () async {
      final responses = <CompanionResponse>[];
      service.responses.listen(responses.add);

      // Two frames back-to-back
      final frame1 = framedResponse([respOk]);
      final frame2 = framedResponse([respSent]);
      transport.injectData(Uint8List.fromList([...frame1, ...frame2]));
      await Future<void>.delayed(Duration.zero);

      expect(responses.length, 2);
      expect(responses[0], isA<OkResponse>());
      expect(responses[1], isA<SentResponse>());
    });

    test('handles partial frame across multiple data events', () async {
      final responses = <CompanionResponse>[];
      service.responses.listen(responses.add);

      final frame = framedResponse([respOk]);
      // Split in the middle
      transport.injectData(frame.sublist(0, 2));
      await Future<void>.delayed(Duration.zero);
      expect(responses, isEmpty);

      transport.injectData(frame.sublist(2));
      await Future<void>.delayed(Duration.zero);
      expect(responses.length, 1);
      expect(responses[0], isA<OkResponse>());
    });
  });

  // =========================================================================
  // State updates from responses
  // =========================================================================

  group('RadioService - state updates', () {
    setUp(() async {
      await service.connect();
      transport.sentData.clear();
    });

    test('BattAndStorage updates batteryMv', () async {
      final battPayload = [
        respBattAndStorage,
        0x74, 0x0E, // 3700 LE (uint16)
      ];
      transport.injectData(framedResponse(battPayload));
      await Future<void>.delayed(Duration.zero);

      expect(service.batteryMv, 3700);
    });

    test('ContactsStart clears contacts list', () async {
      // Pre-populate a fake contact
      service.contacts.add(
        Contact(
          publicKey: Uint8List(32),
          type: 1,
          flags: 0,
          pathLen: 0,
          name: 'Old',
          lastAdvertTimestamp: 0,
        ),
      );
      expect(service.contacts.length, 1);

      transport.injectData(framedResponse([respContactsStart]));
      await Future<void>.delayed(Duration.zero);

      expect(service.contacts, isEmpty);
    });

    test('MsgWaitingPush triggers syncNext automatically', () async {
      transport.injectData(framedResponse([pushMsgWaiting]));
      await Future<void>.delayed(Duration.zero);

      // Should have auto-sent SYNC_NEXT
      expect(transport.sentData.length, 1);
      expect(transport.sentData[0][3], cmdSyncNext);
    });
  });

  // =========================================================================
  // Connection loss
  // =========================================================================

  group('RadioService - connection loss', () {
    test('propagates connectionLost from transport', () async {
      await service.connect();

      var lostFired = false;
      service.connectionLost.listen((_) => lostFired = true);

      transport.injectConnectionLost();
      await Future<void>.delayed(Duration.zero);

      expect(lostFired, true);
    });
  });

  // =========================================================================
  // Disconnect / dispose
  // =========================================================================

  group('RadioService - disconnect', () {
    test('disconnect clears rx buffer and disconnects transport', () async {
      await service.connect();
      await service.disconnect();
      expect(transport.isConnected, false);
    });

    test('dispose disconnects and disposes transport', () async {
      await service.connect();
      // Create a new service/transport pair for this test since tearDown
      // also calls dispose
      final t2 = MockRadioTransport();
      final s2 = RadioService(t2);
      await s2.connect();
      await s2.dispose();
      expect(t2.isDisposed, true);
      expect(t2.isConnected, false);
    });
  });
}
