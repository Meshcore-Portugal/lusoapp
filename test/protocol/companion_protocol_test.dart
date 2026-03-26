import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcapppt/protocol/commands.dart';
import 'package:mcapppt/protocol/companion_encoder.dart';
import 'package:mcapppt/protocol/companion_decoder.dart';
import 'package:mcapppt/protocol/models.dart';

void main() {
  group('CompanionEncoder', () {
    test('appStart includes direction, length, command, reserved, name', () {
      final frame = CompanionEncoder.appStart('TestApp');
      expect(frame[0], dirAppToRadio); // '<'
      // Length is in bytes 1-2 (little-endian)
      final payloadLen = frame[1] | (frame[2] << 8);
      expect(payloadLen, greaterThan(0));
      // Command byte
      expect(frame[3], cmdAppStart);
    });

    test('sendChannelMessage encodes channel index and text', () {
      final frame = CompanionEncoder.sendChannelMessage(0, 'Ola');
      expect(frame[0], dirAppToRadio);
      expect(frame[3], cmdSendChanMsg);
      // Payload: txtPlain(1) + channelIdx(1) + timestamp(4) + text
      expect(frame[4], txtPlain);
      expect(frame[5], 0); // channel 0
    });

    test('sendMessage encodes recipient prefix and text', () {
      final prefix = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final frame = CompanionEncoder.sendMessage(prefix, 'Hello');
      expect(frame[0], dirAppToRadio);
      expect(frame[3], cmdSendMsg);
      expect(frame[4], txtPlain);
    });

    test('setRadioParams encodes LoRa configuration', () {
      const config = RadioConfig(
        frequencyHz: 869618000,
        bandwidthHz: 62500,
        spreadingFactor: 10,
        codingRate: 5,
        txPowerDbm: 14,
      );
      final frame = CompanionEncoder.setRadioParams(config);
      expect(frame[0], dirAppToRadio);
      expect(frame[3], cmdSetRadioParams);
    });

    test('getContacts with no timestamp', () {
      final frame = CompanionEncoder.getContacts();
      expect(frame[0], dirAppToRadio);
      expect(frame[3], cmdGetContacts);
    });

    test('setTxPower encodes power byte', () {
      final frame = CompanionEncoder.setTxPower(14);
      expect(frame[0], dirAppToRadio);
      expect(frame[3], cmdSetTxPower);
      expect(frame[4], 14);
    });

    test('reboot sends reboot command', () {
      final frame = CompanionEncoder.reboot();
      expect(frame[0], dirAppToRadio);
      expect(frame[3], cmdReboot);
    });
  });

  group('CompanionDecoder', () {
    test('decode OK response', () {
      final payload = Uint8List.fromList([respOk]);
      final resp = CompanionDecoder.decode(payload);
      expect(resp, isA<OkResponse>());
    });

    test('decode Error response with code', () {
      final payload = Uint8List.fromList([respErr, 0x02]);
      final resp = CompanionDecoder.decode(payload);
      expect(resp, isA<ErrorResponse>());
      expect((resp as ErrorResponse).errorCode, 0x02);
    });

    test('decode NoMoreMessages response', () {
      final payload = Uint8List.fromList([respNoMoreMessages]);
      final resp = CompanionDecoder.decode(payload);
      expect(resp, isA<NoMoreMessagesResponse>());
    });

    test('decode ContactsStart response', () {
      final payload = Uint8List.fromList([respContactsStart]);
      final resp = CompanionDecoder.decode(payload);
      expect(resp, isA<ContactsStartResponse>());
    });

    test('decode unknown response returns UnknownResponse', () {
      final payload = Uint8List.fromList([0xFE, 0x01, 0x02]);
      final resp = CompanionDecoder.decode(payload);
      expect(resp, isA<UnknownResponse>());
      expect((resp as UnknownResponse).code, 0xFE);
    });

    test('extractFrames parses complete frames', () {
      // Build: ['>'][len_lo][len_hi][payload]
      final frame1Payload = Uint8List.fromList([respOk]);
      final frame2Payload = Uint8List.fromList([respNoMoreMessages]);

      final buffer = Uint8List.fromList([
        dirRadioToApp, 1, 0, ...frame1Payload,
        dirRadioToApp, 1, 0, ...frame2Payload,
      ]);

      final (frames, remaining) = CompanionDecoder.extractFrames(buffer);
      expect(frames.length, 2);
      expect(frames[0], frame1Payload);
      expect(frames[1], frame2Payload);
      expect(remaining.length, 0);
    });

    test('extractFrames handles incomplete frame at end', () {
      final buffer = Uint8List.fromList([
        dirRadioToApp, 1, 0, respOk,
        dirRadioToApp, 5, 0, // incomplete: needs 5 bytes but has 0
      ]);

      final (frames, remaining) = CompanionDecoder.extractFrames(buffer);
      expect(frames.length, 1);
      expect(remaining.length, greaterThan(0));
    });
  });

  group('RadioConfig', () {
    test('frequencyMHz calculates correctly', () {
      const config = RadioConfig(
        frequencyHz: 869618000,
        bandwidthHz: 62500,
        spreadingFactor: 10,
        codingRate: 5,
        txPowerDbm: 14,
      );
      expect(config.frequencyMHz, closeTo(869.618, 0.001));
      expect(config.bandwidthKHz, closeTo(62.5, 0.1));
    });

    test('copyWith creates modified copy', () {
      const config = RadioConfig(
        frequencyHz: 869618000,
        bandwidthHz: 62500,
        spreadingFactor: 10,
        codingRate: 5,
        txPowerDbm: 14,
      );
      final modified = config.copyWith(txPowerDbm: 20);
      expect(modified.txPowerDbm, 20);
      expect(modified.frequencyHz, 869618000);
    });
  });

  group('Contact', () {
    test('shortId returns hex of first 4 bytes', () {
      final contact = Contact(
        publicKey: Uint8List.fromList(List.generate(32, (i) => i)),
        type: 1,
        flags: 0,
        pathLen: 0,
        name: 'Test',
        lastAdvertTimestamp: 0,
      );
      expect(contact.shortId, '00010203');
    });

    test('type checks work correctly', () {
      final chat = Contact(
        publicKey: Uint8List(32),
        type: 1,
        flags: 0,
        pathLen: 0,
        name: 'Chat',
        lastAdvertTimestamp: 0,
      );
      expect(chat.isChat, true);
      expect(chat.isRepeater, false);

      final repeater = Contact(
        publicKey: Uint8List(32),
        type: 2,
        flags: 0,
        pathLen: 0,
        name: 'Repeater',
        lastAdvertTimestamp: 0,
      );
      expect(repeater.isRepeater, true);
      expect(repeater.isChat, false);
    });
  });
}
