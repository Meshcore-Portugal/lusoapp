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
  // Favorites (app-side, not stored on radio)
  // ---------------------------------------------------------------------------

  Future<void> saveFavorites(Set<String> keyHexSet) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyFavorites, jsonEncode(keyHexSet.toList()));
    } catch (_) {}
  }

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
