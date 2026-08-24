import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lusoapp/protocol/protocol.dart';
import 'package:lusoapp/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_db.dart';

/// The one-time move of bulk data out of SharedPreferences. Deleting the old
/// keys is the part that actually reclaims the multi-megabyte preferences file
/// responsible for slow cold starts, so these tests check removal as closely
/// as they check the copy.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final alice = Uint8List.fromList([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 1, 2]);

  Map<String, Object> legacyPrefs({
    int conversations = 2,
    int perConversation = 5,
    int contacts = 3,
    int pathHashes = 4,
  }) {
    final out = <String, Object>{};

    for (var c = 0; c < conversations; c++) {
      final msgs = [
        for (var i = 0; i < perConversation; i++)
          ChatMessage(
            text: 'conv$c message $i',
            timestamp: 1000 + (c * 100) + i,
            isOutgoing: i.isEven,
            senderKey: alice,
            senderName: 'Alice',
            snr: -6.5,
            pathLen: 2,
          ).toJson(),
      ];
      out['msgs_v1_contact_conv$c'] = jsonEncode(msgs);
    }

    out['contacts_v1'] = jsonEncode([
      for (var i = 0; i < contacts; i++)
        Contact(
          publicKey: Uint8List.fromList([i, i, i, i, i, i, i, i]),
          type: 1,
          flags: 1,
          pathLen: 1,
          name: 'contact$i',
          lastAdvertTimestamp: 500 + i,
          latitude: 38.0 + i,
          longitude: -9.0 - i,
        ).toJson(),
    ]);

    out['msg_paths_v1'] = jsonEncode({
      for (var h = 0; h < pathHashes; h++)
        'hash$h': [
          MessagePath(
            snr: h.toDouble(),
            rssi: -80 - h,
            pathHashCount: 1,
            pathHashSize: 1,
            pathBytes: Uint8List.fromList([h]),
          ).toJson(),
        ],
    });

    return out;
  }

  test(
    'moves every bulk key into the database and deletes the originals',
    () async {
      SharedPreferences.setMockInitialValues(legacyPrefs());
      useInMemoryDatabase();

      final result = await StorageService.instance.migrateFromPrefs();

      expect(result.completed, isTrue);
      expect(result.failedKeys, isEmpty);
      expect(result.conversations, 2);
      expect(result.messages, 10);
      expect(result.contacts, 3);
      expect(result.packetPathHashes, 4);

      // Data is queryable from the database.
      final conv0 = await StorageService.instance.loadMessages('contact_conv0');
      expect(conv0, hasLength(5));
      expect(conv0.first.text, 'conv0 message 0');
      expect(conv0.first.senderName, 'Alice');
      expect(conv0.first.snr, -6.5);

      expect(await StorageService.instance.loadContacts(), hasLength(3));
      expect(await StorageService.instance.loadMessagePaths(), hasLength(4));

      // The old keys are gone — this is what shrinks the preferences file.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().where((k) => k.startsWith('msgs_v1_')), isEmpty);
      expect(prefs.getString('contacts_v1'), isNull);
      expect(prefs.getString('msg_paths_v1'), isNull);
    },
  );

  test('is idempotent — a second run is a no-op', () async {
    SharedPreferences.setMockInitialValues(legacyPrefs());
    useInMemoryDatabase();

    await StorageService.instance.migrateFromPrefs();
    final second = await StorageService.instance.migrateFromPrefs();

    expect(second.didWork, isFalse);
    expect(second.completed, isTrue);
    // Nothing was duplicated by the second pass.
    expect(
      await StorageService.instance.loadMessages('contact_conv0'),
      hasLength(5),
    );
    expect(await StorageService.instance.loadContacts(), hasLength(3));
  });

  test('leaves settings keys alone', () async {
    SharedPreferences.setMockInitialValues({
      ...legacyPrefs(),
      'last_device_id': 'AA:BB:CC',
      'notification_settings_v1': '{"enabled":true}',
      'contacts_filter': 2,
    });
    useInMemoryDatabase();

    await StorageService.instance.migrateFromPrefs();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('last_device_id'), 'AA:BB:CC');
    expect(prefs.getString('notification_settings_v1'), '{"enabled":true}');
    expect(prefs.getInt('contacts_filter'), 2);
  });

  test('a corrupt conversation is left in place for a later retry', () async {
    SharedPreferences.setMockInitialValues({
      ...legacyPrefs(conversations: 1),
      'msgs_v1_contact_broken': 'not valid json at all',
    });
    useInMemoryDatabase();

    final result = await StorageService.instance.migrateFromPrefs();

    expect(result.completed, isFalse, reason: 'must not set the done flag');
    expect(result.failedKeys, contains('msgs_v1_contact_broken'));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('msgs_v1_contact_broken'), isNotNull);
    // The healthy conversation still migrated and was cleaned up.
    expect(prefs.getString('msgs_v1_contact_conv0'), isNull);
    expect(
      await StorageService.instance.loadMessages('contact_conv0'),
      hasLength(5),
    );
  });

  test('an empty install migrates cleanly', () async {
    SharedPreferences.setMockInitialValues({});
    useInMemoryDatabase();

    final result = await StorageService.instance.migrateFromPrefs();

    expect(result.completed, isTrue);
    expect(result.didWork, isFalse);
  });

  test('caps an over-long conversation at maxMessagesPerKey', () async {
    const over = StorageService.maxMessagesPerKey + 25;
    SharedPreferences.setMockInitialValues({
      'msgs_v1_contact_big': jsonEncode([
        for (var i = 0; i < over; i++)
          ChatMessage(
            text: 'm$i',
            timestamp: i,
            isOutgoing: false,
            senderKey: alice,
          ).toJson(),
      ]),
    });
    useInMemoryDatabase();

    await StorageService.instance.migrateFromPrefs();

    final loaded = await StorageService.instance.loadMessages('contact_big');
    expect(loaded, hasLength(StorageService.maxMessagesPerKey));
    // The newest messages are the ones kept.
    expect(loaded.last.text, 'm${over - 1}');
  });
}
