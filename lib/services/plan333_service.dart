import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../protocol/protocol.dart';
import '../providers/radio_providers.dart';
import 'notification_service.dart';
import 'storage_service.dart';

// ---------------------------------------------------------------------------
// Plan333Config — user settings for the Mesh 3-3-3 event
// ---------------------------------------------------------------------------

class Plan333Config {
  const Plan333Config({
    this.stationName = '',
    this.city = '',
    this.locality = '',
    this.meshChannelIndex = 0,
    this.autoSendCq = false,
  });

  final String stationName;
  final String city;
  final String locality;

  /// MeshCore channel index (0-based) used to send CQ and QSL messages.
  final int meshChannelIndex;

  /// When true, CQ messages are sent automatically during the event window.
  final bool autoSendCq;

  /// True when the config has enough data to build a valid CQ message.
  bool get isConfigured => stationName.isNotEmpty && city.isNotEmpty;

  /// Builds the standard CQ presence string.
  ///   "CQ Plano 333, [name], [city], [locality]"
  String get cqMessage {
    final parts = ['CQ Plano 333', stationName, city];
    if (locality.isNotEmpty) parts.add(locality);
    return parts.join(', ');
  }

  Plan333Config copyWith({
    String? stationName,
    String? city,
    String? locality,
    int? meshChannelIndex,
    bool? autoSendCq,
  }) =>
      Plan333Config(
        stationName: stationName ?? this.stationName,
        city: city ?? this.city,
        locality: locality ?? this.locality,
        meshChannelIndex: meshChannelIndex ?? this.meshChannelIndex,
        autoSendCq: autoSendCq ?? this.autoSendCq,
      );

  Map<String, dynamic> toJson() => {
        'station_name': stationName,
        'city': city,
        'locality': locality,
        'mesh_channel': meshChannelIndex,
        'auto_send': autoSendCq,
      };

  factory Plan333Config.fromJson(Map<String, dynamic> json) => Plan333Config(
        stationName: (json['station_name'] as String?) ?? '',
        city: (json['city'] as String?) ?? '',
        locality: (json['locality'] as String?) ?? '',
        meshChannelIndex: (json['mesh_channel'] as int?) ?? 0,
        autoSendCq: (json['auto_send'] as bool?) ?? false,
      );
}

// ---------------------------------------------------------------------------
// Plan333AutoSendState — tracks CQ sends in the current event session
// ---------------------------------------------------------------------------

class Plan333AutoSendState {
  const Plan333AutoSendState({this.cqSentCount = 0, this.lastCqTime});

  /// Number of CQ messages sent in the current Saturday event (0–3).
  final int cqSentCount;

  /// Timestamp of the most recent CQ send.
  final DateTime? lastCqTime;

  Plan333AutoSendState copyWith({int? cqSentCount, DateTime? lastCqTime}) =>
      Plan333AutoSendState(
        cqSentCount: cqSentCount ?? this.cqSentCount,
        lastCqTime: lastCqTime ?? this.lastCqTime,
      );
}

// ---------------------------------------------------------------------------
// Plan333Service — static utility / window-detection
// ---------------------------------------------------------------------------

/// Pure business logic for the Portuguese Plano 3-3-3.
///
/// CB/PMR: windows every 3 hours (00:00 03:00 … 21:00), ±3 min each.
/// Mesh:   weekly Saturdays 21:00–22:00 (presence) / 21:30–22:00 (QSL).
class Plan333Service {
  Plan333Service._();

  // ── CB / PMR ─────────────────────────────────────────────────────────────
  static const List<int> windowHours = [0, 3, 6, 9, 12, 15, 18, 21];

  static bool isWindowActive(DateTime now) {
    final totalMinutes = now.hour * 60 + now.minute;
    for (final h in windowHours) {
      var diff = (totalMinutes - h * 60).abs();
      if (diff > 720) diff = 1440 - diff;
      if (diff <= 3) return true;
    }
    return false;
  }

