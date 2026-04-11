import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lusoapp/protocol/models.dart';

void main() {
  group('Contact', () {
    test(
      'shortId returns empty string when publicKey has fewer than 4 bytes',
      () {
        final contact = Contact(
          publicKey: Uint8List.fromList([0x01, 0x02]),
          type: 1,
          flags: 0,
          pathLen: 0,
          name: 'Short',
          lastAdvertTimestamp: 0,
        );
        expect(contact.shortId, isEmpty);
      },
    );

    test('isRoom returns true for type 3', () {
      final contact = Contact(
        publicKey: Uint8List(32),
        type: 3,
        flags: 0,
        pathLen: 0,
        name: 'Room',
        lastAdvertTimestamp: 0,
      );
      expect(contact.isRoom, true);
      expect(contact.isChat, false);
      expect(contact.isRepeater, false);
      expect(contact.isSensor, false);
    });

    test('isSensor returns true for type 4', () {
      final contact = Contact(
        publicKey: Uint8List(32),
        type: 4,
        flags: 0,
        pathLen: 0,
        name: 'Sensor',
        lastAdvertTimestamp: 0,
      );
      expect(contact.isSensor, true);
      expect(contact.isRoom, false);
    });
  });

  group('RadioConfig', () {
    test('copyWith preserves all unchanged fields', () {
      const config = RadioConfig(
        frequencyHz: 869618,
        bandwidthHz: 62500,
        spreadingFactor: 10,
        codingRate: 5,
        txPowerDbm: 14,
      );
      final modified = config.copyWith(spreadingFactor: 12);
      expect(modified.spreadingFactor, 12);
      expect(modified.frequencyHz, 869618);
      expect(modified.bandwidthHz, 62500);
      expect(modified.codingRate, 5);
      expect(modified.txPowerDbm, 14);
    });
  });

  group('ChatMessage', () {
    test('isChannel is true when channelIndex is set', () {
      const msg = ChatMessage(
        text: 'hello',
        timestamp: 1000,
        isOutgoing: false,
        channelIndex: 0,
      );
      expect(msg.isChannel, true);
      expect(msg.isPrivate, false);
    });

    test('isPrivate is true when channelIndex is null', () {
      const msg = ChatMessage(text: 'hello', timestamp: 1000, isOutgoing: true);
      expect(msg.isPrivate, true);
      expect(msg.isChannel, false);
    });
  });

  group('DeviceInfo', () {
    test('batteryVolts converts millivolts correctly', () {
      const info = DeviceInfo(
        firmwareVersion: 3,
        deviceName: 'Test',
        batteryMillivolts: 3700,
      );
      expect(info.batteryVolts, closeTo(3.7, 0.001));
    });

    test('batteryVolts is 0 when millivolts is 0', () {
      const info = DeviceInfo(
        firmwareVersion: 3,
        deviceName: 'Test',
        batteryMillivolts: 0,
      );
      expect(info.batteryVolts, 0.0);
    });
  });

  group('ChannelInfo', () {
    test('isEmpty is true when name is empty and secret is null', () {
      const ch = ChannelInfo(index: 0, name: '');
      expect(ch.isEmpty, true);
    });

    test('isEmpty is true when name is empty and secret is all zeros', () {
      final ch = ChannelInfo(index: 0, name: '', secret: Uint8List(16));
      expect(ch.isEmpty, true);
    });

    test('isEmpty is false when name is set', () {
      const ch = ChannelInfo(index: 0, name: 'General');
      expect(ch.isEmpty, false);
    });

    test('isEmpty is false when secret has non-zero bytes', () {
      final secret = Uint8List(16);
      secret[0] = 0x01;
      final ch = ChannelInfo(index: 0, name: '', secret: secret);
      expect(ch.isEmpty, false);
    });
  });
}
