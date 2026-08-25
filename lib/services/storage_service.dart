import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../protocol/models.dart';
import 'db/app_database.dart';
import 'db/stores.dart';

String _sanitizeUtf16(String s) {
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c >= 0xD800 && c <= 0xDFFF) {
      final buf = StringBuffer();
      for (var j = 0; j < s.length; j++) {
        final u = s.codeUnitAt(j);
        if (u >= 0xD800 && u <= 0xDBFF) {
          if (j + 1 < s.length) {
            final u2 = s.codeUnitAt(j + 1);
            if (u2 >= 0xDC00 && u2 <= 0xDFFF) {
              buf.write(s[j]);
              buf.write(s[j + 1]);
              j++;
              continue;
            }
          }
          buf.writeCharCode(0xFFFD);
        } else if (u >= 0xDC00 && u <= 0xDFFF) {
          buf.writeCharCode(0xFFFD);
        } else {
          buf.write(s[j]);
        }
      }
      return buf.toString();
    }
  }
  return s;
}

String _safeDeviceName(String name, {required String fallback}) {
  final sanitized = _sanitizeUtf16(name).trim();
  return sanitized.isEmpty ? fallback : sanitized;
}

/// Persistent storage for messages, contacts, and device settings.
///
/// Bulk data (messages, contacts, packet paths) lives in a SQLite database via
/// drift; small settings stay in [SharedPreferences].
///
/// SharedPreferences is a whole-file store: every write rewrote the entire
/// file, and `getInstance()` loads every key across the platform channel at
/// startup. With messages and per-packet path records in there it grew to
/// megabytes, which is what made cold start slow and writes expensive.
/// Settings are small and unaffected, so they stayed put.
///
/// Messages are capped at [maxMessagesPerKey] entries per conversation key
/// to bound storage growth.
class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  static const _keyLastDeviceId = 'last_device_id';
  static const _keyLastDeviceType = 'last_device_type';
  static const _keyLastDeviceName = 'last_device_name';
  static const _keyContacts = 'contacts_v1';
  static const int maxMessagesPerKey = 2000;

  /// Maximum distinct packet hashes retained on disk. Mirrors the in-memory
  /// cap in `PacketHeardNotifier`.
  static const int maxPacketPathHashes = 2000;

  /// Legacy prefs key prefix for a conversation's messages. Retained only so
  /// [migrateFromPrefs] can find and clear the old entries.
  static const _legacyMessagesPrefix = 'msgs_v1_';

  // ---------------------------------------------------------------------------
  // Database
  // ---------------------------------------------------------------------------

  AppDatabase? _db;

  /// The database, opened on first use.
  AppDatabase get db => _db ??= AppDatabase();

  /// Inject a database (e.g. an in-memory one) for tests.
  void debugUseDatabase(AppDatabase database) {
    _db = database;
    _messages = null;
    _contacts = null;
    _paths = null;
    _settings = null;
  }

  MessageStore? _messages;
  ContactStore? _contacts;
  PacketPathStore? _paths;
  SettingsStore? _settings;

  MessageStore get messages => _messages ??= MessageStore(db);
  ContactStore get contacts => _contacts ??= ContactStore(db);
  PacketPathStore get packetPaths => _paths ??= PacketPathStore(db);

  /// Durable key/value settings. Anything the user configured and expects to
  /// find again after a restart belongs here rather than in prefs.
  SettingsStore get settings => _settings ??= SettingsStore(db);

  // ---------------------------------------------------------------------------
  // Last connected device
  // ---------------------------------------------------------------------------

  Future<void> saveLastDevice({
    required String id,
    required String type,
    required String name,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final safeName = _safeDeviceName(name, fallback: id);
    await prefs.setString(_keyLastDeviceId, id);
    await prefs.setString(_keyLastDeviceType, type);
    await prefs.setString(_keyLastDeviceName, safeName);
  }

  /// Returns `null` when no device has been saved yet.
  Future<LastDevice?> loadLastDevice() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_keyLastDeviceId);
    final type = prefs.getString(_keyLastDeviceType);
    final name = prefs.getString(_keyLastDeviceName);
    if (id == null || type == null) return null;
    return LastDevice(
      id: id,
      type: type,
      name: _safeDeviceName(name ?? id, fallback: id),
    );
  }

  Future<void> clearLastDevice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyLastDeviceId);
    await prefs.remove(_keyLastDeviceType);
    await prefs.remove(_keyLastDeviceName);
  }

  // ---------------------------------------------------------------------------
  // Recent devices — ordered most-recent first, capped at [maxRecentDevices].
  // ---------------------------------------------------------------------------

  static const _keyRecentDevices = 'recent_devices_v1';
  static const int maxRecentDevices = 5;

  /// Inserts or moves the device to the front of the recent list, writes the
  /// legacy single-device keys for backward compat, and persists.
  /// Returns the updated list (most-recent first).
  Future<List<LastDevice>> upsertRecentDevice({
    required String id,
    required String type,
    required String name,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final safeName = _safeDeviceName(name, fallback: id);
      // Keep legacy keys in sync so loadLastDevice() still works.
      await prefs.setString(_keyLastDeviceId, id);
      await prefs.setString(_keyLastDeviceType, type);
      await prefs.setString(_keyLastDeviceName, safeName);
      // Prepend, dedup by id, cap.
      final existing = _parseRecentDevices(prefs);
      final updated =
          [
            LastDevice(id: id, type: type, name: safeName),
            ...existing.where((d) => d.id != id),
          ].take(maxRecentDevices).toList();
      await prefs.setString(
        _keyRecentDevices,
        jsonEncode(
          updated
              .map((d) => {'id': d.id, 'type': d.type, 'name': d.name})
              .toList(),
        ),
      );
      return updated;
    } catch (_) {
      return [
        LastDevice(
          id: id,
          type: type,
          name: _safeDeviceName(name, fallback: id),
        ),
      ];
    }
  }

  /// Removes the device with [id] from the recent list and persists.
  /// Also updates the legacy single-device keys to reflect the new head
  /// of the list (or clears them if the list becomes empty).
  /// Returns the updated list.
  Future<List<LastDevice>> removeRecentDevice(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = _parseRecentDevices(prefs);
      final updated = existing.where((d) => d.id != id).toList();
      await prefs.setString(
        _keyRecentDevices,
        jsonEncode(
          updated
              .map((d) => {'id': d.id, 'type': d.type, 'name': d.name})
              .toList(),
        ),
      );
      // Sync legacy keys.
      if (updated.isNotEmpty) {
        final first = updated.first;
        await prefs.setString(_keyLastDeviceId, first.id);
        await prefs.setString(_keyLastDeviceType, first.type);
        await prefs.setString(_keyLastDeviceName, first.name);
      } else {
        await prefs.remove(_keyLastDeviceId);
        await prefs.remove(_keyLastDeviceType);
        await prefs.remove(_keyLastDeviceName);
      }
      return updated;
    } catch (_) {
      return [];
    }
  }

  /// Loads the recent-devices list.  On first call after an upgrade migrates
  /// the legacy single-device keys into a one-element list.
  Future<List<LastDevice>> loadRecentDevices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyRecentDevices);
      if (raw != null) return _parseRecentDevices(prefs);
      // Migration: seed from legacy last_device keys.
      final id = prefs.getString(_keyLastDeviceId);
      final type = prefs.getString(_keyLastDeviceType);
      final name = prefs.getString(_keyLastDeviceName);
      if (id == null || type == null) return [];
      final seeded = [
        LastDevice(
          id: id,
          type: type,
          name: _safeDeviceName(name ?? id, fallback: id),
        ),
      ];
      await prefs.setString(
        _keyRecentDevices,
        jsonEncode(
          seeded
              .map((d) => {'id': d.id, 'type': d.type, 'name': d.name})
              .toList(),
        ),
      );
      return seeded;
    } catch (_) {
      return [];
    }
  }

  static List<LastDevice> _parseRecentDevices(SharedPreferences prefs) {
    try {
      final raw = prefs.getString(_keyRecentDevices);
      if (raw == null) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map(
            (e) => LastDevice(
              id: e['id'] as String,
              type: e['type'] as String,
              name: _safeDeviceName(
                e['name'] as String? ?? e['id'] as String,
                fallback: e['id'] as String,
              ),
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // Messages  (key = 'contact_<hex6>' or 'ch_<index>')
  // ---------------------------------------------------------------------------

  /// Write or update one message. This is the hot path: it costs a single row
  /// insert (or an update of the mutable status fields when the message is
  /// already stored), rather than re-encoding the whole conversation.
  Future<void> upsertMessage(String key, ChatMessage message) async {
    try {
      await messages.upsert(key, message);
    } catch (_) {
      // Storage errors are non-fatal — messages still live in memory.
    }
  }

  /// Replace every stored message for [key]. Prefer [upsertMessage] for single
  /// messages; this exists for bulk rewrites such as deleting one message.
  Future<void> saveMessages(String key, List<ChatMessage> msgs) async {
    try {
      final tail =
          msgs.length > maxMessagesPerKey
              ? msgs.sublist(msgs.length - maxMessagesPerKey)
              : msgs;
      await messages.replaceAll(key, tail);
    } catch (_) {}
  }

  Future<List<ChatMessage>> loadMessages(String key) async {
    try {
      return await messages.load(key, limit: maxMessagesPerKey);
    } catch (_) {
      return [];
    }
  }

  Future<void> clearMessages(String key) async {
    try {
      await messages.clear(key);
    } catch (_) {}
  }

  /// Trim [key] back to [maxMessagesPerKey] rows, newest kept.
  Future<void> pruneMessages(String key) async {
    try {
      await messages.prune(key, keep: maxMessagesPerKey);
    } catch (_) {}
  }

  /// Apply retention limits across the whole database. Cheap enough to run at
  /// startup: two statements, no data loaded into Dart.
  Future<void> applyRetention() async {
    try {
      await messages.pruneAll(keepPerConversation: maxMessagesPerKey);
      await packetPaths.pruneToHashLimit(keepHashes: maxPacketPathHashes);
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Contacts
  // ---------------------------------------------------------------------------

  Future<void> saveContacts(List<Contact> list) async {
    try {
      await contacts.replaceAll(list);
    } catch (_) {}
  }

  Future<List<Contact>> loadContacts() async {
    try {
      return await contacts.loadAll();
    } catch (_) {
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // Channels
  // ---------------------------------------------------------------------------

  static const _keyChannels = 'channels_v1';
  static const _keyChannelsV2Prefix = 'channels_v2_';
  static const _keyMutedChannelsV2Prefix = 'muted_channels_v2_';
  static const _keyKnownRegionsV1Prefix = 'known_regions_v1_';
  static const _keyDefaultFloodScopeV1Prefix = 'default_flood_scope_v1_';

  /// Sanitise a device ID for use as a storage key suffix.
  /// Replaces any non-alphanumeric characters (colons, slashes, etc.) with '_'.
  static String sanitizeId(String deviceId) =>
      deviceId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');

  // ---------------------------------------------------------------------------
  // Channels — radio-scoped (v2) and legacy global (v1) storage.
  // ---------------------------------------------------------------------------

  /// Save channels scoped to a specific radio device ID.
  Future<void> saveChannelsForRadio(
    String deviceId,
    List<ChannelInfo> channels,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(channels.map((c) => c.toJson()).toList());
      await prefs.setString(
        '$_keyChannelsV2Prefix${sanitizeId(deviceId)}',
        json,
      );
    } catch (_) {}
  }

  /// Load channels scoped to a specific radio device ID.
  /// Falls back to the legacy global key on first use so existing users don't
  /// lose their channel list after upgrading.
  Future<List<ChannelInfo>> loadChannelsForRadio(String deviceId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final scopedKey = '$_keyChannelsV2Prefix${sanitizeId(deviceId)}';
      final json = prefs.getString(scopedKey) ?? prefs.getString(_keyChannels);
      if (json == null) return [];
      final list = jsonDecode(json) as List<dynamic>;
      return list
          .map((e) => ChannelInfo.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // Legacy global channel methods kept for migration / offline startup.
  Future<void> saveChannels(List<ChannelInfo> channels) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(channels.map((c) => c.toJson()).toList());
      await prefs.setString(_keyChannels, json);
    } catch (_) {}
  }

  Future<List<ChannelInfo>> loadChannels() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_keyChannels);
      if (json == null) return [];
      final list = jsonDecode(json) as List<dynamic>;
      return list
          .map((e) => ChannelInfo.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // Muted channels — radio-scoped (v2) storage.
  // ---------------------------------------------------------------------------

  Future<void> saveMutedChannelsForRadio(
    String deviceId,
    Set<int> indices,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        '$_keyMutedChannelsV2Prefix${sanitizeId(deviceId)}',
        indices.map((i) => '$i').toList(),
      );
    } catch (_) {}
  }

  /// Load muted channel indices for a specific radio device.
  /// Falls back to the legacy global key on first use.
  Future<Set<int>> loadMutedChannelsForRadio(String deviceId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final scopedKey = '$_keyMutedChannelsV2Prefix${sanitizeId(deviceId)}';
      final list =
          prefs.getStringList(scopedKey) ??
          prefs.getStringList('muted_channels_v1') ??
          [];
      return list.map(int.parse).toSet();
    } catch (_) {
      return {};
    }
  }

  // ---------------------------------------------------------------------------
  // Region/default-scope state — radio-scoped (v1)
  // ---------------------------------------------------------------------------

  Future<void> saveKnownRegionsForRadio(
    String deviceId,
    List<String> regions,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final normalized =
          regions
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      await prefs.setStringList(
        '$_keyKnownRegionsV1Prefix${sanitizeId(deviceId)}',
        normalized,
      );
    } catch (_) {}
  }

  Future<List<String>> loadKnownRegionsForRadio(String deviceId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw =
          prefs.getStringList(
            '$_keyKnownRegionsV1Prefix${sanitizeId(deviceId)}',
          ) ??
          const <String>[];
      final out =
          raw.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList()
            ..sort();
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveDefaultFloodScopeForRadio(
    String deviceId,
    String? scopeName,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_keyDefaultFloodScopeV1Prefix${sanitizeId(deviceId)}';
      final trimmed = scopeName?.trim() ?? '';
      if (trimmed.isEmpty) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, trimmed);
      }
    } catch (_) {}
  }

  Future<String?> loadDefaultFloodScopeForRadio(String deviceId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_keyDefaultFloodScopeV1Prefix${sanitizeId(deviceId)}';
      final raw = prefs.getString(key)?.trim();
      if (raw == null || raw.isEmpty) return null;
      return raw;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Notification settings
  // ---------------------------------------------------------------------------

  static const _keyNotificationSettings = 'notification_settings_v1';
  static const _keyFavorites = 'favorites_v1';

  Future<void> saveNotificationSettings(NotificationSettings settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _keyNotificationSettings,
        jsonEncode(settings.toJson()),
      );
    } catch (_) {}
  }

  Future<NotificationSettings> loadNotificationSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyNotificationSettings);
      if (raw == null) return const NotificationSettings();
      return NotificationSettings.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return const NotificationSettings();
    }
  }

  // ---------------------------------------------------------------------------
  // Plan 3-3-3 settings + QSL log
  //
  // These live in the database, not SharedPreferences. Users reported their
  // Plan 3-3-3 station config coming back empty after closing and reopening the
  // app: prefs rewrites its entire file on every write, so a write interrupted
  // by the OS killing the app can take unrelated keys down with it, and the
  // whole file is lost as one unit. A row write here is committed by SQLite
  // before the call returns.
  //
  // The key strings are unchanged so [migratePlan333Settings] is a plain copy.
  // ---------------------------------------------------------------------------

  static const _keyPlan333Enabled = 'plan333_enabled';
  static const _keyPlan333Config = 'plan333_config';
  static const _keyPlan333AutoSendState = 'plan333_auto_send_state';
  static const _keyQslLog = 'plan333_qsl_log';
  static const _keyQslLogSessionStart = 'plan333_qsl_log_session_start';

  /// Every Plan 3-3-3 key, in the order [migratePlan333Settings] moves them.
  static const List<String> plan333SettingKeys = [
    _keyPlan333Enabled,
    _keyPlan333Config,
    _keyPlan333AutoSendState,
    _keyQslLog,
    _keyQslLogSessionStart,
  ];

  Future<void> savePlan333Enabled(bool enabled) async {
    try {
      await settings.setBool(_keyPlan333Enabled, value: enabled);
    } catch (_) {}
  }

  Future<bool> loadPlan333Enabled() async {
    try {
      return await settings.getBool(_keyPlan333Enabled) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Stores Plan333Config as a raw JSON string (caller handles encoding).
  Future<void> savePlan333Config(String json) async {
    try {
      await settings.setString(_keyPlan333Config, json);
    } catch (_) {}
  }

  /// Returns the stored Plan333Config JSON string, or null if not set.
  Future<String?> loadPlan333Config() async {
    try {
      return await settings.getString(_keyPlan333Config);
    } catch (_) {
      return null;
    }
  }

  /// Stores Plan333AutoSendState as a raw JSON string (caller handles encoding).
  Future<void> savePlan333AutoSendState(String json) async {
    try {
      await settings.setString(_keyPlan333AutoSendState, json);
    } catch (_) {}
  }

  /// Returns the stored Plan333AutoSendState JSON string, or null if not set.
  Future<String?> loadPlan333AutoSendState() async {
    try {
      return await settings.getString(_keyPlan333AutoSendState);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveQslLog(String json) async {
    try {
      await settings.setString(_keyQslLog, json);
    } catch (_) {}
  }

  Future<String?> loadQslLog() async {
    try {
      return await settings.getString(_keyQslLog);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveQslLogSessionStart(int? epochMillis) async {
    try {
      if (epochMillis == null) {
        await settings.remove(_keyQslLogSessionStart);
      } else {
        await settings.setInt(_keyQslLogSessionStart, epochMillis);
      }
    } catch (_) {}
  }

  Future<int?> loadQslLogSessionStart() async {
    try {
      return await settings.getInt(_keyQslLogSessionStart);
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // One-time move of Plan 3-3-3 settings out of SharedPreferences
  // ---------------------------------------------------------------------------

  static const _keyPlan333SettingsMigrated = 'plan333_settings_migrated_v1';

  /// Copy any Plan 3-3-3 keys still sitting in SharedPreferences into the
  /// database, then delete the prefs originals.
  ///
  /// The done-flag lives in the database, not in prefs: a prefs-side flag would
  /// be lost by exactly the failure this migration exists to escape, and the
  /// migration would then re-run against keys it had already deleted.
  ///
  /// A key is only copied when the database has no value for it, so a partial
  /// run is safe to repeat and can never overwrite newer data. Each prefs key
  /// is removed only after its value is confirmed readable from the database.
  ///
  /// Returns the number of keys actually moved.
  Future<int> migratePlan333Settings() async {
    try {
      if (await settings.getBool(_keyPlan333SettingsMigrated) ?? false) {
        return 0;
      }
    } catch (_) {
      // Database unreadable — leave the prefs values where they are.
      return 0;
    }

    final SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      return 0;
    }

    var moved = 0;
    var failed = 0;
    for (final key in plan333SettingKeys) {
      try {
        final legacy = prefs.get(key);
        if (legacy == null) continue;

        // Never clobber a value already written through the new path.
        if (await settings.getString(key) == null) {
          if (legacy is bool) {
            await settings.setBool(key, value: legacy);
          } else if (legacy is int) {
            await settings.setInt(key, legacy);
          } else {
            await settings.setString(key, legacy.toString());
          }
          // Confirm the row landed before dropping the only other copy.
          if (await settings.getString(key) == null) {
            failed++;
            continue;
          }
          moved++;
        }
        await prefs.remove(key);
      } catch (_) {
        failed++;
      }
    }

    // Only close the door once every key made it across; otherwise the next
    // launch retries the ones that did not.
    if (failed == 0) {
      try {
        await settings.setBool(_keyPlan333SettingsMigrated, value: true);
      } catch (_) {}
    }

    return moved;
  }

  // ---------------------------------------------------------------------------
  // Favorites — legacy app-local set. Superseded by the radio's contact
  // `flags` byte (bit 0). These helpers remain only for one-shot migration
  // of pre-fix data; see `_migrateLegacyFavorites` in radio_providers.dart.
  // ---------------------------------------------------------------------------

  /// Reads the legacy app-local favourites set (hex public keys). Returns an
  /// empty set after migration has run.
  Future<Set<String>> loadFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyFavorites);
      if (raw == null) return {};
      final list = jsonDecode(raw) as List<dynamic>;
      return list.cast<String>().toSet();
    } catch (_) {
      return {};
    }
  }

  /// Removes the legacy favourites key once migration has pushed the bits
  /// to the radio.
  Future<void> clearFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyFavorites);
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Message paths  (packetHashHex → list of MessagePath)
  // ---------------------------------------------------------------------------

  static const _keyMessagePaths = 'msg_paths_v1';
  static const int _maxPathsPerHash = 10;

  /// Append one packet reception — one row, no rewrite of anything else.
  Future<void> appendPacketPath(String hashHex, MessagePath path) async {
    try {
      await packetPaths.append(hashHex, path);
    } catch (_) {}
  }

  Future<void> saveMessagePaths(Map<String, List<MessagePath>> paths) async {
    try {
      final capped = <String, List<MessagePath>>{
        for (final entry in paths.entries)
          entry.key:
              entry.value.length > _maxPathsPerHash
                  ? entry.value.sublist(entry.value.length - _maxPathsPerHash)
                  : entry.value,
      };
      await packetPaths.replaceAll(capped);
    } catch (_) {}
  }

  Future<Map<String, List<MessagePath>>> loadMessagePaths() async {
    try {
      return await packetPaths.loadAll();
    } catch (_) {
      return {};
    }
  }

  /// Drop all but the [maxPacketPathHashes] most recently heard packet hashes.
  Future<void> prunePacketPaths() async {
    try {
      await packetPaths.pruneToHashLimit(keepHashes: maxPacketPathHashes);
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Private key backup  (keyed by first 6 hex chars of radio public key)
  // ---------------------------------------------------------------------------

  static String _prvKeyBackupStorageKey(String pubKeyHex6) =>
      'prv_key_bkp_$pubKeyHex6';

  /// Persist [prvKeyHex] (128-char hex = 64 raw bytes) for the radio identified
  /// by [pubKeyHex6] (first 6 hex bytes of the public key).
  Future<void> savePrivateKeyBackup(String pubKeyHex6, String prvKeyHex) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prvKeyBackupStorageKey(pubKeyHex6), prvKeyHex);
    } catch (_) {}
  }

  /// Returns the stored 128-char hex private key for [pubKeyHex6], or null.
  Future<String?> loadPrivateKeyBackup(String pubKeyHex6) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_prvKeyBackupStorageKey(pubKeyHex6));
    } catch (_) {
      return null;
    }
  }

  /// Remove the private key backup for [pubKeyHex6].
  Future<void> clearPrivateKeyBackup(String pubKeyHex6) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prvKeyBackupStorageKey(pubKeyHex6));
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // One-time migration of bulk data out of SharedPreferences
  // ---------------------------------------------------------------------------

  static const _keyStorageMigrated = 'storage_migrated_v1';

  /// Move messages, contacts and packet paths from the old JSON-in-prefs
  /// representation into the database, then delete the old keys.
  ///
  /// Deleting them is the point: they are what made the preferences file grow
  /// to megabytes, and that file is read in full at every launch.
  ///
  /// Safe to call on every start — it no-ops once the flag is set. Each key is
  /// migrated independently, and a key is only removed once its rows are
  /// confirmed present, so a failure part-way leaves the remaining originals
  /// intact for the next launch to retry.
  Future<StorageMigrationResult> migrateFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_keyStorageMigrated) ?? false) {
      return const StorageMigrationResult.alreadyDone();
    }

    var conversations = 0;
    var migratedMessages = 0;
    var migratedContacts = 0;
    var migratedPathHashes = 0;
    final failures = <String>[];

    // -- Messages: one prefs key per conversation ----------------------------
    final messageKeys =
        prefs
            .getKeys()
            .where((k) => k.startsWith(_legacyMessagesPrefix))
            .toList();
    for (final prefsKey in messageKeys) {
      final convKey = prefsKey.substring(_legacyMessagesPrefix.length);
      try {
        final raw = prefs.getString(prefsKey);
        if (raw == null) {
          await prefs.remove(prefsKey);
          continue;
        }
        final decoded =
            (jsonDecode(raw) as List<dynamic>)
                .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
                .toList();
        if (decoded.isEmpty) {
          await prefs.remove(prefsKey);
          continue;
        }
        final tail =
            decoded.length > maxMessagesPerKey
                ? decoded.sublist(decoded.length - maxMessagesPerKey)
                : decoded;
        await messages.replaceAll(convKey, tail);

        // Only drop the original once the rows are actually queryable.
        final stored = await messages.load(convKey, limit: maxMessagesPerKey);
        if (stored.isEmpty) {
          failures.add(prefsKey);
          continue;
        }
        await prefs.remove(prefsKey);
        conversations++;
        migratedMessages += stored.length;
      } catch (_) {
        // Leave this key in place; the next launch retries it.
        failures.add(prefsKey);
      }
    }

    // -- Contacts ------------------------------------------------------------
    try {
      final raw = prefs.getString(_keyContacts);
      if (raw != null) {
        final decoded =
            (jsonDecode(raw) as List<dynamic>)
                .map((e) => Contact.fromJson(e as Map<String, dynamic>))
                .toList();
        if (decoded.isEmpty) {
          await prefs.remove(_keyContacts);
        } else {
          await contacts.replaceAll(decoded);
          if (await contacts.count() > 0) {
            await prefs.remove(_keyContacts);
            migratedContacts = decoded.length;
          } else {
            failures.add(_keyContacts);
          }
        }
      }
    } catch (_) {
      failures.add(_keyContacts);
    }

    // -- Packet paths --------------------------------------------------------
    try {
      final raw = prefs.getString(_keyMessagePaths);
      if (raw != null) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        if (map.isEmpty) {
          await prefs.remove(_keyMessagePaths);
        } else {
          final decoded = <String, List<MessagePath>>{
            for (final entry in map.entries)
              entry.key:
                  (entry.value as List<dynamic>)
                      .map(
                        (e) => MessagePath.fromJson(e as Map<String, dynamic>),
                      )
                      .toList(),
          };
          await packetPaths.replaceAll(decoded);
          await prunePacketPaths();
          if (await packetPaths.distinctHashCount() > 0) {
            await prefs.remove(_keyMessagePaths);
            migratedPathHashes = decoded.length;
          } else {
            failures.add(_keyMessagePaths);
          }
        }
      }
    } catch (_) {
      failures.add(_keyMessagePaths);
    }

    // Only declare victory when nothing was left behind, so a partial run is
    // retried rather than silently stranding data in prefs.
    if (failures.isEmpty) {
      await prefs.setBool(_keyStorageMigrated, true);
    }

    return StorageMigrationResult(
      conversations: conversations,
      messages: migratedMessages,
      contacts: migratedContacts,
      packetPathHashes: migratedPathHashes,
      failedKeys: failures,
      completed: failures.isEmpty,
    );
  }
}