  static DateTime nextWindowTime(DateTime now) {
    final totalMinutes = now.hour * 60 + now.minute;
    for (final h in windowHours) {
      if (h * 60 > totalMinutes) {
        return DateTime(now.year, now.month, now.day, h, 0);
      }
    }
    final tomorrow = now.add(const Duration(days: 1));
    return DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 0, 0);
  }

  static double windowProgress(DateTime now) {
    final totalSeconds =
        now.hour * 3600 + now.minute * 60 + now.second.toDouble();
    int lastH = windowHours.last;
    for (final h in windowHours) {
      if (h * 3600 <= totalSeconds) lastH = h;
    }
    return ((totalSeconds - lastH * 3600.0) / 10800.0).clamp(0.0, 1.0);
  }

  // ── MeshCore channel config (published on plano333.pt) ───────────────────
  static const String meshCoreHashtag = '#plano333';
  static const String meshCoreSecretKey = '8d40917d08edeeb33e85c1a2308a2221';
  static const String reportUrl =
      'https://www.meshcore.pt/pt/projects/plano333';

  // ── Meshtastic channel config (published on plano333.pt) ─────────────────
  static const String meshtasticChannelName = 'Plano_3-3-3';
  static const String meshtasticPsk =
      'AlRIqQuRL8WUxq2xIk2xjxJenYAXvzjCT8nY2lFnx2k=';

  // ── Mesh ─────────────────────────────────────────────────────────────────
  static const int _meshHour = 21;   // event start
  static const int _meshEnd = 22;    // event end (exclusive)
  static const int _qslMinute = 30;  // QSL phase starts at xx:30

  /// True when [now] is Saturday 21:00–22:00 (presence window for MeshCore).
  static bool isMeshEventActive(DateTime now) =>
      now.weekday == DateTime.saturday &&
      now.hour >= _meshHour &&
      now.hour < _meshEnd;

  /// True when [now] is Saturday 21:30–22:00 (QSL confirmation window).
  static bool isMeshQslActive(DateTime now) =>
      now.weekday == DateTime.saturday &&
      now.hour == _meshHour &&
      now.minute >= _qslMinute;

  /// Next Saturday 21:00:00.
  static DateTime nextMeshEvent(DateTime now) {
    var d = DateTime(now.year, now.month, now.day, _meshHour, 0);
    if (d.isBefore(now)) d = d.add(const Duration(days: 1));
    while (d.weekday != DateTime.saturday) d = d.add(const Duration(days: 1));
    return d;
  }

  /// Minute within the 21:xx hour at which CQ [index] (0-based) is sent.
  /// Slots: 21:02, 21:22, 21:42 — 20 min apart, starting 2 min in.
  static int cqTargetMinute(int index) => 2 + index * 20;

  /// Next Saturday (used for the training reminder label).
  static DateTime nextSaturdayTraining(DateTime now) {
    var d = DateTime(now.year, now.month, now.day, 21, 0);
    if (d.isBefore(now)) d = d.add(const Duration(days: 1));
    while (d.weekday != DateTime.saturday) d = d.add(const Duration(days: 1));
    return d;
  }
}

// ---------------------------------------------------------------------------
// plan333ConfigProvider
// ---------------------------------------------------------------------------

final plan333ConfigProvider =
    StateNotifierProvider<Plan333ConfigNotifier, Plan333Config>(
        (ref) => Plan333ConfigNotifier());

class Plan333ConfigNotifier extends StateNotifier<Plan333Config> {
  Plan333ConfigNotifier() : super(const Plan333Config());

  Future<void> loadFromStorage() async {
    final raw = await StorageService.instance.loadPlan333Config();
    if (raw == null) return;
    try {
      state = Plan333Config.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {}
  }

  Future<void> update(Plan333Config config) async {
    state = config;
    await StorageService.instance.savePlan333Config(jsonEncode(config.toJson()));
  }
}

// ---------------------------------------------------------------------------
// plan333EnabledProvider — CB/PMR window notification toggle
// ---------------------------------------------------------------------------

final plan333EnabledProvider =
    StateNotifierProvider<Plan333Notifier, bool>((ref) => Plan333Notifier());

class Plan333Notifier extends StateNotifier<bool> {
  Plan333Notifier() : super(false);

  Future<void> loadFromStorage() async {
    final enabled = await StorageService.instance.loadPlan333Enabled();
    state = enabled;
    if (enabled) await NotificationService.instance.schedulePlan333Alerts();
  }

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    await StorageService.instance.savePlan333Enabled(enabled);
    if (enabled) {
      await NotificationService.instance.schedulePlan333Alerts();
    } else {
      await NotificationService.instance.cancelPlan333Alerts();
    }
  }
}

// ---------------------------------------------------------------------------
// plan333AutoSendProvider — MeshCore auto-send state + logic
// ---------------------------------------------------------------------------

final plan333AutoSendProvider =
    StateNotifierProvider<Plan333AutoSendNotifier, Plan333AutoSendState>(
        (ref) => Plan333AutoSendNotifier(ref));

class Plan333AutoSendNotifier extends StateNotifier<Plan333AutoSendState> {
  Plan333AutoSendNotifier(this._ref) : super(const Plan333AutoSendState()) {
    // Poll every 30 s — lightweight, auto-send fires only once per slot.
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) => _tick());
  }

  final Ref _ref;
  Timer? _pollTimer;

  void _tick() {
    final now = DateTime.now();
    final config = _ref.read(plan333ConfigProvider);

    // Reset session counter when the Mesh event window closes.
    if (!Plan333Service.isMeshEventActive(now) && state.cqSentCount > 0) {
      state = const Plan333AutoSendState();
      return;
    }

    if (!config.autoSendCq) return;
    if (!Plan333Service.isMeshEventActive(now)) return;
    if (state.cqSentCount >= 3) return;
    if (!config.isConfigured) return;

    // Fire each CQ once its target minute has been reached.
    final targetMinute = Plan333Service.cqTargetMinute(state.cqSentCount);
    if (now.minute >= targetMinute) _doSend(config);
  }

  /// Manually send one CQ (ignores auto-send flag, respects 3-message limit).
  Future<void> sendManualCq() async {
    final config = _ref.read(plan333ConfigProvider);
    if (!config.isConfigured) return;
    _doSend(config);
  }

  void _doSend(Plan333Config config) {
    final service = _ref.read(radioServiceProvider);
    if (service == null || !service.isConnected) return;

    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final msg = config.cqMessage;

    _ref.read(messagesProvider.notifier).addOutgoing(
          ChatMessage(
            text: msg,
            timestamp: ts,
            isOutgoing: true,
            channelIndex: config.meshChannelIndex,
          ),
        );
    service.sendChannelMessage(config.meshChannelIndex, msg, timestamp: ts);

    state = state.copyWith(
      cqSentCount: state.cqSentCount + 1,
      lastCqTime: DateTime.now(),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}
