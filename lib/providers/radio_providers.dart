import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart' show Color, ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../protocol/cayenne_lpp.dart';
import '../protocol/protocol.dart';
import '../services/notification_service.dart';
import '../services/plan333_service.dart';
import '../services/radio_service.dart';
import '../services/storage_service.dart';
import '../services/widget_service.dart';
import '../transport/transport.dart';

part 'parts/connection_notifier.dart';
part 'parts/messages_notifier.dart';
part 'parts/advert_auto_add.dart';

/// Returns the 64-char hex string of the first 32 bytes of a public key.
/// Used as a stable map key for comparing contact identity across providers.
String _keyHex(Uint8List key) =>
    key.take(32).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

// ---------------------------------------------------------------------------
// Transport state
// ---------------------------------------------------------------------------

final transportStateProvider = StateProvider<TransportState>(
  (_) => TransportState.disconnected,
);

// ---------------------------------------------------------------------------
// Connection progress (step label + step index 0-5)
// ---------------------------------------------------------------------------

final connectionStepProvider = StateProvider<String>((_) => '');
final connectionProgressProvider = StateProvider<int>((_) => 0);

// ---------------------------------------------------------------------------
// Radio service — the central singleton managing the connection
// ---------------------------------------------------------------------------

final radioServiceProvider = StateProvider<RadioService?>((_) => null);

/// Snapshot of the public-key hex-strings of contacts confirmed to be stored
/// on the radio at the last explicit sync (initial connect or contact deletion).
/// Used by [discoveredContactsProvider] so that background path-update refreshes
/// don't falsely hide contacts from the discover screen.
final radioContactsSnapshotProvider = StateProvider<Set<String>>((_) => {});

/// True once the first [EndContactsResponse] has been received after the
/// current connection was established.  Reset to false on every new connect
/// attempt and on disconnect.  Used by the contacts screen to distinguish
/// "no contacts on this radio" (synced, empty snapshot) from "not yet synced"
/// (should fall back to the local cache).
final contactsSyncedProvider = StateProvider<bool>((_) => false);

// ---------------------------------------------------------------------------
// Current radio device ID — set when a connection is established, cleared
// on disconnect. Used to scope channel and message storage per radio so
// that data from different radios never bleeds into each other.
// ---------------------------------------------------------------------------

final currentRadioIdProvider = StateProvider<String?>((_) => null);

// ---------------------------------------------------------------------------
// Last connected device (loaded on app start from SharedPreferences)
// ---------------------------------------------------------------------------

final lastDeviceProvider = StateProvider<LastDevice?>((_) => null);

/// All recently connected devices, most-recent first (up to 5).
/// Superset of [lastDeviceProvider]; used by the connect screen to let
/// users with multiple radios reconnect without scanning.
final recentDevicesProvider = StateProvider<List<LastDevice>>((_) => []);

// ---------------------------------------------------------------------------
// Data providers
// ---------------------------------------------------------------------------

final selfInfoProvider = StateProvider<SelfInfo?>((_) => null);
final radioConfigProvider = StateProvider<RadioConfig?>((_) => null);
final deviceInfoProvider = StateProvider<DeviceInfo?>((_) => null);
final batteryProvider = StateProvider<int>((_) => 0);

/// (storageUsed, storageTotal) in bytes; both null until first RESP_BATT_AND_STORAGE.
final storageProvider = StateProvider<(int?, int?)>((_) => (null, null));

// Contacts
class ContactsNotifier extends StateNotifier<List<Contact>> {
  ContactsNotifier() : super([]);
  bool _loaded = false;

  // Internal index: hex6 of first 6 bytes → (list index, Contact).
  // Kept in sync on every state write so upsertFromAdvert / touchLastHeard
  // are O(1) lookups instead of O(n) scans.
  final Map<String, (int, Contact)> _byHex6 = {};

  // Debounce timer for saves triggered by high-frequency events (adverts,
  // incoming messages).  User-triggered mutations (setCustomName, remove, …)
  // still save immediately.
  Timer? _saveDebounce;

  @override
  void dispose() {
    _saveDebounce?.cancel();
    super.dispose();
  }

  void _rebuildIndex(List<Contact> contacts) {
    _byHex6.clear();
    for (var i = 0; i < contacts.length; i++) {
      final c = contacts[i];
      if (c.publicKey.length >= 6) {
        _byHex6[_hex6(c.publicKey)] = (i, c);
      }
    }
  }

