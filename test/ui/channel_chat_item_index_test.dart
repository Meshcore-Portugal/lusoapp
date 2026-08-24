import 'package:flutter_test/flutter_test.dart';
import 'package:lusoapp/ui/screens/channel_chat_screen.dart';

/// The chat lists are reversed so that scrolling to the newest message is a
/// jump to offset 0 rather than to a lazily-estimated `maxScrollExtent`. That
/// inverts the item index, and the optional unread divider shifts everything
/// after it — this pins the arithmetic.
void main() {
  /// Renders the whole list top-to-bottom the way the reversed ListView does,
  /// using '---' for the divider slot.
  List<String> render({required int messageCount, required int firstUnread}) {
    final itemCount = messageCount + (firstUnread >= 0 ? 1 : 0);
    return [
      // A reversed list draws index 0 at the bottom, so to read the list
      // top-to-bottom we walk the indices backwards.
      for (var i = itemCount - 1; i >= 0; i--)
        switch (channelChatItemIndex(
          reversedIndex: i,
          messageCount: messageCount,
          firstUnreadIndex: firstUnread,
        )) {
          null => '---',
          final int m => 'm$m',
        },
    ];
  }

  group('without an unread divider', () {
    test('renders oldest at the top, newest at the bottom', () {
      expect(render(messageCount: 4, firstUnread: -1), [
        'm0',
        'm1',
        'm2',
        'm3',
      ]);
    });

    test('index 0 of the reversed list is the newest message', () {
      expect(
        channelChatItemIndex(
          reversedIndex: 0,
          messageCount: 10,
          firstUnreadIndex: -1,
        ),
        9,
      );
    });

    test('every message is rendered exactly once', () {
      const count = 50;
      final rendered = render(messageCount: count, firstUnread: -1);
      expect(rendered, hasLength(count));
      expect(rendered.toSet(), hasLength(count));
    });

    test('handles a single message and an empty list', () {
      expect(render(messageCount: 1, firstUnread: -1), ['m0']);
      expect(render(messageCount: 0, firstUnread: -1), isEmpty);
    });
  });

  group('with an unread divider', () {
    test('divider sits directly above the first unread message', () {
      // 5 messages, unread starts at message index 3.
      expect(render(messageCount: 5, firstUnread: 3), [
        'm0',
        'm1',
        'm2',
        '---',
        'm3',
        'm4',
      ]);
    });

    test('divider at the very top means everything is unread', () {
      expect(render(messageCount: 3, firstUnread: 0), [
        '---',
        'm0',
        'm1',
        'm2',
      ]);
    });

    test('divider just above the newest message', () {
      expect(render(messageCount: 3, firstUnread: 2), [
        'm0',
        'm1',
        '---',
        'm2',
      ]);
    });

    test('no message is dropped or duplicated by the divider shift', () {
      const count = 40;
      for (var unread = 0; unread < count; unread++) {
        final rendered = render(messageCount: count, firstUnread: unread);
        expect(rendered, hasLength(count + 1), reason: 'unread=$unread');
        expect(rendered.where((e) => e == '---'), hasLength(1));
        final messages = rendered.where((e) => e != '---').toList();
        expect(messages, [
          for (var i = 0; i < count; i++) 'm$i',
        ], reason: 'order must stay oldest-first for unread=$unread');
      }
    });
  });
}
