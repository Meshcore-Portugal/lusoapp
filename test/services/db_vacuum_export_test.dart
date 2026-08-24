import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lusoapp/services/db/app_database.dart';
import 'package:lusoapp/services/storage_service.dart';

import '../support/test_db.dart';

void main() {
  test('VACUUM INTO snapshot is a valid standalone database', () async {
    final db = useInMemoryDatabase();
    await db
        .into(db.messages)
        .insert(
          MessagesCompanion.insert(
            convKey: 'abc',
            timestamp: 1234,
            isOutgoing: true,
            content: 'hello snapshot',
          ),
        );

    final tmp = await Directory.systemTemp.createTemp('mc_vacuum');
    final target = File('${tmp.path}/snap.db');
    final escaped = target.path.replaceAll("'", "''");
    await StorageService.instance.db.customStatement(
      "VACUUM INTO '$escaped'",
    );

    expect(await target.exists(), isTrue);
    final bytes = await target.readAsBytes();
    expect(bytes.length, greaterThan(0));
    // SQLite file header.
    expect(String.fromCharCodes(bytes.sublist(0, 15)), 'SQLite format 3');

    // Reopen the snapshot on its own and confirm the row survived.
    final reopened = AppDatabase.forTesting(NativeDatabase(target));
    final rows = await reopened.select(reopened.messages).get();
    expect(rows.single.content, 'hello snapshot');
    await reopened.close();

    await tmp.delete(recursive: true);
  });
}
