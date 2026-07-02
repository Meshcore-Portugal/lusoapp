import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lusoapp/providers/canned_messages_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _waitForInitialLoad(ProviderContainer container) async {
  for (var i = 0; i < 60; i++) {
    if (container.read(cannedMessagesProvider).isNotEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for canned messages to load.');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('CannedMessagesNotifier persistence', () {
    test('seeds defaults and persists them on first launch', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await _waitForInitialLoad(container);
      final state = container.read(cannedMessagesProvider);

      expect(state, isNotEmpty);
      expect(state.any((m) => m.id == 'sos' && m.isEmergency), isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('canned_messages_v1'), isNotNull);
    });

    test('loads persisted v1 messages after restart', () async {
      final first = ProviderContainer();
      addTearDown(first.dispose);
      await _waitForInitialLoad(first);

      await first
          .read(cannedMessagesProvider.notifier)
          .add(text: 'Persist me', label: 'PM');

      final beforeRestart = first.read(cannedMessagesProvider);
      expect(beforeRestart.any((m) => m.text == 'Persist me'), isTrue);

      final second = ProviderContainer();
      addTearDown(second.dispose);
      await _waitForInitialLoad(second);

      final afterRestart = second.read(cannedMessagesProvider);
      expect(afterRestart.any((m) => m.text == 'Persist me'), isTrue);
    });

    test('migrates legacy key to v1 and keeps data', () async {
      final legacyPayload = jsonEncode([
        {
          'id': 'legacy_1',
          'text': 'Legacy message',
          'label': 'Legacy',
          'isEmergency': false,
        },
      ]);

      SharedPreferences.setMockInitialValues({
        'canned_messages': legacyPayload,
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await _waitForInitialLoad(container);
      final state = container.read(cannedMessagesProvider);

      expect(state.length, 1);
      expect(state.single.id, 'legacy_1');
      expect(state.single.text, 'Legacy message');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('canned_messages_v1'), legacyPayload);
      expect(prefs.getString('canned_messages'), isNull);
    });

    test('recovers to defaults when stored payload is invalid JSON', () async {
      SharedPreferences.setMockInitialValues({
        'canned_messages_v1': '{not-json}',
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await _waitForInitialLoad(container);
      final state = container.read(cannedMessagesProvider);

      expect(state, isNotEmpty);
      expect(state.any((m) => m.id == 'sos' && m.isEmergency), isTrue);

      final prefs = await SharedPreferences.getInstance();
      final repaired = prefs.getString('canned_messages_v1');
      expect(repaired, isNotNull);
      expect(() => jsonDecode(repaired!), returnsNormally);
    });
  });
}
