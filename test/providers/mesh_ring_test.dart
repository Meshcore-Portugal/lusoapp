import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lusoapp/providers/radio_providers.dart';
import 'package:lusoapp/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../support/test_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    useInMemoryDatabase();
    SharedPreferences.setMockInitialValues({});
  });

  // ---------------------------------------------------------------------------
  // PriorityContactsNotifier
  // ---------------------------------------------------------------------------

  group('PriorityContactsNotifier', () {
    test('starts empty', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(priorityContactsProvider), isEmpty);
    });

    test('toggle marks a contact priority, toggle again unmarks it', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container
          .read(priorityContactsProvider.notifier)
          .loadForRadio('radio-A');
      await container.read(priorityContactsProvider.notifier).toggle('aabbcc');

      expect(
        container.read(priorityContactsProvider.notifier).isPriority('aabbcc'),
        isTrue,
      );

      await container.read(priorityContactsProvider.notifier).toggle('aabbcc');

      expect(
        container.read(priorityContactsProvider.notifier).isPriority('aabbcc'),
        isFalse,
      );
    });

    test(
      'persists to SharedPreferences after loadForRadio round-trip',
      () async {
        final c1 = ProviderContainer();
        await c1
            .read(priorityContactsProvider.notifier)
            .loadForRadio('radio-A');
        await c1.read(priorityContactsProvider.notifier).toggle('ddeeff');
        c1.dispose();

        // New container — simulates app restart.
        final c2 = ProviderContainer();
        addTearDown(c2.dispose);
        await c2
            .read(priorityContactsProvider.notifier)
            .loadForRadio('radio-A');

        expect(c2.read(priorityContactsProvider).contains('ddeeff'), isTrue);
      },
    );

    test('priority list is per-radio — different radios have separate lists', (
      () async {
        final c = ProviderContainer();
        addTearDown(c.dispose);

        await c.read(priorityContactsProvider.notifier).loadForRadio('radio-A');
        await c.read(priorityContactsProvider.notifier).toggle('112233');

        // Switch to a different radio.
        await c.read(priorityContactsProvider.notifier).loadForRadio('radio-B');

        expect(c.read(priorityContactsProvider).contains('112233'), isFalse);
      }),
    );
  });

  // ---------------------------------------------------------------------------
  // MeshRingCooldownNotifier
  // ---------------------------------------------------------------------------

  group('MeshRingCooldownNotifier', () {
    test('lastRingEpochFor returns null before any ring', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container
            .read(meshRingCooldownProvider.notifier)
            .lastRingEpochFor('aabbcc'),
        isNull,
      );
    });

    test('markRung records an epoch retrievable via lastRingEpochFor', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final before = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await container.read(meshRingCooldownProvider.notifier).markRung(
        'aabbcc',
      );
      final after = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      final recorded = container
          .read(meshRingCooldownProvider.notifier)
          .lastRingEpochFor('aabbcc');
      expect(recorded, isNotNull);
      expect(recorded! >= before && recorded <= after, isTrue);
    });

    test('persists across restart via loadFromStorage', () async {
      final c1 = ProviderContainer();
      await c1.read(meshRingCooldownProvider.notifier).markRung('ddeeff');
      c1.dispose();

      final c2 = ProviderContainer();
      addTearDown(c2.dispose);
      await c2.read(meshRingCooldownProvider.notifier).loadFromStorage();

      expect(
        c2.read(meshRingCooldownProvider.notifier).lastRingEpochFor('ddeeff'),
        isNotNull,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // MeshRingSettings model
  // ---------------------------------------------------------------------------

  group('MeshRingSettings', () {
    test('defaults to disabled with a 5 minute interval', () {
      const settings = MeshRingSettings();
      expect(settings.enabled, isFalse);
      expect(settings.minIntervalMinutes, 5);
    });

    test('toJson/fromJson round-trips', () {
      const settings = MeshRingSettings(enabled: true, minIntervalMinutes: 15);
      final restored = MeshRingSettings.fromJson(settings.toJson());
      expect(restored.enabled, isTrue);
      expect(restored.minIntervalMinutes, 15);
    });

    test('save/load round-trips through StorageService', () async {
      const settings = MeshRingSettings(enabled: true, minIntervalMinutes: 10);
      await StorageService.instance.saveMeshRingSettings(settings);
      final loaded = await StorageService.instance.loadMeshRingSettings();
      expect(loaded.enabled, isTrue);
      expect(loaded.minIntervalMinutes, 10);
    });
  });

  // ---------------------------------------------------------------------------
  // meshRingShouldRing — the three MeshRing behaviors from issue #58
  // ---------------------------------------------------------------------------

  group('meshRingShouldRing', () {
    test('rings on the first unread message from the contact', () {
      final result = meshRingShouldRing(
        isCallMessage: false,
        hadUnreadBefore: false,
        lastRingEpoch: null,
        nowEpoch: 1000,
        minIntervalMinutes: 5,
      );
      expect(result, isTrue);
    });

    test(
      'does not ring again for a normal message while already unread and '
      'within the cooldown',
      () {
        final result = meshRingShouldRing(
          isCallMessage: false,
          hadUnreadBefore: true,
          lastRingEpoch: 1000,
          nowEpoch: 1100, // 100s later, cooldown is 5 min (300s)
          minIntervalMinutes: 5,
        );
        expect(result, isFalse);
      },
    );

    test('rings again for a normal message once the cooldown has elapsed', () {
      final result = meshRingShouldRing(
        isCallMessage: false,
        hadUnreadBefore: true,
        lastRingEpoch: 1000,
        nowEpoch: 1000 + 301, // just past 5 minutes
        minIntervalMinutes: 5,
      );
      expect(result, isTrue);
    });

    test(
      'a call message forces a ring even with unread messages already '
      'pending, once the cooldown has elapsed',
      () {
        final result = meshRingShouldRing(
          isCallMessage: true,
          hadUnreadBefore: true,
          lastRingEpoch: 1000,
          nowEpoch: 1000 + 301,
          minIntervalMinutes: 5,
        );
        expect(result, isTrue);
      },
    );

    test('a call message still respects the cooldown — no spamming', () {
      final result = meshRingShouldRing(
        isCallMessage: true,
        hadUnreadBefore: true,
        lastRingEpoch: 1000,
        nowEpoch: 1100,
        minIntervalMinutes: 5,
      );
      expect(result, isFalse);
    });

    test('a never-rung contact (null epoch) is always past its cooldown', () {
      final result = meshRingShouldRing(
        isCallMessage: true,
        hadUnreadBefore: true,
        lastRingEpoch: null,
        nowEpoch: 1000,
        minIntervalMinutes: 5,
      );
      expect(result, isTrue);
    });
  });
}
