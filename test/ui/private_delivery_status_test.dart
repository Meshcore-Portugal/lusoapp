import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lusoapp/protocol/protocol.dart';
import 'package:lusoapp/ui/screens/private_chat_screen.dart';

void main() {
  ChatMessage outgoing({
    int retryCount = 0,
    bool confirmed = false,
    bool failed = false,
  }) {
    return ChatMessage(
      text: 'hello',
      timestamp: 1,
      isOutgoing: true,
      senderKey: Uint8List.fromList([1, 2, 3, 4, 5, 6]),
      confirmed: confirmed,
      failed: failed,
      retryCount: retryCount,
    );
  }

  String statusFor(ChatMessage message) {
    return formatPrivateDeliveryStatus(
      message,
      pendingLabel: 'Pending',
      confirmedLabel: 'Confirmed',
      failedLabel: 'Failed',
      retryLabel: 'Retry',
      floodLabel: 'Flood',
    );
  }

  group('formatPrivateDeliveryStatus', () {
    test('returns pending for initial send', () {
      expect(statusFor(outgoing()), 'Pending');
    });

    test('returns retry attempt with flood suffix after retry begins', () {
      expect(statusFor(outgoing(retryCount: 1)), 'Retry 2/4 • Flood');
    });

    test('returns confirmed when delivered', () {
      expect(statusFor(outgoing(confirmed: true)), 'Confirmed');
    });

    test('returns failed summary with attempt count', () {
      expect(
        statusFor(outgoing(retryCount: 3, failed: true)),
        'Failed • Retry 4/4 • Flood',
      );
    });
  });
}
