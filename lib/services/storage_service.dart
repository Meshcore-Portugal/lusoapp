import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../protocol/models.dart';

/// Persistent storage for messages, contacts, and device settings.
///
/// Uses [SharedPreferences] so it works on all platforms including web.
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

  static String _messagesKey(String key) => 'msgs_v1_$key';

  // ---------------------------------------------------------------------------
  // Last connected device
  // ---------------------------------------------------------------------------

  Future<void> saveLastDevice({
    required String id,
    required String type,
    required String name,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastDeviceId, id);
    await prefs.setString(_keyLastDeviceType, type);
    await prefs.setString(_keyLastDeviceName, name);
  }

  /// Returns `null` when no device has been saved yet.
  Future<LastDevice?> loadLastDevice() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_keyLastDeviceId);
    final type = prefs.getString(_keyLastDeviceType);
    final name = prefs.getString(_keyLastDeviceName);
    if (id == null || type == null) return null;
    return LastDevice(id: id, type: type, name: name ?? id);
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
      // Keep legacy keys in sync so loadLastDevice() still works.
      await prefs.setString(_keyLastDeviceId, id);
      await prefs.setString(_keyLastDeviceType, type);
      await prefs.setString(_keyLastDeviceName, name);
      // Prepend, dedup by id, cap.
      final existing = _parseRecentDevices(prefs);
      final updated =
          [
            LastDevice(id: id, type: type, name: name),
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
      return [LastDevice(id: id, type: type, name: name)];
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
      final seeded = [LastDevice(id: id, type: type, name: name ?? id)];
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
              name: e['name'] as String,
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

  Future<void> saveMessages(String key, List<ChatMessage> messages) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tail =
          messages.length > maxMessagesPerKey
              ? messages.sublist(messages.length - maxMessagesPerKey)
              : messages;
      final json = jsonEncode(tail.map((m) => m.toJson()).toList());
      await prefs.setString(_messagesKey(key), json);
    } catch (_) {
      // Storage errors are non-fatal — messages still live in memory.
    }
  }

  Future<List<ChatMessage>> loadMessages(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_messagesKey(key));
      if (json == null) return [];
      final list = jsonDecode(json) as List<dynamic>;
      return list
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> clearMessages(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_messagesKey(key));
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Contacts
  // ---------------------------------------------------------------------------

  Future<void> saveContacts(List<Contact> contacts) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(contacts.map((c) => c.toJson()).toList());
      await prefs.setString(_keyContacts, json);
    } catch (_) {}
  }

  Future<List<Contact>> loadContacts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_keyContacts);
      if (json == null) return [];
      final list = jsonDecode(json) as List<dynamic>;
      return list
          .map((e) => Contact.fromJson(e as Map<String, dynamic>))
          .toList();
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
  // Plan 3-3-3 settings
  // ---------------------------------------------------------------------------

  static const _keyPlan333Enabled = 'plan333_enabled';
  static const _keyPlan333Config = 'plan333_config';

  Future<void> savePlan333Enabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyPlan333Enabled, enabled);
    } catch (_) {}
  }

  Future<bool> loadPlan333Enabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyPlan333Enabled) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Stores Plan333Config as a raw JSON string (caller handles encoding).
  Future<void> savePlan333Config(String json) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyPlan333Config, json);
    } catch (_) {}
  }

  /// Returns the stored Plan333Config JSON string, or null if not set.
  Future<String?> loadPlan333Config() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyPlan333Config);
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // QSL log
  // ---------------------------------------------------------------------------

  static const _keyQslLog = 'plan333_qsl_log';

  Future<void> saveQslLog(String json) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyQslLog, json);
    } catch (_) {}
  }

  Future<String?> loadQslLog() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyQslLog);
    } catch (_) {
      return null;
    }
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

  Future<void> saveMessagePaths(Map<String, List<MessagePath>> paths) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = <String, dynamic>{};
      for (final entry in paths.entries) {
        final list = entry.value;
        final tail =
            list.length > _maxPathsPerHash
                ? list.sublist(list.length - _maxPathsPerHash)
                : list;
        map[entry.key] = tail.map((p) => p.toJson()).toList();
      }
      await prefs.setString(_keyMessagePaths, jsonEncode(map));
    } catch (_) {}
  }

  Future<Map<String, List<MessagePath>>> loadMessagePaths() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyMessagePaths);
      if (raw == null) return {};
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final entry in map.entries)
          entry.key:
              (entry.value as List<dynamic>)
                  .map((e) => MessagePath.fromJson(e as Map<String, dynamic>))
                  .toList(),
      };
    } catch (_) {
      return {};
    }
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
      );
  const NotificationSettings({
    this.enabled = true,
    this.privateMessages = true,
    this.channelMessages = true,
    this.onlyWhenBackground = false,
  });

  /// Master switch — disables all notifications when false.
  final bool enabled;

  /// Notify on incoming private messages.
  final bool privateMessages;

  /// Notify on incoming channel messages.
  final bool channelMessages;

  /// Only fire notifications when the app is in the background.
  final bool onlyWhenBackground;

  NotificationSettings copyWith({
    bool? enabled,
    bool? privateMessages,
    bool? channelMessages,
    bool? onlyWhenBackground,
  }) {
    return NotificationSettings(
      enabled: enabled ?? this.enabled,
      privateMessages: privateMessages ?? this.privateMessages,
      channelMessages: channelMessages ?? this.channelMessages,
      onlyWhenBackground: onlyWhenBackground ?? this.onlyWhenBackground,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'private_messages': privateMessages,
    'channel_messages': channelMessages,
    'only_when_background': onlyWhenBackground,
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
