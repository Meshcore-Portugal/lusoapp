import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../protocol/protocol.dart';
import '../providers/radio_providers.dart';
import 'notification_service.dart';
import 'storage_service.dart';

// ---------------------------------------------------------------------------
// Plan333Config — user settings for the Mesh 3-3-3 event
// ---------------------------------------------------------------------------

class Plan333Config {
  factory Plan333Config.fromJson(Map<String, dynamic> json) => Plan333Config(
    stationName: (json['station_name'] as String?) ?? '',
    city: (json['city'] as String?) ?? '',
    locality: (json['locality'] as String?) ?? '',
    meshChannelIndex: (json['mesh_channel'] as int?) ?? 0,
    autoSendCq: (json['auto_send'] as bool?) ?? false,
  );
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
  }) => Plan333Config(
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
}

// ---------------------------------------------------------------------------
// Plan333AutoSendState — tracks CQ sends in the current event session
// ---------------------------------------------------------------------------

class Plan333AutoSendState {
  const Plan333AutoSendState({
    this.cqSentCount = 0,
    this.lastCqTime,
    this.qslSentStations = const {},
    this.lastQslTime,
    this.aborted = false,
  });

  /// Number of CQ messages sent in the current Saturday event (0–3).
  final int cqSentCount;

  /// Timestamp of the most recent CQ send.
  final DateTime? lastCqTime;

  /// Station names for which a QSL has been auto-sent this session.
  final Set<String> qslSentStations;

  /// Timestamp of the most recent QSL auto-send.
  final DateTime? lastQslTime;

  /// When true, the user aborted the auto-send session — no further
  /// automatic CQ/QSL messages will be sent until the state is reset.
  final bool aborted;

  int get qslSentCount => qslSentStations.length;