  void _scheduleSave(List<Contact> contacts) {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(seconds: 2), () {
      StorageService.instance.saveContacts(contacts);
    });
  }

  /// O(1) contact lookup by 6-byte key prefix hex (used by notification handler).
  Contact? lookupByHex6(String hex6) => _byHex6[hex6]?.$2;

  /// Load cached contacts from storage (called once on app start).
  Future<void> loadFromStorage() async {
    if (_loaded) return;
    _loaded = true;
    final stored = await StorageService.instance.loadContacts();
    if (stored.isNotEmpty) {
      state = stored;
      _rebuildIndex(stored);
    }
  }

  void refresh(List<Contact> contacts) {
    // Build O(1) lookup map from current cache so the merge is O(n) not O(n²).
    final currentByKeyHex = <String, Contact>{
      for (final c in state) _keyHex(c.publicKey): c,
    };
    // Also track which full-key hexes came from the radio for the
    // preserve-local-only pass below.
    final radioKeys = <String>{};

    final merged =
        contacts.map((incoming) {
          final kh = _keyHex(incoming.publicKey);
          radioKeys.add(kh);
          final existing = currentByKeyHex[kh];
          // No local cache hit — nothing to preserve.
          if (existing == null) return incoming;
          var out =
              existing.customName != null
                  ? incoming.withCustomName(existing.customName)
                  : incoming;
          // Preserve the most recent advert timestamp seen locally.
          if (existing.lastAdvertTimestamp > out.lastAdvertTimestamp) {
            out = Contact(
              publicKey: out.publicKey,
              type: out.type,
              flags: out.flags,
              pathLen: out.pathLen,
              name: out.name,
              lastAdvertTimestamp: existing.lastAdvertTimestamp,
              latitude: out.latitude,
              longitude: out.longitude,
              lastModified: out.lastModified,
              customName: out.customName,
            );
          }
          return out;
        }).toList();

    // Preserve locally-cached contacts that are not in the radio's list.
    // These are contacts received via AdvertPush (heard on the mesh) but not
    // yet formally stored in the radio's contacts table.  Dropping them on
    // every refresh causes the node to "disappear" after an app restart.
    for (final local in state) {
      if (!radioKeys.contains(_keyHex(local.publicKey))) {
        merged.add(local);
      }
    }

    state = merged;
    _rebuildIndex(merged);
    StorageService.instance.saveContacts(merged);
  }

  void setCustomName(Uint8List publicKey, String? customName) {
    final next =
        state
            .map(
              (c) =>
                  _keysEqual(c.publicKey, publicKey)
                      ? c.withCustomName(customName)
                      : c,
            )
            .toList();
    state = next;
    _rebuildIndex(next);
    StorageService.instance.saveContacts(next);
  }

  /// Optimistically flips the favourite bit on the cached contact and saves
  /// storage. Callers are expected to push the updated contact to the radio
  /// via [RadioService.addUpdateContact] so the change persists across
  /// disconnects and reaches other apps connected to the same radio.
  void setFavorite(Uint8List publicKey, bool value) {
    final next =
        state
            .map(
              (c) =>
                  _keysEqual(c.publicKey, publicKey)
                      ? c.withFavorite(value)
                      : c,
            )
            .toList();
    state = next;
    _rebuildIndex(next);
    StorageService.instance.saveContacts(next);
  }

  void remove(Uint8List publicKey) {
    final next =
        state.where((c) => !_keysEqual(c.publicKey, publicKey)).toList();
    state = next;
    _rebuildIndex(next);
    StorageService.instance.saveContacts(next);
  }

  /// Update lastModified on the contact matched by the 6-byte key prefix.
  /// Called on every incoming private message and every 0x88 advert frame.
  /// Uses the O(1) hex6 index so it never scans the list.
  /// Save is debounced — high-frequency adverts coalesce into one write.
  void touchLastHeard(Uint8List senderKey) {
    if (senderKey.length < 6) return;
    final hex6 = _hex6(senderKey);
    final entry = _byHex6[hex6];
    if (entry == null) return;
    final (idx, existing) = entry;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final next = [...state];
    next[idx] = Contact(
      publicKey: existing.publicKey,
      type: existing.type,
      flags: existing.flags,
      pathLen: existing.pathLen,
      name: existing.name,
      lastAdvertTimestamp: existing.lastAdvertTimestamp,
      latitude: existing.latitude,
      longitude: existing.longitude,
      lastModified: now,
      customName: existing.customName,
    );
    state = next;
    _rebuildIndex(next);
    _scheduleSave(next);
  }

  /// Adds a new contact if unseen, or refreshes the name/type/timestamp if already known.
  /// Uses the O(1) hex6 index and debounces the storage write.
  void upsertFromAdvert(Uint8List publicKey, int type, String name) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final hex6 = _hex6(publicKey);
    final entry = _byHex6[hex6];
    List<Contact> next;
    if (entry != null) {
      final (idx, existing) = entry;
      next = [...state];
      next[idx] = Contact(
        publicKey: existing.publicKey,
        // Preserve the known type if the advert carries type=0 (unknown).
        // Firmware pushAdvert (0x80) can omit the type for path-update adverts.
        type: type != 0 ? type : existing.type,
        flags: existing.flags,
        pathLen: existing.pathLen,
        name: name.isNotEmpty ? name : existing.name,
        lastAdvertTimestamp: now,
        latitude: existing.latitude,
        longitude: existing.longitude,
        // Update lastModified so _bestTs() reflects the live reception time.
        // Without this, _bestTs prefers the old lastModified and "Visto" never changes.
        lastModified: now,
        customName: existing.customName,
      );
    } else {
      // Don't create a nameless contact — an advert without a name is a
      // path-update ping for a node we haven't met yet; ignore it until
      // a proper advert with a name arrives.
      if (name.isEmpty) return;
      next = [
        ...state,
        Contact(
          publicKey: publicKey,
          type: type,
          flags: 0,
          pathLen: 0,
          name: name,
          lastAdvertTimestamp: now,
        ),
      ];
    }
    state = next;
    _rebuildIndex(next);
    _scheduleSave(next);
  }

  static bool _keysEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

