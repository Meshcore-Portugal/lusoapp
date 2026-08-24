import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lusoapp/protocol/protocol.dart';
import 'package:lusoapp/services/db/app_database.dart';
import 'package:lusoapp/services/db/stores.dart';

/// Exercises the drift schema against a real in-memory SQLite database:
/// row/model round-tripping, the upsert that replaced whole-conversation
/// rewrites, and the retention queries.
void main() {
  late AppDatabase db;
  late MessageStore messages;
  late ContactStore contacts;
  late PacketPathStore paths;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    messages = MessageStore(db);
    contacts = ContactStore(db);
    paths = PacketPathStore(db);
  });

  tearDown(() async => db.close());

  final alice = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);

  ChatMessage msg(
    int ts,
    String text, {
    bool outgoing = false,
    bool confirmed = false,
    int retryCount = 0,
    bool cli = false,
  }) => ChatMessage(
    text: text,
    timestamp: ts,
    isOutgoing: outgoing,
    senderKey: alice,
    senderName: 'Alice',
    confirmed: confirmed,
    snr: -7.25,
    pathLen: 3,
    retryCount: retryCount,
    isCliResponse: cli,
  );

  group('messages', () {
    test('round-trips every field', () async {
      await messages.upsert('contact_aabb', msg(100, 'hello', cli: true));

      final loaded = await messages.load('contact_aabb', limit: 100);
      expect(loaded, hasLength(1));
      final m = loaded.single;
      expect(m.text, 'hello');
      expect(m.timestamp, 100);
      expect(m.isOutgoing, isFalse);
      expect(m.senderKey, alice);
      expect(m.senderName, 'Alice');
      expect(m.snr, -7.25);
      expect(m.pathLen, 3);
      expect(
        m.isCliResponse,
        isTrue,
        reason: 'isCliResponse was lost by the old JSON representation',
      );
    });

    test('upsert updates status in place instead of duplicating', () async {
      await messages.upsert('c1', msg(200, 'ping', outgoing: true));
      await messages.upsert(
        'c1',
        msg(200, 'ping', outgoing: true, confirmed: true, retryCount: 2),
      );

      final loaded = await messages.load('c1', limit: 100);
      expect(loaded, hasLength(1), reason: 'same identity must not duplicate');
      expect(loaded.single.confirmed, isTrue);
      expect(loaded.single.retryCount, 2);
    });

    test(
      'same timestamp with different text stays a separate message',
      () async {
        await messages.upsert('c1', msg(300, 'first'));
        await messages.upsert('c1', msg(300, 'second'));
        expect(await messages.load('c1', limit: 100), hasLength(2));
      },
    );

    test('conversations are isolated', () async {
      await messages.upsert('c1', msg(400, 'in c1'));
      await messages.upsert('c2', msg(400, 'in c2'));

      expect((await messages.load('c1', limit: 10)).single.text, 'in c1');
      expect((await messages.load('c2', limit: 10)).single.text, 'in c2');
    });

    test('load returns the newest N, oldest first', () async {
      for (var i = 0; i < 10; i++) {
        await messages.upsert('c1', msg(500 + i, 'm$i'));
      }

      final loaded = await messages.load('c1', limit: 3);
      expect(loaded.map((m) => m.text).toList(), ['m7', 'm8', 'm9']);
    });

    test('prune keeps the newest rows only', () async {
      for (var i = 0; i < 10; i++) {
        await messages.upsert('c1', msg(600 + i, 'm$i'));
      }
      await messages.prune('c1', keep: 4);

      final loaded = await messages.load('c1', limit: 100);
      expect(loaded.map((m) => m.text).toList(), ['m6', 'm7', 'm8', 'm9']);
    });

    test('prune leaves other conversations untouched', () async {
      for (var i = 0; i < 5; i++) {
        await messages.upsert('c1', msg(700 + i, 'a$i'));
        await messages.upsert('c2', msg(700 + i, 'b$i'));
      }
      await messages.prune('c1', keep: 2);

      expect(await messages.load('c1', limit: 100), hasLength(2));
      expect(await messages.load('c2', limit: 100), hasLength(5));
    });

    test('replaceAll swaps the conversation contents', () async {
      await messages.upsert('c1', msg(800, 'old'));
      await messages.replaceAll('c1', [msg(900, 'new a'), msg(901, 'new b')]);

      final loaded = await messages.load('c1', limit: 100);
      expect(loaded.map((m) => m.text).toList(), ['new a', 'new b']);
    });

    test('clear removes only the named conversation', () async {
      await messages.upsert('c1', msg(1000, 'x'));
      await messages.upsert('c2', msg(1000, 'y'));
      await messages.clear('c1');

      expect(await messages.load('c1', limit: 10), isEmpty);
      expect(await messages.load('c2', limit: 10), hasLength(1));
    });
  });

  group('contacts', () {
    Contact contact(List<int> key, String name) => Contact(
      publicKey: Uint8List.fromList(key),
      type: 1,
      flags: 3,
      pathLen: 2,
      name: name,
      lastAdvertTimestamp: 12345,
      latitude: 38.7,
      longitude: -9.1,
      lastModified: 999,
      customName: 'custom-$name',
    );

    test('round-trips and replaces wholesale', () async {
      await contacts.replaceAll([
        contact([1], 'a'),
        contact([2], 'b'),
      ]);
      expect(await contacts.count(), 2);

      final loaded = await contacts.loadAll();
      final a = loaded.firstWhere((c) => c.name == 'a');
      expect(a.latitude, 38.7);
      expect(a.longitude, -9.1);
      expect(a.customName, 'custom-a');
      expect(a.flags, 3);

      await contacts.replaceAll([
        contact([3], 'c'),
      ]);
      final after = await contacts.loadAll();
      expect(after.map((c) => c.name).toList(), ['c']);
    });

    test('duplicate public keys collapse to one row', () async {
      await contacts.replaceAll([
        contact([9], 'first'),
        contact([9], 'second'),
      ]);
      expect(await contacts.count(), 1);
    });
  });

  group('packet paths', () {
    MessagePath path(double snr) => MessagePath(
      snr: snr,
      rssi: -90,
      pathHashCount: 2,
      pathHashSize: 1,
      pathBytes: Uint8List.fromList([0xAA, 0xBB]),
    );

    test('appends accumulate per hash and round-trip', () async {
      await paths.append('hashA', path(1));
      await paths.append('hashA', path(2));
      await paths.append('hashB', path(3));

      final all = await paths.loadAll();
      expect(all['hashA'], hasLength(2));
      expect(all['hashB'], hasLength(1));
      expect(all['hashA']!.first.snr, 1);
      expect(all['hashA']!.first.pathBytes, Uint8List.fromList([0xAA, 0xBB]));
      expect(all['hashA']!.first.pathHashCount, 2);
    });

    test('pruneToHashLimit keeps the most recently heard hashes', () async {
      for (var i = 0; i < 6; i++) {
        await paths.append('hash$i', path(i.toDouble()));
      }
      await paths.pruneToHashLimit(keepHashes: 2);

      final remaining = await paths.loadAll();
      expect(remaining.keys.toSet(), {'hash4', 'hash5'});
      expect(await paths.distinctHashCount(), 2);
    });
  });
}
