import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

/// One row per chat message, private or channel.
///
/// [convKey] mirrors the conversation keys `MessagesNotifier` already uses
/// (`contact_<hex6>` / `ch_<sanitizedDeviceId>_<index>`), so callers keep
/// addressing conversations exactly as they did with the old prefs keys.
///
/// The unique key reproduces the in-memory dedup identity (`_msgId`), moving
/// duplicate rejection into the database.
@DataClassName('MessageRow')
@TableIndex(name: 'messages_conv_ts', columns: {#convKey, #timestamp})
class Messages extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get convKey => text()();
  IntColumn get timestamp => integer()();
  BoolColumn get isOutgoing => boolean()();

  /// The message body. Named `content` because `text` collides with drift's
  /// own `text()` column builder.
  TextColumn get content => text().named('text')();

  BlobColumn get senderKey => blob().nullable()();
  IntColumn get channelIndex => integer().nullable()();
  TextColumn get senderName => text().nullable()();
  BoolColumn get confirmed => boolean().withDefault(const Constant(false))();
  RealColumn get snr => real().nullable()();
  IntColumn get pathLen => integer().nullable()();
  IntColumn get heardCount => integer().withDefault(const Constant(0))();
  IntColumn get sentRouteFlag => integer().nullable()();
  IntColumn get expectedAck => integer().nullable()();
  IntColumn get suggestedTimeoutMs => integer().nullable()();
  TextColumn get packetHashHex => text().nullable()();

  /// TXT_TYPE_CLI_DATA marker. This was absent from `ChatMessage.toJson`, so
  /// CLI responses used to reload from storage as normal chat messages.
  BoolColumn get isCliResponse =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get failed => boolean().withDefault(const Constant(false))();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();

  @override
  List<Set<Column>> get uniqueKeys => [
    {convKey, timestamp, isOutgoing, content},
  ];
}

/// Contacts known to the app — the radio's table plus advert-heard entries.
@DataClassName('ContactRow')
class ContactRows extends Table {
  @override
  String get tableName => 'contacts';

  BlobColumn get publicKey => blob()();
  IntColumn get type => integer()();
  IntColumn get flags => integer()();
  IntColumn get pathLen => integer()();
  TextColumn get name => text()();
  IntColumn get lastAdvertTimestamp => integer()();
  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();
  IntColumn get lastModified => integer().nullable()();
  TextColumn get customName => text().nullable()();

  @override
  Set<Column> get primaryKey => {publicKey};
}

/// Per-reception RF path records, keyed by packet hash. One row per reception,
/// so a repeated hash simply adds rows instead of rewriting a JSON blob.
@DataClassName('PacketPathRow')
@TableIndex(name: 'packet_paths_hash', columns: {#hashHex})
@TableIndex(name: 'packet_paths_recorded', columns: {#recordedAt})
class PacketPaths extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get hashHex => text()();
  RealColumn get snr => real()();
  IntColumn get rssi => integer()();
  IntColumn get pathHashCount => integer()();
  IntColumn get pathHashSize => integer()();
  BlobColumn get pathBytes => blob()();

  /// Epoch milliseconds — used for age-based pruning.
  IntColumn get recordedAt => integer()();
}

/// Small key/value settings that must survive app restarts.
///
/// SharedPreferences is a whole-file store: every write rewrites the file, and
/// a write interrupted by a kill can lose unrelated keys along with it. That is
/// what made Plan 3-3-3 config go missing between launches. These rows go
/// through the same transactional SQLite database as messages and contacts, so
/// a settings write is durable the moment it returns.
@DataClassName('AppSettingRow')
class AppSettings extends Table {
  @override
  String get tableName => 'app_settings';

  /// Setting name. Reuses the old SharedPreferences key strings so the
  /// one-time migration is a straight copy.
  TextColumn get settingKey => text().named('key')();

  /// Value, encoded as text. Non-string settings are stored as their JSON /
  /// `toString()` form and parsed back by the typed accessors.
  TextColumn get settingValue => text().named('value')();

  /// Epoch milliseconds of the last write — diagnostics only.
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {settingKey};
}

@DriftDatabase(tables: [Messages, ContactRows, PacketPaths, AppSettings])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  /// In-memory instance for tests.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    onUpgrade: (m, from, to) async {
      // v2 added `app_settings`, moving durable settings out of
      // SharedPreferences. Existing installs only need the new table.
      if (from < 2) {
        await m.createTable(appSettings);
      }
    },
  );

  static QueryExecutor _open() => driftDatabase(
    name: 'meshcore',
    web: DriftWebOptions(
      sqlite3Wasm: Uri.parse('sqlite3.wasm'),
      driftWorker: Uri.parse('drift_worker.js'),
    ),
  );
}
