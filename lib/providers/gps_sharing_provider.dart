import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How the app shares the phone's GPS with the connected radio.
///
/// The user is **always in charge**: the default is [off], and switching to
/// [auto] requires an explicit toggle and a fresh location-permission grant.
enum GpsSharingMode {
  /// No sharing. Toggling here also clears the radio's stored coords (0,0).
  off,

  /// Only share when the user explicitly taps "Partilhar agora" / map FAB.
  manual,

  /// Background timer pushes the phone GPS on every [GpsSharingSettings.intervalMinutes].
  auto,
}

/// Privacy granularity applied before sending coords to the radio.
enum GpsSharingPrecision {
  /// Send the raw fix (sub-meter precision).
  exact,

  /// Round to ~100 m (3 decimal places).
  rounded100m,

  /// Round to ~1 km (2 decimal places).
  rounded1km;

  int get decimals => switch (this) {
    GpsSharingPrecision.exact => 6,
    GpsSharingPrecision.rounded100m => 3,
    GpsSharingPrecision.rounded1km => 2,
  };

  double apply(double value) {
    final m = _pow10(decimals);
    return (value * m).round() / m;
  }
}

double _pow10(int n) {
  var v = 1.0;
  for (var i = 0; i < n; i++) {
    v *= 10;
  }
  return v;
}

class GpsSharingSettings extends Equatable {
  const GpsSharingSettings({
    this.mode = GpsSharingMode.off,
    this.precision = GpsSharingPrecision.rounded100m,
    this.intervalMinutes = 15,
    this.minMoveMeters = 50,
    this.lastSharedAtEpoch,
    this.lastSharedLat,
    this.lastSharedLon,
  });

  factory GpsSharingSettings.fromJson(Map<String, dynamic> json) {
    return GpsSharingSettings(
      mode: GpsSharingMode.values.firstWhere(
        (m) => m.name == json['mode'],
        orElse: () => GpsSharingMode.off,
      ),
      precision: GpsSharingPrecision.values.firstWhere(
        (p) => p.name == json['precision'],
        orElse: () => GpsSharingPrecision.rounded100m,
      ),
      intervalMinutes: (json['intervalMinutes'] as num?)?.toInt() ?? 15,
      minMoveMeters: (json['minMoveMeters'] as num?)?.toInt() ?? 50,
      lastSharedAtEpoch: (json['lastSharedAtEpoch'] as num?)?.toInt(),
      lastSharedLat: (json['lastSharedLat'] as num?)?.toDouble(),
      lastSharedLon: (json['lastSharedLon'] as num?)?.toDouble(),
    );
  }

  final GpsSharingMode mode;
  final GpsSharingPrecision precision;
  final int intervalMinutes;

  /// Minimum movement in meters before Auto mode pushes a new fix.
  /// 0 = always push (legacy behaviour). Recommended 50 m.
  final int minMoveMeters;

  /// Unix epoch (seconds) of the most recent successful push.
  final int? lastSharedAtEpoch;
  final double? lastSharedLat;
  final double? lastSharedLon;

  bool get isEnabled => mode != GpsSharingMode.off;
  bool get isAuto => mode == GpsSharingMode.auto;

  GpsSharingSettings copyWith({
    GpsSharingMode? mode,
    GpsSharingPrecision? precision,
    int? intervalMinutes,
    int? minMoveMeters,
    int? lastSharedAtEpoch,
    double? lastSharedLat,
    double? lastSharedLon,
    bool clearLastShared = false,
  }) {
    return GpsSharingSettings(
      mode: mode ?? this.mode,
      precision: precision ?? this.precision,
      intervalMinutes: intervalMinutes ?? this.intervalMinutes,
      minMoveMeters: minMoveMeters ?? this.minMoveMeters,
      lastSharedAtEpoch:
          clearLastShared
              ? null
              : (lastSharedAtEpoch ?? this.lastSharedAtEpoch),
      lastSharedLat:
          clearLastShared ? null : (lastSharedLat ?? this.lastSharedLat),
      lastSharedLon:
          clearLastShared ? null : (lastSharedLon ?? this.lastSharedLon),
    );
  }

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'precision': precision.name,
    'intervalMinutes': intervalMinutes,
    'minMoveMeters': minMoveMeters,
    if (lastSharedAtEpoch != null) 'lastSharedAtEpoch': lastSharedAtEpoch,
    if (lastSharedLat != null) 'lastSharedLat': lastSharedLat,
    if (lastSharedLon != null) 'lastSharedLon': lastSharedLon,
  };

  @override
  List<Object?> get props => [
    mode,
    precision,
    intervalMinutes,
    minMoveMeters,
    lastSharedAtEpoch,
    lastSharedLat,
    lastSharedLon,
  ];
}

const _kStorageKey = 'gps_sharing_v1';

class GpsSharingNotifier extends StateNotifier<GpsSharingSettings> {
  GpsSharingNotifier() : super(const GpsSharingSettings());

  Future<void> loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kStorageKey);
      if (raw == null) return;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      state = GpsSharingSettings.fromJson(json);
    } catch (_) {
      // Corrupt blob — fall back to defaults.
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kStorageKey, jsonEncode(state.toJson()));
    } catch (_) {}
  }

  Future<void> setMode(GpsSharingMode mode) async {
    if (state.mode == mode) return;
    state = state.copyWith(mode: mode);
    if (mode == GpsSharingMode.off) {
      // Clearing last-shared makes the UI honest about "no longer broadcasting".
      state = state.copyWith(clearLastShared: true);
    }
    await _persist();
  }

  Future<void> setPrecision(GpsSharingPrecision p) async {
    if (state.precision == p) return;
    state = state.copyWith(precision: p);
    await _persist();
  }

  Future<void> setIntervalMinutes(int minutes) async {
    final clamped = minutes.clamp(1, 240);
    if (state.intervalMinutes == clamped) return;
    state = state.copyWith(intervalMinutes: clamped);
    await _persist();
  }

  Future<void> setMinMoveMeters(int meters) async {
    final clamped = meters.clamp(0, 5000);
    if (state.minMoveMeters == clamped) return;
    state = state.copyWith(minMoveMeters: clamped);
    await _persist();
  }

  /// Record that we pushed coords to the radio (used by the service).
  Future<void> markShared(double lat, double lon) async {
    state = state.copyWith(
      lastSharedAtEpoch: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      lastSharedLat: lat,
      lastSharedLon: lon,
    );
    await _persist();
  }

  Future<void> clearLastShared() async {
    state = state.copyWith(clearLastShared: true);
    await _persist();
  }
}

final gpsSharingProvider =
    StateNotifierProvider<GpsSharingNotifier, GpsSharingSettings>(
      (ref) => GpsSharingNotifier(),
    );