final contactsProvider = StateNotifierProvider<ContactsNotifier, List<Contact>>(
  (ref) {
    return ContactsNotifier();
  },
);

// Channels
class ChannelsNotifier extends StateNotifier<List<ChannelInfo>> {
  ChannelsNotifier(this._ref) : super([]);
  final Ref _ref;

  /// Load channels for the last known device at startup (offline cache).
  /// Only populates state if there is data — does not clear existing state.
  Future<void> loadFromStorage() async {
    final stored = await StorageService.instance.loadChannels();
    if (stored.isNotEmpty) {
      state = List.from(stored)..sort((a, b) => a.index.compareTo(b.index));
    }
  }

  /// Load channels scoped to a specific radio device.
  /// Replaces any previously loaded channels in state.
  Future<void> loadFromStorageForRadio(String deviceId) async {
    final stored = await StorageService.instance.loadChannelsForRadio(deviceId);
    state = List.from(stored)..sort((a, b) => a.index.compareTo(b.index));
  }

  /// Clear in-memory channels without touching storage.
  /// Called when switching to a different radio before the new radio's
  /// channels have been fetched, to prevent stale data showing in the UI.
  void clearChannels() {
    state = [];
  }

  void refresh(List<ChannelInfo> channels) {
    state = List.from(channels)..sort((a, b) => a.index.compareTo(b.index));
    final deviceId = _ref.read(currentRadioIdProvider);
    if (deviceId != null) {
      StorageService.instance.saveChannelsForRadio(deviceId, state);
    } else {
      StorageService.instance.saveChannels(state);
    }
  }
}

final channelsProvider =
    StateNotifierProvider<ChannelsNotifier, List<ChannelInfo>>((ref) {
      return ChannelsNotifier(ref);
    });

// Per-key message version counters: key → bump count.
// Incremented each time any message for that key is added/updated.
// Keys follow the same scheme as MessagesNotifier._partitionKey:
//   'c_<hex6>'  for private contacts
//   'ch_<idx>'  for channels
// Screens watch this with .select((vs) => vs[key] ?? 0) to rebuild only
// when their specific conversation changes, not on every message app-wide.
final messageVersionsProvider = StateProvider<Map<String, int>>(
  (_) => const {},
);

// Stable snapshot of (contact hex6 → last private message timestamp).
// Uses custom equality so that a channel message arriving does NOT cause
// contacts_screen to rebuild; only actual private-message ts changes do.
class _MsgTsSnapshot {
  const _MsgTsSnapshot(this.data);
  final Map<String, int> data;

  @override
  bool operator ==(Object other) {
    if (other is! _MsgTsSnapshot) return false;
    if (data.length != other.data.length) return false;
    for (final e in data.entries) {
      if (other.data[e.key] != e.value) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hashAll(data.entries.map((e) => Object.hash(e.key, e.value)));
}

final contactLastMsgTsProvider = Provider<Map<String, int>>((ref) {
  return ref
      .watch(
        messagesProvider.select((msgs) {
          final result = <String, int>{};
          for (final m in msgs) {
            if (m.senderKey != null &&
                m.senderKey!.length >= 6 &&
                m.channelIndex == null) {
              final k = _hex6(m.senderKey!);
              if (m.timestamp > (result[k] ?? 0)) result[k] = m.timestamp;
            }
          }
          return _MsgTsSnapshot(result);
        }),
      )
      .data;
});

// ---------------------------------------------------------------------------
// Unread message counts
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Muted channels
// ---------------------------------------------------------------------------

class MutedChannelsNotifier extends StateNotifier<Set<int>> {
  MutedChannelsNotifier() : super({}) {
    _load();
  }

  static const _key = 'muted_channels_v1';
  String? _activeDeviceId;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    state = list.map(int.parse).toSet();
  }

  /// Load muted channels scoped to a specific radio device.
  /// Replaces the current mute set with the device-specific one.
  Future<void> loadForRadio(String deviceId) async {
    _activeDeviceId = deviceId;
    state = await StorageService.instance.loadMutedChannelsForRadio(deviceId);
  }

  Future<void> toggle(int channelIndex) async {
    final next = Set<int>.from(state);
    if (next.contains(channelIndex)) {
      next.remove(channelIndex);
    } else {
      next.add(channelIndex);
    }
    state = next;
    await _save();
  }

  Future<void> _save() async {
    if (_activeDeviceId != null) {
      await StorageService.instance.saveMutedChannelsForRadio(
        _activeDeviceId!,
        state,
      );
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, state.map((i) => '$i').toList());
    }
  }
}

