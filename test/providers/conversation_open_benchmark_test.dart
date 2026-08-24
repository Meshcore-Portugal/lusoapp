import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lusoapp/providers/radio_providers.dart';
import 'package:lusoapp/protocol/protocol.dart';
import 'package:lusoapp/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_db.dart';

/// Measures how long opening a conversation takes with a realistic history.
///
/// Opening a channel calls `ensureLoadedForChannel` → `_mergeStored`. The cost
/// that matters is whether that work is proportional to the conversation being
/// opened or to every message in the app.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    useInMemoryDatabase();
  });

  // A busy install: several channels plus private conversations, each with a
  // long history and realistic message lengths.
  const channels = 6;
  const contacts = 6;
  const perConversation = 900;

  ChatMessage channelMsg(int ch, int i) => ChatMessage(
    text:
        'Mensagem $i no canal $ch — texto de comprimento realista para que o '
        'custo de hashing e concatenacao seja representativo do uso real.',
    timestamp: 1700000000 + i,
    isOutgoing: i % 7 == 0,
    channelIndex: ch,
    senderName: 'Estacao$ch',
    snr: -6.5,
    pathLen: 2,
  );

  ChatMessage privateMsg(int c, int i) => ChatMessage(
    text:
        'Mensagem privada $i do contacto $c — texto de comprimento realista '
        'para representar o custo real de deduplicacao.',
    timestamp: 1700000000 + i,
    isOutgoing: i % 5 == 0,
    senderKey: Uint8List.fromList([c, c, c, c, c, c, 0, 0]),
    senderName: 'Contacto$c',
  );

  Future<void> seed() async {
    for (var ch = 0; ch < channels; ch++) {
      await StorageService.instance.saveMessages('ch_$ch', [
        for (var i = 0; i < perConversation; i++) channelMsg(ch, i),
      ]);
    }
    for (var c = 0; c < contacts; c++) {
      final hex6 =
          List.filled(
            6,
            c,
          ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      await StorageService.instance.saveMessages('contact_$hex6', [
        for (var i = 0; i < perConversation; i++) privateMsg(c, i),
      ]);
    }
  }

  test('opening every conversation stays responsive', () async {
    await seed();

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(messagesProvider.notifier);

    final totalStopwatch = Stopwatch()..start();
    var worstMs = 0;
    String worstLabel = '';

    for (var ch = 0; ch < channels; ch++) {
      final sw = Stopwatch()..start();
      await notifier.ensureLoadedForChannel(ch);
      sw.stop();
      // ignore: avoid_print
      print(
        '  open channel $ch  (loaded so far: '
        '${container.read(messagesProvider).length})  '
        '${sw.elapsedMicroseconds / 1000}ms',
      );
      if (sw.elapsedMilliseconds > worstMs) {
        worstMs = sw.elapsedMilliseconds;
        worstLabel = 'channel $ch';
      }
    }
    for (var c = 0; c < contacts; c++) {
      final hex6 =
          List.filled(
            6,
            c,
          ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final sw = Stopwatch()..start();
      await notifier.ensureLoadedForContact(hex6);
      sw.stop();
      // ignore: avoid_print
      print(
        '  open contact $c  (loaded so far: '
        '${container.read(messagesProvider).length})  '
        '${sw.elapsedMicroseconds / 1000}ms',
      );
      if (sw.elapsedMilliseconds > worstMs) {
        worstMs = sw.elapsedMilliseconds;
        worstLabel = 'contact $c';
      }
    }
    totalStopwatch.stop();

    final total = container.read(messagesProvider).length;
    // ignore: avoid_print
    print(
      'OPEN-BENCH  messages=$total  '
      'total=${totalStopwatch.elapsedMilliseconds}ms  '
      'worst-single-open=${worstMs}ms ($worstLabel)',
    );

    expect(total, (channels + contacts) * perConversation);
    // The last conversation opened must not cost dramatically more than the
    // first: that is the signature of work scaling with the whole app rather
    // than with the conversation.
    expect(
      worstMs,
      lessThan(400),
      reason: 'opening one conversation should not take hundreds of ms',
    );
  });
}
