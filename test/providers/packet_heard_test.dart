import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lusoapp/providers/radio_providers.dart';
import 'package:lusoapp/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_db.dart';

/// PacketHeardNotifier.record runs for every packet heard on the mesh. It used
/// to re-encode its whole map and rewrite the preferences file on each call,
/// and the map grew without bound. These tests pin the in-memory cap and the
/// debounced retention pass.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    useInMemoryDatabase();
  });

  void recordOne(PacketHeardNotifier n, String hash) {
    n.record(
      hash,
      snr: 5.5,
      rssi: -80,
      pathBytes: Uint8List.fromList([0xAB]),
      pathHashCount: 1,
      pathHashSize: 1,
    );
  }

  test('retains only the most recent hashes in memory once capped', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(packetHeardProvider.notifier);

    const overflow = 5;
    for (var i = 0; i < PacketHeardNotifier.maxHashes + overflow; i++) {
      recordOne(notifier, 'hash$i');
    }

    final state = container.read(packetHeardProvider);
    expect(state.length, PacketHeardNotifier.maxHashes);
    // The oldest-inserted hashes are the ones evicted.
    expect(state.containsKey('hash0'), isFalse);
    expect(state.containsKey('hash${overflow - 1}'), isFalse);
    expect(state.containsKey('hash$overflow'), isTrue);
    expect(
      state.containsKey('hash${PacketHeardNotifier.maxHashes + overflow - 1}'),
      isTrue,
    );
  });

  test('repeated receptions of one hash accumulate as separate paths', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(packetHeardProvider.notifier);

    recordOne(notifier, 'same');
    recordOne(notifier, 'same');
    final count = notifier.record(
      'same',
      snr: 1,
      rssi: -90,
      pathBytes: Uint8List(0),
      pathHashCount: 0,
      pathHashSize: 1,
    );

    expect(count, 3);
    expect(container.read(packetHeardProvider)['same']!.length, 3);
  });

  test('each reception is appended to the database', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(packetHeardProvider.notifier);

    recordOne(notifier, 'a');
    recordOne(notifier, 'a');
    recordOne(notifier, 'b');
    // Appends are fire-and-forget; let them settle.
    await Future<void>.delayed(Duration.zero);

    final stored = await StorageService.instance.loadMessagePaths();
    expect(stored['a'], hasLength(2));
    expect(stored['b'], hasLength(1));
    expect(stored['a']!.first.snr, 5.5);
    expect(stored['a']!.first.rssi, -80);
  });

  test('the retention pass is debounced, not run per packet', () {
    fakeAsync((async) {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(packetHeardProvider.notifier);

      recordOne(notifier, 'first');
      // A burst inside the window must not re-arm the timer repeatedly.
      for (var i = 0; i < 50; i++) {
        recordOne(notifier, 'burst$i');
      }
      async.flushMicrotasks();
      expect(
        async.pendingTimers,
        hasLength(1),
        reason: 'one pending prune for the whole burst',
      );

      async.elapse(const Duration(seconds: 6));
      async.flushMicrotasks();
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('reset reloads persisted paths', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(packetHeardProvider.notifier);

    recordOne(notifier, 'kept');
    await Future<void>.delayed(Duration.zero);

    notifier.reset();
    expect(container.read(packetHeardProvider), isEmpty);

    // reset() reloads from storage on a microtask.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(packetHeardProvider).containsKey('kept'), isTrue);
  });
}
