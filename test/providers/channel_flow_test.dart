import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lusoapp/providers/radio_providers.dart';
import 'package:lusoapp/protocol/protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // ---------------------------------------------------------------------------
  // BlockedSendersNotifier
  // ---------------------------------------------------------------------------

  group('BlockedSendersNotifier', () {
    test('starts empty', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(blockedSendersProvider), isEmpty);
    });

    test('block adds a name and isBlocked returns true', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(blockedSendersProvider.notifier).block('Alice');

      expect(container.read(blockedSendersProvider).contains('Alice'), isTrue);
      expect(
        container.read(blockedSendersProvider.notifier).isBlocked('Alice'),
        isTrue,
      );
    });

    test('unblock removes the name', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(blockedSendersProvider.notifier).block('Bob');
      await container.read(blockedSendersProvider.notifier).unblock('Bob');

      expect(container.read(blockedSendersProvider).contains('Bob'), isFalse);
    });

    test('block is idempotent — blocking twice keeps one entry', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(blockedSendersProvider.notifier).block('Carol');
      await container.read(blockedSendersProvider.notifier).block('Carol');

      expect(container.read(blockedSendersProvider).length, 1);
    });

    test('blocking empty string is a no-op', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(blockedSendersProvider.notifier).block('');

      expect(container.read(blockedSendersProvider), isEmpty);
    });

    test(
      'persists to SharedPreferences after loadForRadio round-trip',
      () async {
        SharedPreferences.setMockInitialValues({});

        final c1 = ProviderContainer();
        await c1.read(blockedSendersProvider.notifier).loadForRadio('radio-A');
        await c1.read(blockedSendersProvider.notifier).block('Dave');
        c1.dispose();

        // New container — simulates app restart.
        final c2 = ProviderContainer();
        addTearDown(c2.dispose);
        await c2.read(blockedSendersProvider.notifier).loadForRadio('radio-A');

        expect(c2.read(blockedSendersProvider).contains('Dave'), isTrue);
      },
    );

    test(
      'blocked list is per-radio — different radios have separate lists',
      () async {
        SharedPreferences.setMockInitialValues({});

        final c = ProviderContainer();
        addTearDown(c.dispose);

        await c.read(blockedSendersProvider.notifier).loadForRadio('radio-A');
        await c.read(blockedSendersProvider.notifier).block('Eve');

        // Switch to a different radio.
        await c.read(blockedSendersProvider.notifier).loadForRadio('radio-B');

        expect(c.read(blockedSendersProvider).contains('Eve'), isFalse);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // MessagesNotifier — blocked-sender dedup behaviour
  // ---------------------------------------------------------------------------

  group('MessagesNotifier blocks channel messages from blocked senders', () {
    ChatMessage channelMsg({
      required int timestamp,
      required String senderName,
      required int channelIndex,
    }) {
      return ChatMessage(
        text: 'hello',
        timestamp: timestamp,
        isOutgoing: false,
        channelIndex: channelIndex,
        senderName: senderName,
      );
    }

    test('addMessage accepts message from non-blocked sender', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container
          .read(messagesProvider.notifier)
          .addMessage(
            channelMsg(timestamp: 1, senderName: 'Alice', channelIndex: 0),
          );

      expect(container.read(messagesProvider).length, 1);
    });

    // NOTE: The blocked-sender filter runs in connection_notifier before
    // addMessage is called.  This test directly validates that the
    // blockedSendersProvider gate works as expected — if a caller checks it
    // before addMessage, the message will never reach state.
    test(
      'blockedSendersProvider gate prevents addMessage from being called',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        await container.read(blockedSendersProvider.notifier).block('Spammer');

        final msg = channelMsg(
          timestamp: 2,
          senderName: 'Spammer',
          channelIndex: 1,
        );

        // Simulate what connection_notifier does: check before calling addMessage.
        final isBlocked = container
            .read(blockedSendersProvider)
            .contains(msg.senderName ?? '');
        if (!isBlocked) {
          container.read(messagesProvider.notifier).addMessage(msg);
        }

        expect(container.read(messagesProvider), isEmpty);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // activeChannelIndexProvider
  // ---------------------------------------------------------------------------

  group('activeChannelIndexProvider', () {
    test('starts at -1 (no active channel)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(activeChannelIndexProvider), -1);
    });

    test('can be set to the open channel index', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(activeChannelIndexProvider.notifier).state = 3;

      expect(container.read(activeChannelIndexProvider), 3);
    });

    test('resets to -1 when user leaves the channel', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(activeChannelIndexProvider.notifier).state = 2;
      container.read(activeChannelIndexProvider.notifier).state = -1;

      expect(container.read(activeChannelIndexProvider), -1);
    });

    test('unread count should NOT increment for the active channel', () async {
      final container = ProviderContainer();

      // User is viewing channel 2.
      container.read(activeChannelIndexProvider.notifier).state = 2;

      // Simulate what connection_notifier does before calling incrementChannel.
      const incomingChannelIndex = 2;
      final isViewingChannel =
          container.read(activeChannelIndexProvider) == incomingChannelIndex;

      if (!isViewingChannel) {
        container
            .read(unreadCountsProvider.notifier)
            .incrementChannel(incomingChannelIndex);
      }

      expect(container.read(unreadCountsProvider).forChannel(2), 0);
      // Let the background _save complete before disposing.
      await Future<void>.delayed(Duration.zero);
      container.dispose();
    });

    test('unread count DOES increment for channels not being viewed', () async {
      final container = ProviderContainer();

      // User is viewing channel 2 — channel 5 is in background.
      container.read(activeChannelIndexProvider.notifier).state = 2;

      const incomingChannelIndex = 5;
      final isViewingChannel =
          container.read(activeChannelIndexProvider) == incomingChannelIndex;

      if (!isViewingChannel) {
        container
            .read(unreadCountsProvider.notifier)
            .incrementChannel(incomingChannelIndex);
      }

      expect(container.read(unreadCountsProvider).forChannel(5), 1);
      expect(container.read(unreadCountsProvider).forChannel(2), 0);
      // Let the background _save complete before disposing.
      await Future<void>.delayed(Duration.zero);
      container.dispose();
    });
  });
}