/// Outcome of [StorageService.migrateFromPrefs], for logging and tests.
class StorageMigrationResult {
  const StorageMigrationResult({
    required this.conversations,
    required this.messages,
    required this.contacts,
    required this.packetPathHashes,
    required this.failedKeys,
    required this.completed,
  });

  const StorageMigrationResult.alreadyDone()
    : conversations = 0,
      messages = 0,
      contacts = 0,
      packetPathHashes = 0,
      failedKeys = const [],
      completed = true;

  final int conversations;
  final int messages;
  final int contacts;
  final int packetPathHashes;

  /// Prefs keys that could not be migrated and were deliberately left in place.
  final List<String> failedKeys;

  /// True when every key was migrated and the done-flag was set.
  final bool completed;

  /// True when this run actually moved something.
  bool get didWork => conversations > 0 || contacts > 0 || packetPathHashes > 0;

  @override
  String toString() =>
      'StorageMigrationResult(conversations: $conversations, '
      'messages: $messages, contacts: $contacts, '
      'packetPathHashes: $packetPathHashes, '
      'failed: ${failedKeys.length}, completed: $completed)';
}

// ---------------------------------------------------------------------------
// Notification settings model
// ---------------------------------------------------------------------------

/// User-configurable notification preferences.
class NotificationSettings {
  factory NotificationSettings.fromJson(Map<String, dynamic> json) =>
      NotificationSettings(
        enabled: (json['enabled'] as bool?) ?? true,
        privateMessages: (json['private_messages'] as bool?) ?? true,
        channelMessages: (json['channel_messages'] as bool?) ?? true,
        onlyWhenBackground: (json['only_when_background'] as bool?) ?? false,
        channelMentionsOnly: (json['channel_mentions_only'] as bool?) ?? false,
      );
  const NotificationSettings({
    this.enabled = true,
    this.privateMessages = true,
    this.channelMessages = true,
    this.onlyWhenBackground = false,
    this.channelMentionsOnly = false,
  });