final mutedChannelsProvider =
    StateNotifierProvider<MutedChannelsNotifier, Set<int>>(
      (ref) => MutedChannelsNotifier(),
    );

// ---------------------------------------------------------------------------
/// Immutable snapshot of unread counts per channel and per contact.
class UnreadCounts {
  const UnreadCounts({this.channels = const {}, this.contacts = const {}});

  /// channelIndex → unread count
  final Map<int, int> channels;

  /// 6-byte sender key hex → unread count
  final Map<String, int> contacts;

  int get totalChannels => channels.values.fold(0, (a, b) => a + b);
  int get totalContacts => contacts.values.fold(0, (a, b) => a + b);
  int forChannel(int i) => channels[i] ?? 0;
  int forContact(String hex6) => contacts[hex6] ?? 0;
}

class UnreadCountsNotifier extends StateNotifier<UnreadCounts> {
  UnreadCountsNotifier() : super(const UnreadCounts());

  static const _chKey = 'unread_channels_v1';
  static const _coKey = 'unread_contacts_v1';

  Future<void> loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final chRaw = prefs.getString(_chKey);
    final coRaw = prefs.getString(_coKey);
    Map<int, int> ch = {};
    Map<String, int> co = {};
    if (chRaw != null) {
      for (final part in chRaw.split(',')) {
        final kv = part.split(':');
        if (kv.length == 2) {
          final k = int.tryParse(kv[0]);
          final v = int.tryParse(kv[1]);
          if (k != null && v != null && v > 0) ch[k] = v;
        }
      }
    }
    if (coRaw != null) {
      for (final part in coRaw.split(',')) {
        final kv = part.split(':');
        if (kv.length == 2 && kv[0].isNotEmpty) {
          final v = int.tryParse(kv[1]);
          if (v != null && v > 0) co[kv[0]] = v;
        }
      }
    }
    state = UnreadCounts(channels: ch, contacts: co);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _chKey,
      state.channels.entries.map((e) => '${e.key}:${e.value}').join(','),
    );
    await prefs.setString(
      _coKey,
      state.contacts.entries.map((e) => '${e.key}:${e.value}').join(','),
    );
  }

  void incrementChannel(int index) {
    final ch = Map<int, int>.from(state.channels)
      ..[index] = (state.channels[index] ?? 0) + 1;
    state = UnreadCounts(channels: ch, contacts: state.contacts);
    _save();
  }

  void incrementContact(String hex6) {
    final co = Map<String, int>.from(state.contacts)
      ..[hex6] = (state.contacts[hex6] ?? 0) + 1;
    state = UnreadCounts(channels: state.channels, contacts: co);
    _save();
  }

  void markChannelRead(int index) {
    if ((state.channels[index] ?? 0) == 0) return;
    final ch = Map<int, int>.from(state.channels)..remove(index);
    state = UnreadCounts(channels: ch, contacts: state.contacts);
    _save();
  }

  void markContactRead(String hex6) {
    if ((state.contacts[hex6] ?? 0) == 0) return;
    final co = Map<String, int>.from(state.contacts)..remove(hex6);
    state = UnreadCounts(channels: state.channels, contacts: co);
    _save();
  }

  /// Reset only channel unread counts. Called when connecting to a different
  /// radio so that slot-index-based counts from the previous radio don't
  /// carry over to the new radio's channels.
  void resetChannels() {
    state = UnreadCounts(channels: {}, contacts: state.contacts);
    _save();
  }

  void reset() {
    state = const UnreadCounts();
    _save();
  }
}

final unreadCountsProvider =
    StateNotifierProvider<UnreadCountsNotifier, UnreadCounts>(
      (ref) => UnreadCountsNotifier(),
    );

// ---------------------------------------------------------------------------
// Notification settings
// ---------------------------------------------------------------------------

class NotificationSettingsNotifier extends StateNotifier<NotificationSettings> {
  NotificationSettingsNotifier() : super(const NotificationSettings());

  Future<void> loadFromStorage() async {
    final s = await StorageService.instance.loadNotificationSettings();
    state = s;
    NotificationService.instance.settings = s;
  }

  void update(NotificationSettings settings) {
    state = settings;
    NotificationService.instance.settings = settings;
    StorageService.instance.saveNotificationSettings(settings);
  }
}

final notificationSettingsProvider =
    StateNotifierProvider<NotificationSettingsNotifier, NotificationSettings>(
      (ref) => NotificationSettingsNotifier(),
    );

// ---------------------------------------------------------------------------
// Auto-reconnect setting
// ---------------------------------------------------------------------------

class AutoReconnectNotifier extends StateNotifier<bool> {
  AutoReconnectNotifier() : super(true) {
    _load();
  }

  static const _key = 'auto_reconnect';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_key) ?? true;
  }

  Future<void> set(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }
}

final autoReconnectProvider =
    StateNotifierProvider<AutoReconnectNotifier, bool>(
      (ref) => AutoReconnectNotifier(),
    );

