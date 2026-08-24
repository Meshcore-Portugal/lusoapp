import 'package:drift/drift.dart';

import '../../protocol/models.dart';
import 'app_database.dart';

/// Row ⇄ model mapping and the queries behind `StorageService`.
///
/// These replace the JSON-blob-in-SharedPreferences representation. The key
/// win is that one message or one path can be written on its own: the old code
/// re-encoded an entire conversation (up to 2000 messages) and rewrote the
/// whole preferences file for every single update.

// ---------------------------------------------------------------------------
// Messages
// ---------------------------------------------------------------------------

class MessageStore {
  const MessageStore(this._db);
  final AppDatabase _db;

  static ChatMessage toModel(MessageRow r) => ChatMessage(
    text: r.content,
    timestamp: r.timestamp,
    isOutgoing: r.isOutgoing,
    senderKey: r.senderKey,
    channelIndex: r.channelIndex,
    senderName: r.senderName,
    confirmed: r.confirmed,
    snr: r.snr,
    pathLen: r.pathLen,
    heardCount: r.heardCount,
    sentRouteFlag: r.sentRouteFlag,
    expectedAck: r.expectedAck,
    suggestedTimeoutMs: r.suggestedTimeoutMs,
    packetHashHex: r.packetHashHex,
    isCliResponse: r.isCliResponse,
    failed: r.failed,
    retryCount: r.retryCount,
  );

  static MessagesCompanion toCompanion(String convKey, ChatMessage m) =>
      MessagesCompanion.insert(
        convKey: convKey,
        timestamp: m.timestamp,
        isOutgoing: m.isOutgoing,
        content: m.text,
        senderKey: Value(m.senderKey),
        channelIndex: Value(m.channelIndex),
        senderName: Value(m.senderName),
        confirmed: Value(m.confirmed),
        snr: Value(m.snr),
        pathLen: Value(m.pathLen),
        heardCount: Value(m.heardCount),
        sentRouteFlag: Value(m.sentRouteFlag),
        expectedAck: Value(m.expectedAck),
        suggestedTimeoutMs: Value(m.suggestedTimeoutMs),
        packetHashHex: Value(m.packetHashHex),
        isCliResponse: Value(m.isCliResponse),
        failed: Value(m.failed),
        retryCount: Value(m.retryCount),
      );

  /// Newest [limit] messages for [convKey], returned oldest-first for display.
  Future<List<ChatMessage>> load(String convKey, {required int limit}) async {
    final q =
        _db.select(_db.messages)
          ..where((t) => t.convKey.equals(convKey))
          ..orderBy([
            (t) => OrderingTerm.desc(t.timestamp),
            (t) => OrderingTerm.desc(t.id),
          ])
          ..limit(limit);
    final rows = await q.get();
    return rows.reversed.map(toModel).toList();
  }

  /// Insert [m], or update its mutable fields when the conversation already
  /// holds a message with the same identity.
  ///
  /// This one call replaces the old "rewrite the whole conversation" save for
  /// both new messages and status transitions (confirmed / failed /
  /// retryCount / heardCount / route flags).
  Future<void> upsert(String convKey, ChatMessage m) async {
    await _db
        .into(_db.messages)
        .insert(
          toCompanion(convKey, m),
          onConflict: DoUpdate(
            (_) => MessagesCompanion.custom(
              confirmed: Constant(m.confirmed),
              snr: Constant(m.snr),
              pathLen: Constant(m.pathLen),
              heardCount: Constant(m.heardCount),
              sentRouteFlag: Constant(m.sentRouteFlag),
              expectedAck: Constant(m.expectedAck),
              suggestedTimeoutMs: Constant(m.suggestedTimeoutMs),
              packetHashHex: Constant(m.packetHashHex),
              isCliResponse: Constant(m.isCliResponse),
              failed: Constant(m.failed),
              retryCount: Constant(m.retryCount),
              senderName: Constant(m.senderName),
            ),
            target: [
              _db.messages.convKey,
              _db.messages.timestamp,
              _db.messages.isOutgoing,
              _db.messages.content,
            ],
          ),
        );
  }

  /// Replace every message stored for [convKey]. Used for bulk rewrites, such
  /// as removing a single message from a conversation.
  Future<void> replaceAll(String convKey, List<ChatMessage> messages) async {
    await _db.transaction(() async {
      await (_db.delete(_db.messages)
        ..where((t) => t.convKey.equals(convKey))).go();
      await _db.batch((b) {
        b.insertAll(_db.messages, [
          for (final m in messages) toCompanion(convKey, m),
        ], mode: InsertMode.insertOrIgnore);
      });
    });
  }

  Future<void> clear(String convKey) async {
    await (_db.delete(_db.messages)
      ..where((t) => t.convKey.equals(convKey))).go();
  }

  /// Drop the oldest rows of [convKey] beyond the newest [keep].
  Future<void> prune(String convKey, {required int keep}) async {
    await _db.customStatement(
      'DELETE FROM messages WHERE conv_key = ?1 AND id NOT IN '
      '(SELECT id FROM messages WHERE conv_key = ?1 '
      'ORDER BY timestamp DESC, id DESC LIMIT ?2)',
      [convKey, keep],
    );
  }