  /// Master switch — disables all notifications when false.
  final bool enabled;

  /// Notify on incoming private messages.
  final bool privateMessages;

  /// Notify on incoming channel messages.
  final bool channelMessages;

  /// Only fire notifications when the app is in the background.
  final bool onlyWhenBackground;

  /// When true, only notify for channel messages that mention the user.
  final bool channelMentionsOnly;

  NotificationSettings copyWith({
    bool? enabled,
    bool? privateMessages,
    bool? channelMessages,
    bool? onlyWhenBackground,
    bool? channelMentionsOnly,
  }) {
    return NotificationSettings(
      enabled: enabled ?? this.enabled,
      privateMessages: privateMessages ?? this.privateMessages,
      channelMessages: channelMessages ?? this.channelMessages,
      onlyWhenBackground: onlyWhenBackground ?? this.onlyWhenBackground,
      channelMentionsOnly: channelMentionsOnly ?? this.channelMentionsOnly,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'private_messages': privateMessages,
    'channel_messages': channelMessages,
    'only_when_background': onlyWhenBackground,
    'channel_mentions_only': channelMentionsOnly,
  };
}

/// Describes the last device that was successfully connected.
class LastDevice {
  const LastDevice({required this.id, required this.type, required this.name});

  /// Platform device ID (BLE deviceId or serial port path).
  final String id;

  /// Transport kind: 'ble', 'serialCompanion', 'serialKiss'.
  final String type;

  /// Human-readable display name.
  final String name;
}