/// Returns the first 6 bytes of [key] as a lowercase hex string.
String _hex6(Uint8List key) =>
    key.take(6).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

// ---------------------------------------------------------------------------
// Battery history
// ---------------------------------------------------------------------------

class BatteryReading {
  const BatteryReading({required this.timestamp, required this.millivolts});
  final DateTime timestamp;
  final int millivolts;
  double get volts => millivolts / 1000.0;
}

class BatteryHistoryNotifier extends StateNotifier<List<BatteryReading>> {
  BatteryHistoryNotifier() : super([]) {
    _loadFromPrefs();
  }

  static const _prefKey = 'battery_history_v1';
  static const _maxAge = Duration(days: 7);

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    if (raw == null) return;
    try {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      final cutoff = DateTime.now().subtract(_maxAge);
      final readings =
          list
              .map(
                (e) => BatteryReading(
                  timestamp: DateTime.fromMillisecondsSinceEpoch(
                    e['ts'] as int,
                  ),
                  millivolts: e['mv'] as int,
                ),
              )
              .where((r) => r.timestamp.isAfter(cutoff))
              .toList();
      if (readings.isNotEmpty) state = readings;
    } catch (_) {
      // Ignore malformed persisted data
    }
  }

  void add(int millivolts) {
    if (millivolts <= 0) return;
    final cutoff = DateTime.now().subtract(_maxAge);
    state = [
      ...state.where((r) => r.timestamp.isAfter(cutoff)),
      BatteryReading(timestamp: DateTime.now(), millivolts: millivolts),
    ];
    _saveToPrefs();
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final data =
        state
            .map(
              (r) => {
                'ts': r.timestamp.millisecondsSinceEpoch,
                'mv': r.millivolts,
              },
            )
            .toList();
    await prefs.setString(_prefKey, jsonEncode(data));
  }
}

final batteryHistoryProvider =
    StateNotifierProvider<BatteryHistoryNotifier, List<BatteryReading>>(
      (ref) => BatteryHistoryNotifier(),
    );

// ---------------------------------------------------------------------------
// Network statistics
// ---------------------------------------------------------------------------

class NetworkStats {
  const NetworkStats({
    this.rxMessages = 0,
    this.txMessages = 0,
    this.errors = 0,
    this.heardNodes = 0,
  });
  final int rxMessages;
  final int txMessages;
  final int errors;
  final int heardNodes;

  NetworkStats copyWith({
    int? rxMessages,
    int? txMessages,
    int? errors,
    int? heardNodes,
  }) => NetworkStats(
    rxMessages: rxMessages ?? this.rxMessages,
    txMessages: txMessages ?? this.txMessages,
    errors: errors ?? this.errors,
    heardNodes: heardNodes ?? this.heardNodes,
  );
}

class NetworkStatsNotifier extends StateNotifier<NetworkStats> {
  NetworkStatsNotifier() : super(const NetworkStats());

  void incrementRx() =>
      state = state.copyWith(rxMessages: state.rxMessages + 1);
  void incrementTx() =>
      state = state.copyWith(txMessages: state.txMessages + 1);
  void incrementError() => state = state.copyWith(errors: state.errors + 1);
  void incrementHeard() =>
      state = state.copyWith(heardNodes: state.heardNodes + 1);
  void reset() => state = const NetworkStats();
}

final networkStatsProvider =
    StateNotifierProvider<NetworkStatsNotifier, NetworkStats>(
      (ref) => NetworkStatsNotifier(),
    );

// ---------------------------------------------------------------------------
// Telemetry (CayenneLPP sensor readings)
// ---------------------------------------------------------------------------

class TelemetryEntry {
  const TelemetryEntry({required this.timestamp, required this.readings});
  final DateTime timestamp;
  final List<CayenneReading> readings;
}

class TelemetryNotifier extends StateNotifier<List<TelemetryEntry>> {
  TelemetryNotifier() : super([]);

  static const _maxEntries = 50;

  void add(List<CayenneReading> readings) {
    if (readings.isEmpty) return;
    final entry = TelemetryEntry(timestamp: DateTime.now(), readings: readings);
    final updated = [entry, ...state];
    state =
        updated.length > _maxEntries
            ? updated.sublist(0, _maxEntries)
            : updated;
  }
}

final telemetryProvider =
    StateNotifierProvider<TelemetryNotifier, List<TelemetryEntry>>(
      (ref) => TelemetryNotifier(),
    );

// ---------------------------------------------------------------------------
// Scanned devices
// ---------------------------------------------------------------------------

final scannedDevicesProvider = StateProvider<List<RadioDevice>>((_) => []);

// ---------------------------------------------------------------------------
// Trace result
// ---------------------------------------------------------------------------

/// Latest parsed [TraceResult] received from a PUSH_CODE_TRACE_DATA (0x89).
/// Updated whenever a new trace push arrives; null until first trace received.
final traceResultProvider = StateProvider<TraceResult?>((ref) => null);