  /// Trim every conversation to its newest [keepPerConversation] rows in one
  /// statement. Used as a startup retention pass.
  Future<void> pruneAll({required int keepPerConversation}) async {
    await _db.customStatement(
      'DELETE FROM messages WHERE id IN ('
      '  SELECT id FROM ('
      '    SELECT id, ROW_NUMBER() OVER ('
      '      PARTITION BY conv_key ORDER BY timestamp DESC, id DESC'
      '    ) AS rn FROM messages'
      '  ) WHERE rn > ?1'
      ')',
      [keepPerConversation],
    );
  }

  Future<int> count() async {
    final row =
        await _db
            .customSelect('SELECT COUNT(*) AS c FROM messages')
            .getSingle();
    return row.read<int>('c');
  }
}

// ---------------------------------------------------------------------------
// Contacts
// ---------------------------------------------------------------------------

class ContactStore {
  const ContactStore(this._db);
  final AppDatabase _db;

  static Contact toModel(ContactRow r) => Contact(
    publicKey: r.publicKey,
    type: r.type,
    flags: r.flags,
    pathLen: r.pathLen,
    name: r.name,
    lastAdvertTimestamp: r.lastAdvertTimestamp,
    latitude: r.latitude,
    longitude: r.longitude,
    lastModified: r.lastModified,
    customName: r.customName,
  );

  static ContactRowsCompanion toCompanion(Contact c) =>
      ContactRowsCompanion.insert(
        publicKey: c.publicKey,
        type: c.type,
        flags: c.flags,
        pathLen: c.pathLen,
        name: c.name,
        lastAdvertTimestamp: c.lastAdvertTimestamp,
        latitude: Value(c.latitude),
        longitude: Value(c.longitude),
        lastModified: Value(c.lastModified),
        customName: Value(c.customName),
      );

  Future<List<Contact>> loadAll() async {
    final rows = await _db.select(_db.contactRows).get();
    return rows.map(toModel).toList();
  }

  /// Replace the stored contact set. `ContactsNotifier` writes contacts as a
  /// whole list, and the set is small enough (hundreds) that a transactional
  /// replace stays cheap.
  Future<void> replaceAll(List<Contact> contacts) async {
    await _db.transaction(() async {
      await _db.delete(_db.contactRows).go();
      await _db.batch((b) {
        b.insertAll(
          _db.contactRows,
          contacts.map(toCompanion).toList(),
          mode: InsertMode.insertOrReplace,
        );
      });
    });
  }

  Future<int> count() async {
    final row =
        await _db
            .customSelect('SELECT COUNT(*) AS c FROM contacts')
            .getSingle();
    return row.read<int>('c');
  }
}

// ---------------------------------------------------------------------------
// Packet paths
// ---------------------------------------------------------------------------

class PacketPathStore {
  const PacketPathStore(this._db);
  final AppDatabase _db;

  static MessagePath toModel(PacketPathRow r) => MessagePath(
    snr: r.snr,
    rssi: r.rssi,
    pathHashCount: r.pathHashCount,
    pathHashSize: r.pathHashSize,
    pathBytes: r.pathBytes,
  );

  static PacketPathsCompanion toCompanion(
    String hashHex,
    MessagePath p,
    int recordedAt,
  ) => PacketPathsCompanion.insert(
    hashHex: hashHex,
    snr: p.snr,
    rssi: p.rssi,
    pathHashCount: p.pathHashCount,
    pathHashSize: p.pathHashSize,
    pathBytes: p.pathBytes,
    recordedAt: recordedAt,
  );

  Future<Map<String, List<MessagePath>>> loadAll() async {
    final rows =
        await (_db.select(_db.packetPaths)
          ..orderBy([(t) => OrderingTerm.asc(t.id)])).get();
    final out = <String, List<MessagePath>>{};
    for (final r in rows) {
      (out[r.hashHex] ??= <MessagePath>[]).add(toModel(r));
    }
    return out;
  }

  /// Append one reception — the hot path: one packet, one row.
  Future<void> append(String hashHex, MessagePath path) async {
    await _db
        .into(_db.packetPaths)
        .insert(
          toCompanion(hashHex, path, DateTime.now().millisecondsSinceEpoch),
        );
  }

  Future<void> replaceAll(Map<String, List<MessagePath>> paths) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction(() async {
      await _db.delete(_db.packetPaths).go();
      await _db.batch((b) {
        for (final e in paths.entries) {
          b.insertAll(_db.packetPaths, [
            for (final p in e.value) toCompanion(e.key, p, now),
          ]);
        }
      });
    });
  }

  /// Keep only the [keepHashes] most recently heard packet hashes.
  ///
  /// Ties on `recorded_at` are broken by row id: a burst of packets can share
  /// a millisecond, and without the tie-break which hashes survive would be
  /// arbitrary. Row id is monotonic, so it stands in for arrival order.
  Future<void> pruneToHashLimit({required int keepHashes}) async {
    await _db.customStatement(
      'DELETE FROM packet_paths WHERE hash_hex NOT IN '
      '(SELECT hash_hex FROM packet_paths '
      'GROUP BY hash_hex '
      'ORDER BY MAX(recorded_at) DESC, MAX(id) DESC LIMIT ?1)',
      [keepHashes],
    );
  }

  Future<int> distinctHashCount() async {
    final row =
        await _db
            .customSelect(
              'SELECT COUNT(DISTINCT hash_hex) AS c FROM packet_paths',
            )
            .getSingle();
    return row.read<int>('c');
  }
}
