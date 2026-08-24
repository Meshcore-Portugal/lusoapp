import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lusoapp/providers/radio_providers.dart';
import 'package:lusoapp/protocol/protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../support/test_db.dart';

/// Covers the incremental bookkeeping that replaced the full rescans in
/// MessagesNotifier: per-message partition appends and the contact →
/// last-message-timestamp map. Both used to be recomputed from the whole
/// message list on every state change.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    useInMemoryDatabase();
    SharedPreferences.setMockInitialValues({});
  });

  final alice = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
  final bob = Uint8List.fromList([9, 10, 11, 12, 13, 14, 15, 16]);

  String hex6(Uint8List k) =>
      k.take(6).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  ChatMessage incoming(int ts, Uint8List sender, String text) => ChatMessage(
    text: text,
    timestamp: ts,
    isOutgoing: false,
    senderKey: sender,
  );

  ChatMessage channelMsg(int ts, int channel, String text) => ChatMessage(
    text: text,
    timestamp: ts,
    isOutgoing: false,
    channelIndex: channel,
  );

  group('partition bookkeeping', () {
    test('appends land in the right bucket, in arrival order', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(messagesProvider.notifier);

      notifier.addMessage(incoming(100, alice, 'a1'));
      notifier.addMessage(incoming(101, bob, 'b1'));
      notifier.addMessage(incoming(102, alice, 'a2'));
      notifier.addMessage(channelMsg(103, 0, 'c1'));

      expect(notifier.forContact(alice).map((m) => m.text).toList(), [
        'a1',
        'a2',
      ]);
      expect(notifier.forContact(bob).map((m) => m.text).toList(), ['b1']);
      expect(notifier.forChannel(0).map((m) => m.text).toList(), ['c1']);
      expect(container.read(messagesProvider).length, 4);
    });

    test('incremental append matches a full rebuild', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(messagesProvider.notifier);

      for (var i = 0; i < 20; i++) {
        notifier.addMessage(incoming(200 + i, i.isEven ? alice : bob, 'm$i'));
      }

      // Derive the expected buckets independently from the flat state list.
      final all = container.read(messagesProvider);
      final expectedAlice =
          all
              .where(
                (m) => m.senderKey != null && hex6(m.senderKey!) == hex6(alice),
              )
              .map((m) => m.text)
              .toList();

      expect(
        notifier.forContact(alice).map((m) => m.text).toList(),
        expectedAlice,
      );
      expect(notifier.forContact(alice).length, 10);
      expect(notifier.forContact(bob).length, 10);
    });

    test('dedup still rejects an identical message', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(messagesProvider.notifier);

      notifier.addMessage(incoming(300, alice, 'dup'));
      notifier.addMessage(incoming(300, alice, 'dup'));

      expect(notifier.forContact(alice).length, 1);
      expect(container.read(messagesProvider).length, 1);
    });
  });

  group('contactLastMsgTsProvider', () {
    test('tracks the newest private message per contact', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(messagesProvider.notifier);

      notifier.addMessage(incoming(500, alice, 'first'));
      notifier.addMessage(incoming(700, alice, 'newest'));
      notifier.addMessage(incoming(600, alice, 'out of order'));
      notifier.addMessage(incoming(650, bob, 'bob'));

      final map = container.read(contactLastMsgTsProvider);
      expect(map[hex6(alice)], 700, reason: 'must keep the max, not the last');
      expect(map[hex6(bob)], 650);
    });

    test('ignores channel messages', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(messagesProvider.notifier);

      notifier.addMessage(channelMsg(900, 2, 'channel traffic'));

      expect(container.read(contactLastMsgTsProvider), isEmpty);
    });

    test('recomputes after the newest message is deleted', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(messagesProvider.notifier);

      notifier.addMessage(incoming(1000, alice, 'older'));
      final newest = incoming(2000, alice, 'newest');
      notifier.addMessage(newest);
      expect(container.read(contactLastMsgTsProvider)[hex6(alice)], 2000);

      notifier.deleteMessage(newest);

      expect(
        container.read(contactLastMsgTsProvider)[hex6(alice)],
        1000,
        reason: 'deleting the newest must fall back to the previous message',
      );
    });
  });
}