  Plan333AutoSendState copyWith({
    int? cqSentCount,
    DateTime? lastCqTime,
    Set<String>? qslSentStations,
    DateTime? lastQslTime,
    bool? aborted,
  }) => Plan333AutoSendState(
    cqSentCount: cqSentCount ?? this.cqSentCount,
    lastCqTime: lastCqTime ?? this.lastCqTime,
    qslSentStations: qslSentStations ?? this.qslSentStations,
    lastQslTime: lastQslTime ?? this.lastQslTime,
    aborted: aborted ?? this.aborted,
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

  /// The 16-byte secret for the #plano333 channel, decoded from [meshCoreSecretKey].
  static Uint8List get meshCoreSecretBytes {
    const hex = meshCoreSecretKey;
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  static const String reportUrl =
      'https://www.meshcore.pt/pt/projects/plano333';

  // ── Meshtastic channel config (published on plano333.pt) ─────────────────
  static const String meshtasticChannelName = 'Plano_3-3-3';
  static const String meshtasticPsk =
      'AlRIqQuRL8WUxq2xIk2xjxJenYAXvzjCT8nY2lFnx2k=';

  // ── Mesh ─────────────────────────────────────────────────────────────────
  static const int _meshHour = 21; // event start
  static const int _meshEnd = 22; // event end (exclusive)
  static const int _qslMinute = 30; // QSL phase starts at xx:30

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
    while (d.weekday != DateTime.saturday) {
      d = d.add(const Duration(days: 1));
    }
    return d;
  }

  /// Minute within the 21:xx hour at which CQ [index] (0-based) is sent.
  /// Slots: 21:02, 21:22, 21:42 — 20 min apart, starting 2 min in.
  static int cqTargetMinute(int index) => 2 + index * 20;

  /// Try to parse an incoming channel message as a CQ presence call.
  ///
  /// Accepted format: `CQ Plano 333, <station>, <city>[, <locality>]`
  /// Returns null if the text is not a CQ Plano 333 message.
  /// [pathLen] is used as the hop count.
  static QslRecord? tryParseCq(String text, {int? pathLen}) {
    final trimmed = text.trim();

    // Some incoming channel payloads may include a sender prefix:
    // "Name: CQ Plano 333, ...". Accept only if CQ starts the body.
    var cqText = trimmed;
    final upper = trimmed.toUpperCase();
    if (!upper.startsWith('CQ PLANO 333')) {
      final sep = trimmed.indexOf(':');
      if (sep < 0) return null;
      final afterPrefix = trimmed.substring(sep + 1).trimLeft();
      if (!afterPrefix.toUpperCase().startsWith('CQ PLANO 333')) return null;
      cqText = afterPrefix;
    }

    final parts = cqText.split(RegExp(r',\s*'));
    // parts[0]="CQ Plano 333"  parts[1]=station  parts[2]=city  parts[3]=locality
    if (parts.length < 2) return null;

    final station = parts[1].trim();
    if (station.isEmpty) return null;

    final location = [
      if (parts.length >= 3 && parts[2].trim().isNotEmpty) parts[2].trim(),
      if (parts.length >= 4 && parts[3].trim().isNotEmpty) parts[3].trim(),
    ].join(', ');

    return QslRecord(
      stationName: station,
      hops: pathLen ?? 0,
      location: location,
      timestamp: DateTime.now(),
    );
  }

  /// Try to parse an incoming channel message as a QSL confirmation.
  ///
  /// Accepted format: `QSL, <station>, <N hops|Direto>, <location>`
  /// All parts after station are optional.  Returns null if the text is not a
  /// QSL message.  [pathLen] is used as the hop count when the text carries no
  /// explicit hops value.
  static QslRecord? tryParseQsl(String text, {int? pathLen}) {
    final trimmed = text.trim();
    if (!trimmed.toUpperCase().startsWith('QSL')) return null;

    // Split on commas (with optional surrounding spaces).
    final parts = trimmed.split(RegExp(r',\s*'));
    if (parts.length < 2) return null;

    final station = parts[1].trim();
    if (station.isEmpty) return null;

    int hops = pathLen ?? 0;
    String location = '';

    if (parts.length >= 3) {
      final hopsPart = parts[2].trim().toLowerCase();
      final hopsMatch = RegExp(r'(\d+)\s*hops?').firstMatch(hopsPart);
      if (hopsMatch != null) {
        hops = int.tryParse(hopsMatch.group(1) ?? '') ?? hops;
      } else if (hopsPart == 'direto' ||
          hopsPart == 'directo' ||
          hopsPart == 'direct') {
        hops = 0;
      } else {
        // No hops info — treat as location.
        location = parts[2].trim();
      }
    }

    if (parts.length >= 4 && location.isEmpty) {
      location = parts.sublist(3).join(', ').trim();
    }

    return QslRecord(
      stationName: station,
      hops: hops,
      location: location,
      timestamp: DateTime.now(),
    );
  }

  /// Next Saturday (used for the training reminder label).
  static DateTime nextSaturdayTraining(DateTime now) {
    var d = DateTime(now.year, now.month, now.day, 21, 0);
    if (d.isBefore(now)) d = d.add(const Duration(days: 1));
    while (d.weekday != DateTime.saturday) {
      d = d.add(const Duration(days: 1));
    }
    return d;
  }
}

// ---------------------------------------------------------------------------
// QslRecord — one received QSL confirmation
// ---------------------------------------------------------------------------

class QslRecord {
  const QslRecord({
    required this.stationName,
    required this.hops,
    required this.location,
    required this.timestamp,
    this.notes = '',
  });

  factory QslRecord.fromJson(Map<String, dynamic> j) => QslRecord(
    stationName: (j['station'] as String?) ?? '',
    hops: (j['hops'] as int?) ?? 0,
    location: (j['location'] as String?) ?? '',
    timestamp: DateTime.fromMillisecondsSinceEpoch((j['ts'] as int?) ?? 0),
    notes: (j['notes'] as String?) ?? '',
  );

  /// Station callsign / name that sent the QSL.
  final String stationName;

  /// Number of hops (0 = direct).
  final int hops;

  /// Their reported location / city.
  final String location;

