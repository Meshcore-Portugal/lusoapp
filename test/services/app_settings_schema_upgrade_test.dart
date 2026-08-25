import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lusoapp/services/db/app_database.dart';
import 'package:lusoapp/services/storage_service.dart';
import 'package:sqlite3/sqlite3.dart';

/// Every existing install opens a schema-v1 file. `app_settings` (schema v2)
/// has to appear on that path too, or Plan 3-3-3 settings would fail to write
/// for exactly the users whose settings were going missing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('mc_schema_upgrade');
    file = File('${dir.path}/meshcore.sqlite');
  });

  tearDown(() {
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows keeps the file handle briefly after close; the temp dir is
      // the OS's problem at that point.
    }
  });

  /// Produce the file an existing install would have: current tables minus
  /// `app_settings`, stamped back to schema v1.
  ///
  /// Drift builds it (so the v1 tables match production exactly), then raw
  /// sqlite3 removes the v2 addition and rewinds `user_version`.
  Future<void> writeV1File() async {
    final seed = AppDatabase.forTesting(NativeDatabase(file));
    await seed.customStatement('SELECT 1'); // forces onCreate
    await seed.close();

    final raw = sqlite3.open(file.path);
    raw.execute('DROP TABLE app_settings');
    raw.execute('PRAGMA user_version = 1');
    raw.dispose();
  }

  test('a schema-v1 database gains app_settings on open', () async {
    await writeV1File();

    final raw = sqlite3.open(file.path);
    expect(
      raw.select("SELECT name FROM sqlite_master WHERE name='app_settings'"),
      isEmpty,
    );
    expect(raw.select('PRAGMA user_version').first.values.first, 1);
    raw.dispose();

    // Reopening with the current schema must run onUpgrade.
    final upgraded = AppDatabase.forTesting(NativeDatabase(file));
    StorageService.instance.debugUseDatabase(upgraded);

    await StorageService.instance.savePlan333Config(
      '{"station_name":"CT1ABC"}',
    );
    expect(
      await StorageService.instance.loadPlan333Config(),
      '{"station_name":"CT1ABC"}',
    );

    await upgraded.close();
  });

  test('existing rows survive the upgrade', () async {
    await writeV1File();
    final raw = sqlite3.open(file.path);
    raw.execute(
      'INSERT INTO messages (conv_key, timestamp, is_outgoing, text) '
      "VALUES ('contact_abc', 1700, 0, 'hello')",
    );
    raw.dispose();

    final upgraded = AppDatabase.forTesting(NativeDatabase(file));
    StorageService.instance.debugUseDatabase(upgraded);

    final msgs = await StorageService.instance.loadMessages('contact_abc');
    expect(msgs, hasLength(1));
    expect(msgs.single.text, 'hello');

    await upgraded.close();
  });
}