/// Session-scoped accumulator of all [TraceResult]s received since the last
/// connect.  Capped at 50 entries.  Cleared on disconnect.  Used by
/// [TopologyScreen] to derive inter-node edges from historical trace data.
class _TraceHistoryNotifier extends StateNotifier<List<TraceResult>> {
  _TraceHistoryNotifier() : super(const []);

  void add(TraceResult result) {
    state =
        state.length >= 50
            ? [...state.sublist(state.length - 49), result]
            : [...state, result];
  }

  void clear() => state = const [];
}

final traceHistoryProvider =
    StateNotifierProvider<_TraceHistoryNotifier, List<TraceResult>>(
      (_) => _TraceHistoryNotifier(),
    );

/// Cache of outPath bytes per contact, keyed by 6-byte pubKeyPrefix hex.
/// Populated whenever a PathDiscoveryPush (0x8D) is received.
/// Used by the trace flow to supply correct hop-hash path bytes.
final pathCacheProvider = StateProvider<Map<String, List<int>>>((_) => {});

// ---------------------------------------------------------------------------
// Repeater remote-admin
// ---------------------------------------------------------------------------

/// Map of repeater pub-key-prefix hex → latest [RepeaterStats] received.
final repeaterStatusProvider = StateProvider<Map<String, RepeaterStats>>(
  (_) => {},
);

/// Login result: null = no attempt, true = success, false = fail.
/// Reset to null by the admin sheet before each new login attempt.
final loginResultProvider = StateProvider<bool?>((_) => null);

// ---------------------------------------------------------------------------
// Contact favorites — derived from the radio's `flags` byte (bit 0).
// The firmware owns the canonical list; the UI reads Contact.isFavorite
// directly. ContactsNotifier.setFavorite mutates the bit locally and the
// caller pushes the updated contact via RadioService.addUpdateContact.
// ---------------------------------------------------------------------------

/// Migrates any app-local favourites (from pre-fix SharedPreferences) to the
/// radio's `flags` byte. Called once after the initial contact sync on every
/// connect — it's idempotent: after the first migration, the stored set is
/// cleared and subsequent calls are no-ops.
Future<void> _migrateLegacyFavorites(Ref ref, RadioService service) async {
  final legacy = await StorageService.instance.loadFavorites();
  if (legacy.isEmpty) return;
  final contactsNotifier = ref.read(contactsProvider.notifier);
  for (final contact in ref.read(contactsProvider)) {
    final keyHex =
        contact.publicKey
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
    if (!legacy.contains(keyHex) || contact.isFavorite) continue;
    contactsNotifier.setFavorite(contact.publicKey, true);
    // Fire-and-forget — OkResponse isn't awaited; failures fall through to
    // the next connect's migration retry (the legacy set is still present
    // until clearFavorites below runs on success).
    unawaited(
      service.addUpdateContact(contact.withFavorite(true)).catchError((_) {}),
    );
  }
  await StorageService.instance.clearFavorites();
}

// ---------------------------------------------------------------------------
// Radio hardware stats (CMD_GET_STATS responses)
// ---------------------------------------------------------------------------

/// Latest core device statistics from the connected radio.
/// Polled every 5 minutes alongside the battery; null until first response.
final radioStatsCoreProvider = StateProvider<StatsCoreResponse?>((_) => null);

/// Latest radio-layer statistics (noise floor, RSSI, SNR, airtime).
final radioStatsRadioProvider = StateProvider<StatsRadioResponse?>((_) => null);

/// Latest packet counters (received, sent, flood/direct breakdown, CRC errors).
final radioStatsPacketsProvider = StateProvider<StatsPacketsResponse?>(
  (_) => null,
);

// ---------------------------------------------------------------------------
// Noise floor history (in-session ring buffer, up to 300 readings)
// ---------------------------------------------------------------------------

class NoiseFloorReading {
  const NoiseFloorReading({required this.timestamp, required this.dBm});
  final DateTime timestamp;
  final int dBm;
}

class NoiseFloorHistoryNotifier extends StateNotifier<List<NoiseFloorReading>> {
  NoiseFloorHistoryNotifier() : super([]);

  static const _maxReadings = 300;

  void add(int dBm) {
    final next = [
      ...state,
      NoiseFloorReading(timestamp: DateTime.now(), dBm: dBm),
    ];
    state =
        next.length > _maxReadings
            ? next.sublist(next.length - _maxReadings)
            : next;
  }

  void clear() => state = [];
}

final noiseFloorHistoryProvider =
    StateNotifierProvider<NoiseFloorHistoryNotifier, List<NoiseFloorReading>>(
      (ref) => NoiseFloorHistoryNotifier(),
    );

// ---------------------------------------------------------------------------
// RSSI history (in-session ring buffer, up to 300 readings)
// ---------------------------------------------------------------------------

class RssiReading {
  const RssiReading({required this.timestamp, required this.dBm});
  final DateTime timestamp;
  final int dBm;
}

class RssiHistoryNotifier extends StateNotifier<List<RssiReading>> {
  RssiHistoryNotifier() : super([]);