  /// When the QSL was logged (local device time).
  final DateTime timestamp;

  /// Optional free-form notes.
  final String notes;

  String get hopsLabel => hops == 0 ? 'Direto' : '$hops hops';

  Map<String, dynamic> toJson() => {
    'station': stationName,
    'hops': hops,
    'location': location,
    'ts': timestamp.millisecondsSinceEpoch,
    'notes': notes,
  };
}

// ---------------------------------------------------------------------------
// qslLogProvider
// ---------------------------------------------------------------------------

final qslLogProvider = StateNotifierProvider<QslLogNotifier, List<QslRecord>>(
  (_) => QslLogNotifier(),
);

class QslLogNotifier extends StateNotifier<List<QslRecord>> {
  QslLogNotifier() : super([]);

  Future<void> loadFromStorage() async {
    final raw = await StorageService.instance.loadQslLog();
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      state =
          list
              .map((e) => QslRecord.fromJson(e as Map<String, dynamic>))
              .toList();
    } catch (_) {}
  }

  Future<void> add(QslRecord record) async {
    state = [record, ...state];
    await _persist();
  }

  Future<void> remove(int index) async {
    final next = [...state];
    next.removeAt(index);
    state = next;
    await _persist();
  }

  Future<void> clearAll() async {
    state = [];
    await _persist();
  }

  Future<void> _persist() async {
    await StorageService.instance.saveQslLog(
      jsonEncode(state.map((r) => r.toJson()).toList()),
    );
  }
}

// ---------------------------------------------------------------------------
// plan333DebugNowProvider — debug-only simulated clock (survives navigation)
// ---------------------------------------------------------------------------

/// Holds the simulated [DateTime] used by the debug automation panel.
/// Using a provider instead of widget-local state ensures the value is not
/// lost when the user navigates away from Plan333Screen and comes back.
/// Always null in non-debug builds (the panel is hidden by [kDebugMode]).
final plan333DebugNowProvider = StateProvider<DateTime?>((ref) => null);

// plan333ConfigProvider
// ---------------------------------------------------------------------------

final plan333ConfigProvider =
    StateNotifierProvider<Plan333ConfigNotifier, Plan333Config>(
      (ref) => Plan333ConfigNotifier(),
    );

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
    await StorageService.instance.savePlan333Config(
      jsonEncode(config.toJson()),
    );
  }
}

// ---------------------------------------------------------------------------
// plan333EnabledProvider — CB/PMR window notification toggle
// ---------------------------------------------------------------------------

final plan333EnabledProvider = StateNotifierProvider<Plan333Notifier, bool>(
  (ref) => Plan333Notifier(),
);

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
      (ref) => Plan333AutoSendNotifier(ref),
    );

