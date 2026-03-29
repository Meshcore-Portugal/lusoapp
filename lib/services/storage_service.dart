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
  static const int maxMessagesPerKey = 500;

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
