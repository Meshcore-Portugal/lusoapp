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

    test('isStaleAfter uses custom threshold', () {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final fiveDaysAgo = now - (5 * 24 * 60 * 60);
      final contact = Contact(
        publicKey: Uint8List(32),
        type: 1,
        flags: 0,
        pathLen: 0,
        name: 'TestContact',
        lastAdvertTimestamp: fiveDaysAgo,
      );
      // Not stale after 7 days
      expect(contact.isStaleAfter(7), false);
      // Is stale after 4 days
      expect(contact.isStaleAfter(4), true);
      // Not stale after 6 days
      expect(contact.isStaleAfter(6), false);
    });

    test('isStale defaults to 7 days threshold', () {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final eightDaysAgo = now - (8 * 24 * 60 * 60);
      final contact = Contact(
        publicKey: Uint8List(32),
        type: 1,
        flags: 0,
        pathLen: 0,
        name: 'OldContact',
        lastAdvertTimestamp: eightDaysAgo,
      );
      expect(contact.isStale, true);
      expect(contact.isStaleAfter(7), true);
    });

    test('isStale returns false when lastAdvertTimestamp is recent', () {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final threeDaysAgo = now - (3 * 24 * 60 * 60);
      final contact = Contact(
        publicKey: Uint8List(32),
        type: 1,
        flags: 0,
        pathLen: 0,
        name: 'RecentContact',
        lastAdvertTimestamp: threeDaysAgo,
      );
      expect(contact.isStale, false);
    });

    test(
      'isStale returns false when lastAdvertTimestamp is exactly 7 days',
      () {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final sevenDaysAgo = now - (7 * 24 * 60 * 60);
        final contact = Contact(
          publicKey: Uint8List(32),
          type: 1,
          flags: 0,
          pathLen: 0,
          name: 'BoundaryContact',
          lastAdvertTimestamp: sevenDaysAgo,
        );
        expect(contact.isStale, false);
      },
    );
  });

  group('PruneConfig', () {
    test('default config prunes all types after 7 days', () {
      expect(PruneConfig.defaultConfig.daysThreshold, 7);
      expect(PruneConfig.defaultConfig.pruneChats, true);
      expect(PruneConfig.defaultConfig.pruneRepeaters, true);
      expect(PruneConfig.defaultConfig.pruneRooms, true);
      expect(PruneConfig.defaultConfig.pruneSensors, true);
    });

    test('shouldPrune respects staleness threshold', () {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final fiveDaysAgo = now - (5 * 24 * 60 * 60);
      final contact = Contact(
        publicKey: Uint8List(32),
        type: 0x01, // chat
        flags: 0,
        pathLen: 0,
        name: 'Chat',
        lastAdvertTimestamp: fiveDaysAgo,
      );
      final config = PruneConfig(
        daysThreshold: 3,
        pruneChats: true,
        pruneRepeaters: true,
        pruneRooms: true,
        pruneSensors: true,
      );
      expect(config.shouldPrune(contact), true); // 5 days > 3 day threshold
    });

    test('shouldPrune respects contact type filtering', () {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final eightDaysAgo = now - (8 * 24 * 60 * 60);

      final repeater = Contact(
        publicKey: Uint8List(32),
        type: 0x02,
        flags: 0,
        pathLen: 0,
        name: 'Repeater',
        lastAdvertTimestamp: eightDaysAgo,
      );

      // Don't prune repeaters
      final config = PruneConfig(
        daysThreshold: 7,
        pruneChats: true,
        pruneRepeaters: false,
        pruneRooms: true,
        pruneSensors: true,
      );
      expect(config.shouldPrune(repeater), false);
    });

    test('shouldPrune allows selective pruning by type', () {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      final eightDaysAgo = now - (8 * 24 * 60 * 60);

      final chat = Contact(
        publicKey: Uint8List(32),
        type: 0x01,
        flags: 0,
        pathLen: 0,
        name: 'Chat',
        lastAdvertTimestamp: eightDaysAgo,
      );

      final room = Contact(
        publicKey: Uint8List.fromList(List.generate(32, (i) => i + 1)),
        type: 0x03,
        flags: 0,
        pathLen: 0,
        name: 'Room',
        lastAdvertTimestamp: eightDaysAgo,
      );

      // Prune only rooms
      final config = PruneConfig(
        daysThreshold: 7,
        pruneChats: false,
        pruneRepeaters: false,
        pruneRooms: true,
        pruneSensors: false,
      );

      expect(config.shouldPrune(chat), false);
      expect(config.shouldPrune(room), true);
    });

    test('copyWith preserves unchanged fields', () {
      final original = PruneConfig(
        daysThreshold: 14,
        pruneChats: true,
        pruneRepeaters: false,
        pruneRooms: true,
        pruneSensors: false,
      );

      final modified = original.copyWith(daysThreshold: 30);
      expect(modified.daysThreshold, 30);
      expect(modified.pruneChats, true);
      expect(modified.pruneRepeaters, false);
      expect(modified.pruneRooms, true);
      expect(modified.pruneSensors, false);
    });

    test('toJson and fromJson round-trip', () {
      final config = PruneConfig(
        daysThreshold: 14,
        pruneChats: true,
        pruneRepeaters: false,
        pruneRooms: true,
        pruneSensors: false,
      );

      final json = config.toJson();
      final restored = PruneConfig.fromJson(json);

      expect(restored.daysThreshold, 14);
      expect(restored.pruneChats, true);
      expect(restored.pruneRepeaters, false);
      expect(restored.pruneRooms, true);
      expect(restored.pruneSensors, false);
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

    test('isPublic is true only for slot 0', () {
      const pub = ChannelInfo(index: 0, name: 'General');
      const priv = ChannelInfo(index: 1, name: 'Team');
      expect(pub.isPublic, true);
      expect(priv.isPublic, false);
    });

    test('isHashtag is true when name starts with #', () {
      const hash = ChannelInfo(index: 2, name: '#emergency');
      const plain = ChannelInfo(index: 3, name: 'Ops');
      expect(hash.isHashtag, true);
      expect(plain.isHashtag, false);
    });

    test('isEncrypted is false for slot 0 (public channel)', () {
      const pub = ChannelInfo(index: 0, name: 'General');
      expect(pub.isEncrypted, false);
    });

    test('isEncrypted is false for hashtag channels', () {
      const hash = ChannelInfo(index: 1, name: '#local');
      expect(hash.isEncrypted, false);
    });

    test('isEncrypted is true for named non-hashtag non-public channels', () {
      const priv = ChannelInfo(index: 2, name: 'SecretOps');
      expect(priv.isEncrypted, true);
    });
  });
}
