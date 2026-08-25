import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lusoapp/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_db.dart';

/// Plan 3-3-3 config used to live in SharedPreferences and was reported
/// missing after users closed and reopened the app. It now lives in the same
/// SQLite database as messages and contacts. These tests cover the round-trip
/// and the one-time move of existing installs' values.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const configJson =
      '{"station_name":"CT1ABC","city":"Lisboa","locality":"Benfica",'
      '"mesh_channel":2,"auto_send":true}';

  group('database round-trip', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      useInMemoryDatabase();
    });

    test('config survives a reload', () async {
      final storage = StorageService.instance;
      await storage.savePlan333Config(configJson);
      expect(await storage.loadPlan333Config(), configJson);
    });

    test('a later write replaces the row instead of duplicating it', () async {
      final storage = StorageService.instance;
      await storage.savePlan333Config(configJson);
      await storage.savePlan333Config('{"station_name":"CT1XYZ"}');

      expect(await storage.loadPlan333Config(), '{"station_name":"CT1XYZ"}');
      final all = await storage.settings.loadAll();
      expect(all.keys.where((k) => k == 'plan333_config'), hasLength(1));
    });

    test('enabled flag, auto-send state and QSL log round-trip', () async {
      final storage = StorageService.instance;
      final log = jsonEncode([
        {'station': 'CT1DEF', 'hops': 2, 'location': 'Porto', 'ts': 1700},
      ]);

      await storage.savePlan333Enabled(true);
      await storage.savePlan333AutoSendState('{"cq_sent_count":2}');
      await storage.saveQslLog(log);
      await storage.saveQslLogSessionStart(1700000000000);

      expect(await storage.loadPlan333Enabled(), isTrue);
      expect(await storage.loadPlan333AutoSendState(), '{"cq_sent_count":2}');
      expect(await storage.loadQslLog(), log);
      expect(await storage.loadQslLogSessionStart(), 1700000000000);
    });

    test('unset values read back as their defaults', () async {
      final storage = StorageService.instance;
      expect(await storage.loadPlan333Config(), isNull);
      expect(await storage.loadPlan333Enabled(), isFalse);
      expect(await storage.loadQslLogSessionStart(), isNull);
    });

    test('a null session start clears the stored row', () async {
      final storage = StorageService.instance;
      await storage.saveQslLogSessionStart(1700000000000);
      await storage.saveQslLogSessionStart(null);
      expect(await storage.loadQslLogSessionStart(), isNull);
    });
  });

  group('migration from SharedPreferences', () {
    test('moves every key into the database and deletes the originals',
        () async {
      SharedPreferences.setMockInitialValues({
        'plan333_enabled': true,
        'plan333_config': configJson,
        'plan333_auto_send_state': '{"cq_sent_count":1}',
        'plan333_qsl_log': '[]',
        'plan333_qsl_log_session_start': 1700000000000,
      });
      useInMemoryDatabase();

      final storage = StorageService.instance;
      expect(await storage.migratePlan333Settings(), 5);

      expect(await storage.loadPlan333Config(), configJson);
      expect(await storage.loadPlan333Enabled(), isTrue);
      expect(await storage.loadPlan333AutoSendState(), '{"cq_sent_count":1}');
      expect(await storage.loadQslLog(), '[]');
      expect(await storage.loadQslLogSessionStart(), 1700000000000);

      final prefs = await SharedPreferences.getInstance();
      for (final key in StorageService.plan333SettingKeys) {
        expect(prefs.get(key), isNull, reason: '$key should be removed');
      }
    });

    test('never overwrites a value already in the database', () async {
      SharedPreferences.setMockInitialValues({'plan333_config': configJson});
      useInMemoryDatabase();

      final storage = StorageService.instance;
      await storage.savePlan333Config('{"station_name":"NEWER"}');

      expect(await storage.migratePlan333Settings(), 0);
      expect(await storage.loadPlan333Config(), '{"station_name":"NEWER"}');
    });

    test('a second run is a no-op and cannot resurrect stale values',
        () async {
      SharedPreferences.setMockInitialValues({'plan333_config': configJson});
      useInMemoryDatabase();

      final storage = StorageService.instance;
      expect(await storage.migratePlan333Settings(), 1);

      await storage.savePlan333Config('{"station_name":"EDITED"}');
      expect(await storage.migratePlan333Settings(), 0);
      expect(await storage.loadPlan333Config(), '{"station_name":"EDITED"}');
    });

    test('does nothing when prefs hold no Plan 3-3-3 keys', () async {
      SharedPreferences.setMockInitialValues({'last_device_id': 'AA:BB:CC'});
      useInMemoryDatabase();

      final storage = StorageService.instance;
      expect(await storage.migratePlan333Settings(), 0);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('last_device_id'), 'AA:BB:CC');
    });
  });
}
