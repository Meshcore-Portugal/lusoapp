import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lusoapp/services/db/app_database.dart';
import 'package:lusoapp/services/storage_service.dart';

/// Point [StorageService] at a throwaway in-memory database.
///
/// Call this from `setUp` in any test that exercises code writing messages,
/// contacts or packet paths. Without it the service tries to open a real
/// database file, which needs `path_provider` and fails under `flutter test`
/// with a MissingPluginException.
///
/// The database is closed automatically when the test ends.
AppDatabase useInMemoryDatabase() {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  StorageService.instance.debugUseDatabase(db);
  addTearDown(db.close);
  return db;
}
