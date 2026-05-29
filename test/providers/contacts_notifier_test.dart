import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lusoapp/protocol/models.dart';
import 'package:lusoapp/providers/radio_providers.dart';

void main() {
  group('ContactsNotifier.pruneStaleContacts', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('returns 0 when no contacts are stale', () {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final threeDaysAgo = now - (3 * 24 * 60 * 60);

      final contact = Contact(
        publicKey: Uint8List.fromList(List.generate(32, (i) => i)),
        type: 0x01,
        flags: 0,
        pathLen: 0,
        name: 'RecentContact',
        lastAdvertTimestamp: threeDaysAgo,
      );

      container.read(contactsProvider.notifier).state = [contact];
      final pruned =
          container.read(contactsProvider.notifier).pruneStaleContacts();

      expect(pruned, 0);
      expect(container.read(contactsProvider), [contact]);
    });

    test('uses custom daysThreshold parameter', () {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final fiveDaysAgo = now - (5 * 24 * 60 * 60);
      final tenDaysAgo = now - (10 * 24 * 60 * 60);

      final contact5Days = Contact(
        publicKey: Uint8List.fromList(List.generate(32, (i) => i)),
        type: 0x01,
        flags: 0,
        pathLen: 0,
        name: 'Contact5Days',
        lastAdvertTimestamp: fiveDaysAgo,
      );

      final contact10Days = Contact(
        publicKey: Uint8List.fromList(List.generate(32, (i) => i + 1)),
        type: 0x01,
        flags: 0,
        pathLen: 0,
        name: 'Contact10Days',
        lastAdvertTimestamp: tenDaysAgo,
      );

      container.read(contactsProvider.notifier).state = [
        contact5Days,
        contact10Days,
      ];

      // With default 7 days: only contact10Days is stale
      final pruned7 =
          container.read(contactsProvider.notifier).pruneStaleContacts();
      expect(pruned7, 1);

      // Reset state
      container.read(contactsProvider.notifier).state = [
        contact5Days,
        contact10Days,
      ];

      // With custom 3 days: both are stale
      final pruned3 = container
          .read(contactsProvider.notifier)
          .pruneStaleContacts(daysThreshold: 3);
      expect(pruned3, 2);
    });

    test('removes all stale contacts (> 7 days old)', () {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final eightDaysAgo = now - (8 * 24 * 60 * 60);
      final threeDaysAgo = now - (3 * 24 * 60 * 60);

      final staleContact = Contact(
        publicKey: Uint8List.fromList(List.generate(32, (i) => i)),
        type: 0x01,
        flags: 0,
        pathLen: 0,
        name: 'StaleContact',
        lastAdvertTimestamp: eightDaysAgo,
      );

      final recentContact = Contact(
        publicKey: Uint8List.fromList(List.generate(32, (i) => i + 1)),
        type: 0x01,
        flags: 0,
        pathLen: 0,
        name: 'RecentContact',
        lastAdvertTimestamp: threeDaysAgo,
      );

      container.read(contactsProvider.notifier).state = [
        staleContact,
        recentContact,
      ];

      final pruned =
          container.read(contactsProvider.notifier).pruneStaleContacts();

      expect(pruned, 1);
      expect(container.read(contactsProvider), [recentContact]);
    });

    test('removes multiple stale contacts, keeps recent ones', () {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final eightDaysAgo = now - (8 * 24 * 60 * 60);
      final twoDaysAgo = now - (2 * 24 * 60 * 60);

      final stale1 = Contact(
        publicKey: Uint8List.fromList(List.generate(32, (i) => i)),
        type: 0x01,
        flags: 0,
        pathLen: 0,
        name: 'StaleContact1',
        lastAdvertTimestamp: eightDaysAgo,
      );

      final stale2 = Contact(
        publicKey: Uint8List.fromList(List.generate(32, (i) => i + 1)),
        type: 0x01,
        flags: 0,
        pathLen: 0,
        name: 'StaleContact2',
        lastAdvertTimestamp: eightDaysAgo,
      );

      final recent = Contact(
        publicKey: Uint8List.fromList(List.generate(32, (i) => i + 2)),
        type: 0x01,
        flags: 0,
        pathLen: 0,
        name: 'RecentContact',
        lastAdvertTimestamp: twoDaysAgo,
      );

      container.read(contactsProvider.notifier).state = [
        stale1,
        stale2,
        recent,
      ];

      final pruned =
          container.read(contactsProvider.notifier).pruneStaleContacts();

      expect(pruned, 2);
      expect(container.read(contactsProvider), [recent]);
    });

    test('handles boundary case: exactly 7 days old is not stale', () {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final exactlySevenDays = now - (7 * 24 * 60 * 60);

      final contact = Contact(
        publicKey: Uint8List.fromList(List.generate(32, (i) => i)),
        type: 0x01,
        flags: 0,
        pathLen: 0,
        name: 'BoundaryContact',
        lastAdvertTimestamp: exactlySevenDays,
      );

      container.read(contactsProvider.notifier).state = [contact];
      final pruned =
          container.read(contactsProvider.notifier).pruneStaleContacts();

      expect(pruned, 0);
      expect(container.read(contactsProvider), [contact]);
    });

    test('returns 0 and does not modify state when list is empty', () {
      container.read(contactsProvider.notifier).state = [];
      final pruned =
          container.read(contactsProvider.notifier).pruneStaleContacts();

      expect(pruned, 0);
      expect(container.read(contactsProvider), []);
    });
  });

  group('ContactsNotifier.pruneStaleContactsWithConfig', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('prunes based on type filtering', () {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final eightDaysAgo = now - (8 * 24 * 60 * 60);

      final chat = Contact(
        publicKey: Uint8List.fromList(List.generate(32, (i) => i)),
        type: 0x01, // chat
        flags: 0,
        pathLen: 0,
        name: 'ChatContact',
        lastAdvertTimestamp: eightDaysAgo,
      );

      final repeater = Contact(
        publicKey: Uint8List.fromList(List.generate(32, (i) => i + 1)),
        type: 0x02, // repeater
        flags: 0,
        pathLen: 0,
        name: 'RepeaterContact',
        lastAdvertTimestamp: eightDaysAgo,
      );

      container.read(contactsProvider.notifier).state = [chat, repeater];

      // Prune only chats, not repeaters
      final config = PruneConfig(
        daysThreshold: 7,
        pruneChats: true,
        pruneRepeaters: false,
        pruneRooms: true,
        pruneSensors: true,
      );

      final pruned = container
          .read(contactsProvider.notifier)
          .pruneStaleContactsWithConfig(config);

      expect(pruned, 1); // Only chat was removed
      expect(container.read(contactsProvider), [repeater]);
    });

    test('prunes mixed types based on configuration', () {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final eightDaysAgo = now - (8 * 24 * 60 * 60);

      final chat = Contact(
        publicKey: Uint8List.fromList(List.generate(32, (i) => i)),
        type: 0x01,
        flags: 0,
        pathLen: 0,
        name: 'Chat',
        lastAdvertTimestamp: eightDaysAgo,
      );

      final repeater = Contact(
        publicKey: Uint8List.fromList(List.generate(32, (i) => i + 1)),
        type: 0x02,
        flags: 0,
        pathLen: 0,
        name: 'Repeater',
        lastAdvertTimestamp: eightDaysAgo,
      );

      final room = Contact(
        publicKey: Uint8List.fromList(List.generate(32, (i) => i + 2)),
        type: 0x03,
        flags: 0,
        pathLen: 0,
        name: 'Room',
        lastAdvertTimestamp: eightDaysAgo,
      );

      container.read(contactsProvider.notifier).state = [chat, repeater, room];

      // Prune chats and repeaters, not rooms
      final config = PruneConfig(
        daysThreshold: 7,
        pruneChats: true,
        pruneRepeaters: true,
        pruneRooms: false,
        pruneSensors: false,
      );

      final pruned = container
          .read(contactsProvider.notifier)
          .pruneStaleContactsWithConfig(config);

      expect(pruned, 2); // Chat and repeater removed
      expect(container.read(contactsProvider), [room]);
    });

    test('respects custom days threshold in config', () {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final fiveDaysAgo = now - (5 * 24 * 60 * 60);
      final tenDaysAgo = now - (10 * 24 * 60 * 60);

      final contact5Days = Contact(
        publicKey: Uint8List.fromList(List.generate(32, (i) => i)),
        type: 0x01,
        flags: 0,
        pathLen: 0,
        name: 'Contact5Days',
        lastAdvertTimestamp: fiveDaysAgo,
      );

      final contact10Days = Contact(
        publicKey: Uint8List.fromList(List.generate(32, (i) => i + 1)),
        type: 0x01,
        flags: 0,
        pathLen: 0,
        name: 'Contact10Days',
        lastAdvertTimestamp: tenDaysAgo,
      );

      container.read(contactsProvider.notifier).state = [
        contact5Days,
        contact10Days,
      ];

      // Prune only contacts > 3 days old
      final config = PruneConfig(
        daysThreshold: 3,
        pruneChats: true,
        pruneRepeaters: true,
        pruneRooms: true,
        pruneSensors: true,
      );

      final pruned = container
          .read(contactsProvider.notifier)
          .pruneStaleContactsWithConfig(config);

      expect(pruned, 2); // Both older than 3 days
      expect(container.read(contactsProvider), []);
    });

    test('returns 0 when no contacts match config', () {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final eightDaysAgo = now - (8 * 24 * 60 * 60);

      final repeater = Contact(
        publicKey: Uint8List.fromList(List.generate(32, (i) => i)),
        type: 0x02,
        flags: 0,
        pathLen: 0,
        name: 'Repeater',
        lastAdvertTimestamp: eightDaysAgo,
      );

      container.read(contactsProvider.notifier).state = [repeater];

      // Don't prune any type
      final config = PruneConfig(
        daysThreshold: 7,
        pruneChats: false,
        pruneRepeaters: false,
        pruneRooms: false,
        pruneSensors: false,
      );

      final pruned = container
          .read(contactsProvider.notifier)
          .pruneStaleContactsWithConfig(config);

      expect(pruned, 0);
      expect(container.read(contactsProvider), [repeater]);
    });
  });

  group('ContactsNotifier.pruneStaleContacts (legacy)', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test(
      'prunes all types regardless of configuration (backward compatible)',
      () {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final eightDaysAgo = now - (8 * 24 * 60 * 60);

        final chat = Contact(
          publicKey: Uint8List.fromList(List.generate(32, (i) => i)),
          type: 0x01,
          flags: 0,
          pathLen: 0,
          name: 'Chat',
          lastAdvertTimestamp: eightDaysAgo,
        );

        final repeater = Contact(
          publicKey: Uint8List.fromList(List.generate(32, (i) => i + 1)),
          type: 0x02,
          flags: 0,
          pathLen: 0,
          name: 'Repeater',
          lastAdvertTimestamp: eightDaysAgo,
        );

        container.read(contactsProvider.notifier).state = [chat, repeater];

        // Legacy method: prune all types
        final pruned = container
            .read(contactsProvider.notifier)
            .pruneStaleContacts(daysThreshold: 7);

        expect(pruned, 2); // Both types pruned
        expect(container.read(contactsProvider), []);
      },
    );
  });
}