class Plan333AutoSendNotifier extends StateNotifier<Plan333AutoSendState> {
  Plan333AutoSendNotifier(this._ref) : super(const Plan333AutoSendState()) {
    // Poll every 30 s — lightweight, auto-send fires only once per slot.
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) => _tick());
  }

  final Ref _ref;
  Timer? _pollTimer;

  void _tick() {
    _runAutomation(DateTime.now());
  }

  void _runAutomation(
    DateTime now, {
    bool allowOutsideEvent = false,
    bool ignoreAutoSendFlag = false,
  }) {
    final config = _ref.read(plan333ConfigProvider);

    // Reset session state when the Mesh event window closes.
    if (!allowOutsideEvent &&
        !Plan333Service.isMeshEventActive(now) &&
        (state.cqSentCount > 0 || state.qslSentStations.isNotEmpty)) {
      state = const Plan333AutoSendState();
      return;
    }

    if (state.aborted) return;
    if (!ignoreAutoSendFlag && !config.autoSendCq) return;
    if (!allowOutsideEvent && !Plan333Service.isMeshEventActive(now)) return;
    if (!config.isConfigured) return;

    // ── CQ phase: up to 3 sends at 21:02, 21:22, 21:42 ─────────────────
    if (state.cqSentCount < 3) {
      final targetMinute = Plan333Service.cqTargetMinute(state.cqSentCount);
      if (now.minute >= targetMinute) {
        _doSendCq(config);
        return; // one action per tick
      }
    }

    // ── QSL confirmation phase (21:30–22:00) ─────────────────────────────
    if (!allowOutsideEvent && !Plan333Service.isMeshQslActive(now)) return;

    final qslLog = _ref.read(qslLogProvider);
    final unsent =
        qslLog
            .where((r) => !state.qslSentStations.contains(r.stationName))
            .toList();
    if (unsent.isEmpty) return;

    _doSendQsl(config, unsent.first);
  }

  /// Debug helper: execute one automation scheduler pass at [simulatedNow].
  ///
  /// Intended for manual testing from debug UI, so weekly windows can be
  /// verified without waiting for Saturday.
  void debugRunAutomationAt(DateTime simulatedNow) {
    _runAutomation(
      simulatedNow,
      allowOutsideEvent: true,
      ignoreAutoSendFlag: false,
    );
  }

  /// Stop any further automatic CQ/QSL sends for the rest of this session.
  ///
  /// The aborted flag is cleared automatically when the event window closes
  /// (next [_tick] after 22:00 on Saturday) or via [debugResetAutomationState].
  void abortSession() {
    state = state.copyWith(aborted: true);
  }

  /// Debug helper: clear CQ/QSL session counters immediately.
  void debugResetAutomationState() {
    state = const Plan333AutoSendState();
  }

  /// Manually send one CQ (ignores auto-send flag, respects 3-message limit).
  Future<void> sendManualCq() async {
    final config = _ref.read(plan333ConfigProvider);
    if (!config.isConfigured) return;
    _doSendCq(config);
  }

  int _resolvePlan333ChannelIndex(Plan333Config config) {
    // Prefer channel lookup by name; fall back to configured index.
    final channels = _ref.read(channelsProvider);
    final target = Plan333Service.meshCoreHashtag.trim().toLowerCase();
    final targetNoHash = target.startsWith('#') ? target.substring(1) : target;

    final ch =
        channels.where((c) {
          final name = c.name.trim().toLowerCase();
          if (name.isEmpty) return false;
          final nameNoHash = name.startsWith('#') ? name.substring(1) : name;
          return name == target || nameNoHash == targetNoHash;
        }).firstOrNull;

    return ch?.index ?? config.meshChannelIndex;
  }

  void _doSendCq(Plan333Config config) {
    final service = _ref.read(radioServiceProvider);
    if (service == null || !service.isConnected) return;

    final channelIndex = _resolvePlan333ChannelIndex(config);

    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final msg = config.cqMessage;

    _ref
        .read(messagesProvider.notifier)
        .addOutgoing(
          ChatMessage(
            text: msg,
            timestamp: ts,
            isOutgoing: true,
            channelIndex: channelIndex,
          ),
        );
    service.sendChannelMessage(channelIndex, msg, timestamp: ts);

    state = state.copyWith(
      cqSentCount: state.cqSentCount + 1,
      lastCqTime: DateTime.now(),
    );
  }

  void _doSendQsl(Plan333Config config, QslRecord record) {
    final service = _ref.read(radioServiceProvider);
    if (service == null || !service.isConnected) return;

    final channelIndex = _resolvePlan333ChannelIndex(config);

    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final loc = record.location.isNotEmpty ? ', ${record.location}' : '';
    final msg = 'QSL, ${record.stationName}, ${record.hopsLabel}$loc';

    _ref
        .read(messagesProvider.notifier)
        .addOutgoing(
          ChatMessage(
            text: msg,
            timestamp: ts,
            isOutgoing: true,
            channelIndex: channelIndex,
          ),
        );
    service.sendChannelMessage(channelIndex, msg, timestamp: ts);

    state = state.copyWith(
      qslSentStations: {...state.qslSentStations, record.stationName},
      lastQslTime: DateTime.now(),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}
