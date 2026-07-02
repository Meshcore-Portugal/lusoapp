import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
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

  ChatMessage privateOutgoing(int timestamp, List<int> senderKey, String text) {
    return ChatMessage(
      text: text,
      timestamp: timestamp,
      isOutgoing: true,
      senderKey: Uint8List.fromList(senderKey),
    );
  }

  group('MessagesNotifier private message ACK handling', () {
    test('confirmLastOutgoing matches private messages in FIFO order', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(messagesProvider.notifier);

      notifier.addOutgoing(privateOutgoing(101, [1, 2, 3, 4, 5, 6], 'first'));
      notifier.addOutgoing(privateOutgoing(102, [1, 2, 3, 4, 5, 6], 'second'));

      notifier.markLastOutgoingRoute(
        0,
        expectedAck: 0x11111111,
        suggestedTimeoutMs: 5000,
      );
      notifier.markLastOutgoingRoute(
        1,
        expectedAck: 0x22222222,
        suggestedTimeoutMs: 5000,
      );

      notifier.confirmLastOutgoing();

      var messages = container.read(messagesProvider);
      expect(messages[0].confirmed, isTrue);
      expect(messages[1].confirmed, isFalse);

      notifier.confirmLastOutgoing();

      messages = container.read(messagesProvider);
      expect(messages[1].confirmed, isTrue);
    });

    test(
      'markLastOutgoingRoute confirms immediately when no ACK is expected',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final notifier = container.read(messagesProvider.notifier);
        notifier.addOutgoing(
          privateOutgoing(201, [7, 8, 9, 10, 11, 12], 'cli'),
        );

        notifier.markLastOutgoingRoute(
          0,
          expectedAck: 0,
          suggestedTimeoutMs: 0,
        );

        final message = container.read(messagesProvider).single;
        expect(message.confirmed, isTrue);
        expect(message.failed, isFalse);
      },
    );

    test(
      'ack timeout marks message failed when no radio service is available',
      () {
        fakeAsync((async) {
          final container = ProviderContainer();
          addTearDown(container.dispose);

          final notifier = container.read(messagesProvider.notifier);
          notifier.addOutgoing(
            privateOutgoing(301, [13, 14, 15, 16, 17, 18], 'timeout'),
          );

          notifier.markLastOutgoingRoute(
            0,
            expectedAck: 0xCAFEBABE,
            suggestedTimeoutMs: 1,
          );

          async.elapse(const Duration(seconds: 2));
          async.flushMicrotasks();

          final message = container.read(messagesProvider).single;
          expect(message.failed, isTrue);
          expect(message.confirmed, isFalse);
        });
      },
    );
  });
}