  static const _maxReadings = 300;

  void add(int dBm) {
    final next = [...state, RssiReading(timestamp: DateTime.now(), dBm: dBm)];
    state =
        next.length > _maxReadings
            ? next.sublist(next.length - _maxReadings)
            : next;
  }

  void clear() => state = [];
}

final rssiHistoryProvider =
    StateNotifierProvider<RssiHistoryNotifier, List<RssiReading>>(
      (ref) => RssiHistoryNotifier(),
    );

// ---------------------------------------------------------------------------
// Packet heard tracker (driven by 0x88 raw RF log)
// ---------------------------------------------------------------------------

/// Tracks how many times each unique packet hash has been received.
///
/// The firmware pushes `PUSH_CODE_LOG_RX_DATA` (0x88) for every raw RF
/// reception **before** mesh deduplication.  Identical packet hashes mean the
/// same logical packet was heard multiple times — each duplicate represents
/// a different repeater that forwarded it.
///
/// The state maps `packetHashHex` → list of [MessagePath] records.
class PacketHeardNotifier
    extends StateNotifier<Map<String, List<MessagePath>>> {
  PacketHeardNotifier() : super({});

  /// Load persisted paths from storage (called on app start and after reset).
  Future<void> loadFromStorage() async {
    final saved = await StorageService.instance.loadMessagePaths();
    if (saved.isNotEmpty) {
      // Merge: runtime data wins over stored data for any shared key.
      state = {...saved, ...state};
    }
  }

  /// Record a reception of [hashHex] with its path details.
  /// Returns the new total count (number of paths stored for this hash).
  int record(
    String hashHex, {
    required double snr,
    required int rssi,
    required Uint8List pathBytes,
    required int pathHashCount,
    required int pathHashSize,
  }) {
    final path = MessagePath(
      snr: snr,
      rssi: rssi,
      pathHashCount: pathHashCount,
      pathHashSize: pathHashSize,
      pathBytes: pathBytes,
    );
    final prev = state[hashHex] ?? [];
    final next = [...prev, path];
    state = {...state, hashHex: next};
    // Persist after every record so paths survive app restarts.
    StorageService.instance.saveMessagePaths(state);
    return next.length;
  }

  /// Clear the in-memory state (e.g. on disconnect) then reload persisted
  /// paths so historical data remains available for the UI.
  void reset() {
    state = {};
    Future.microtask(loadFromStorage);
  }
}

final packetHeardProvider =
    StateNotifierProvider<PacketHeardNotifier, Map<String, List<MessagePath>>>(
      (ref) => PacketHeardNotifier(),
    );

// ---------------------------------------------------------------------------
// RX log (raw 0x88 frames for diagnostics / PCAP export)
// ---------------------------------------------------------------------------

class RxLogEntry {
  const RxLogEntry({
    required this.receivedAt,
    required this.snr,
    required this.rssi,
    required this.rawPacket,
    this.payloadType,
    this.packetHashHex,
    this.pathHops,
  });

  final DateTime receivedAt;
  final double snr;
  final int rssi;

  /// Raw over-the-air packet bytes (without the 0x88 SNR/RSSI preamble).
  final Uint8List rawPacket;

  final int? payloadType;
  final String? packetHashHex;
  final int? pathHops;
}

class RxLogNotifier extends StateNotifier<List<RxLogEntry>> {
  RxLogNotifier() : super(const []);

  static const int _maxEntries = 4000;

  /// Record one PUSH_CODE_LOG_RX_DATA frame payload (bytes after 0x88).
  void recordFromLogRxFrame(Uint8List data) {
    if (data.length < 2) return;

    final snrByte = data[0];
    final snr = (snrByte < 128 ? snrByte : snrByte - 256) / 4.0;
    final rssiByte = data[1];
    final rssi = rssiByte < 128 ? rssiByte : rssiByte - 256;
    final raw =
        data.length > 2 ? Uint8List.fromList(data.sublist(2)) : Uint8List(0);

    final parsed = parseRawPacket(raw);

    final entry = RxLogEntry(
      receivedAt: DateTime.now(),
      snr: snr,
      rssi: rssi,
      rawPacket: raw,
      payloadType: parsed?.payloadType,
      packetHashHex: parsed?.packetHashHex,
      pathHops: parsed?.pathHashCount,
    );

    final next = [...state, entry];
    if (next.length > _maxEntries) {
      state = next.sublist(next.length - _maxEntries);
    } else {
      state = next;
    }
  }

  void clear() => state = const [];
}

final rxLogProvider = StateNotifierProvider<RxLogNotifier, List<RxLogEntry>>(
  (ref) => RxLogNotifier(),
);

// ---------------------------------------------------------------------------
// Best recent signal — derived from the 0x88 RX log.
//
// Returns the highest (least negative) SNR in dB from packets received in
// the last 5 minutes, or null when disconnected / no packets yet received.
// Used by the AppBar signal indicator in HomeScreen.
// ---------------------------------------------------------------------------

/// Set to true before navigating to /apps/telemetry to auto-scroll to RF section.
final telemetryScrollToRfProvider = StateProvider<bool>((_) => false);

final bestSignalSnrProvider = Provider<double?>((ref) {
  final isConnected = ref.watch(connectionProvider) == TransportState.connected;
  if (!isConnected) return null;

  final log = ref.watch(rxLogProvider);
  if (log.isEmpty) return null;

  final cutoff = DateTime.now().subtract(const Duration(minutes: 5));
  final recent = log.where((e) => e.receivedAt.isAfter(cutoff));
  if (recent.isEmpty) return null;

  return recent.map((e) => e.snr).reduce((a, b) => a > b ? a : b);
});

enum ContactFilter {
  todos,
  favoritos,
  companheiros,
  repetidores,
  salas,
  sensores,
}

enum ContactSort { nome, ouvidoRecentemente, ultimaMensagem }

class _ContactFilterNotifier extends StateNotifier<ContactFilter> {
  _ContactFilterNotifier() : super(ContactFilter.todos) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final idx = prefs.getInt('contacts_filter');
    if (idx != null && idx >= 0 && idx < ContactFilter.values.length) {
      state = ContactFilter.values[idx];
    }
  }

  Future<void> set(ContactFilter f) async {
    state = f;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('contacts_filter', f.index);
  }
}

class _ContactSortNotifier extends StateNotifier<ContactSort> {
  _ContactSortNotifier() : super(ContactSort.ouvidoRecentemente) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final idx = prefs.getInt('contacts_sort');
    if (idx != null && idx >= 0 && idx < ContactSort.values.length) {
      state = ContactSort.values[idx];
    }
  }

  Future<void> set(ContactSort s) async {
    state = s;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('contacts_sort', s.index);
  }
}

final contactFilterProvider =
    StateNotifierProvider<_ContactFilterNotifier, ContactFilter>(
      (_) => _ContactFilterNotifier(),
    );

final contactSortProvider =
    StateNotifierProvider<_ContactSortNotifier, ContactSort>(
      (_) => _ContactSortNotifier(),
    );

// ---------------------------------------------------------------------------
// Mention pill colours (persisted to SharedPreferences)
// ---------------------------------------------------------------------------

class MentionColorNotifier extends StateNotifier<Color> {
  MentionColorNotifier(super.defaultColor, this._key) {
    _load();
  }
  final String _key;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getInt(_key);
    if (val != null) {
      state = Color.fromARGB(
        (val >> 24) & 0xFF,
        (val >> 16) & 0xFF,
        (val >> 8) & 0xFF,
        val & 0xFF,
      );
    }
  }

  Future<void> setColor(Color color) async {
    state = color;
    final prefs = await SharedPreferences.getInstance();
    final a = (color.a * 255).round();
    final r = (color.r * 255).round();
    final g = (color.g * 255).round();
    final b = (color.b * 255).round();
    await prefs.setInt(_key, (a << 24) | (r << 16) | (g << 8) | b);
  }
}

/// Pill background for @[YourName] (you are mentioned).  Default: amber.
final selfMentionColorProvider =
    StateNotifierProvider<MentionColorNotifier, Color>(
      (ref) => MentionColorNotifier(
        const Color.fromARGB(0xFF, 0xFF, 0xB3, 0x47), // amber
        'mention_color_self',
      ),
    );

/// Pill background for @[OtherName] (someone else mentioned).  Default: orange.
final otherMentionColorProvider =
    StateNotifierProvider<MentionColorNotifier, Color>(
      (ref) => MentionColorNotifier(
        const Color.fromARGB(0xFF, 0xFF, 0x6B, 0x00), // orange
        'mention_color_other',
      ),
    );

// ---------------------------------------------------------------------------
// App-wide theme settings (mode + accent), persisted to SharedPreferences.
// ---------------------------------------------------------------------------

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.dark) {
    _load();
  }

  static const _key = 'theme_mode_v1';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    state = switch (raw) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }
}

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
  (ref) => ThemeModeNotifier(),
);

/// User-selected accent colour. `null` means "use brand orange (default)".
class AccentColorNotifier extends StateNotifier<Color?> {
  AccentColorNotifier() : super(null) {
    _load();
  }

  static const _key = 'accent_color_v1';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getInt(_key);
    if (val == null) return;
    state = Color.fromARGB(
      (val >> 24) & 0xFF,
      (val >> 16) & 0xFF,
      (val >> 8) & 0xFF,
      val & 0xFF,
    );
  }

  Future<void> set(Color? color) async {
    state = color;
    final prefs = await SharedPreferences.getInstance();
    if (color == null) {
      await prefs.remove(_key);
      return;
    }
    final a = (color.a * 255).round();
    final r = (color.r * 255).round();
    final g = (color.g * 255).round();
    final b = (color.b * 255).round();
    await prefs.setInt(_key, (a << 24) | (r << 16) | (g << 8) | b);
  }
}

final accentColorProvider = StateNotifierProvider<AccentColorNotifier, Color?>(
  (ref) => AccentColorNotifier(),
);
