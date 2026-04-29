import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../providers/gps_sharing_provider.dart';
import '../providers/radio_providers.dart';
import '../transport/radio_transport.dart' show TransportState;
import 'widget_service.dart';

/// Result of an attempted share-now invocation.
enum GpsShareOutcome {
  ok,
  disabled,
  noPermission,
  serviceDisabled,
  noFix,
  notConnected,
  cleared,
  failed,
  skippedNoMovement,
}

class GpsShareResult {
  GpsShareResult(this.outcome, {this.lat, this.lon, this.error});
  final GpsShareOutcome outcome;
  final double? lat;
  final double? lon;
  final Object? error;
}

/// Glue between [gpsSharingProvider] settings and the connected radio.
///
/// Responsibilities:
/// * In Auto mode: every `intervalMinutes`, pull a fresh phone fix and push it
///   via `radioService.setLocation(lat, lon)`.
/// * In Manual mode: do nothing automatic; expose `shareNow()` for UI buttons.
/// * In Off mode: send a single `setLocation(0, 0)` to clear stored coords on
///   the radio when the user just turned sharing off (and stop the timer).
///
/// The user is always in charge — `shareNow()` and the timer never request
/// location without an explicit setting being switched on.
class GpsSharingService {
  GpsSharingService(this._ref) {
    // React to settings changes.
    _settingsSub = _ref.listen<GpsSharingSettings>(
      gpsSharingProvider,
      (prev, next) => _onSettingsChanged(prev, next),
      fireImmediately: false,
    );
    // React to connection state changes — start/stop timer accordingly.
    _connSub = _ref.listen<TransportState>(
      connectionProvider,
      (prev, next) => _onConnectionChanged(next),
      fireImmediately: false,
    );
  }

  final Ref _ref;
  // ignore: unused_field
  late final ProviderSubscription<GpsSharingSettings> _settingsSub;
  // ignore: unused_field
  late final ProviderSubscription<TransportState> _connSub;
  Timer? _timer;
  bool _busy = false;

  void dispose() {
    _timer?.cancel();
    _settingsSub.close();
    _connSub.close();
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Push the phone's current GPS fix to the radio once.
  /// Returns a structured outcome the UI can show to the user.
  ///
  /// When [enforceMinMove] is true (used by the periodic Auto timer), a fix
  /// closer than [GpsSharingSettings.minMoveMeters] from the last shared
  /// position is skipped to save LoRa air-time.
  Future<GpsShareResult> shareNow({
    bool requireSettingEnabled = true,
    bool enforceMinMove = false,
  }) async {
    final settings = _ref.read(gpsSharingProvider);
    if (requireSettingEnabled && !settings.isEnabled) {
      return GpsShareResult(GpsShareOutcome.disabled);
    }
    final svc = _ref.read(radioServiceProvider);
    final connected = _ref.read(connectionProvider) == TransportState.connected;
    if (svc == null || !connected) {
      return GpsShareResult(GpsShareOutcome.notConnected);
    }
    if (_busy) return GpsShareResult(GpsShareOutcome.failed);
    _busy = true;
    try {
      final permResult = await _ensurePermission();
      if (permResult != null) return permResult;

      final pos = await Geolocator.getCurrentPosition(
        // Medium accuracy is plenty after rounding; saves battery.
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 12),
        ),
      );
      final lat = settings.precision.apply(pos.latitude);
      final lon = settings.precision.apply(pos.longitude);

      // Move-aware skip — only enforced for Auto timer ticks.
      if (enforceMinMove &&
          settings.minMoveMeters > 0 &&
          settings.lastSharedLat != null &&
          settings.lastSharedLon != null) {
        final dist = _haversineMeters(
          settings.lastSharedLat!,
          settings.lastSharedLon!,
          lat,
          lon,
        );
        if (dist < settings.minMoveMeters) {
          return GpsShareResult(
            GpsShareOutcome.skippedNoMovement,
            lat: lat,
            lon: lon,
          );
        }
      }

      await svc.setLocation(lat, lon);
      await _ref.read(gpsSharingProvider.notifier).markShared(lat, lon);
      _pushWidgetSharing(true);
      return GpsShareResult(GpsShareOutcome.ok, lat: lat, lon: lon);
    } catch (e) {
      return GpsShareResult(GpsShareOutcome.failed, error: e);
    } finally {
      _busy = false;
    }
  }

  /// Tell the radio to forget its stored coords (sentinel 0,0 = "no fix").
  /// Called automatically when the user switches mode → off.
  Future<GpsShareResult> clearOnRadio() async {
    final svc = _ref.read(radioServiceProvider);
    final connected = _ref.read(connectionProvider) == TransportState.connected;
    if (svc == null || !connected) {
      return GpsShareResult(GpsShareOutcome.notConnected);
    }
    try {
      await svc.setLocation(0, 0);
      await _ref.read(gpsSharingProvider.notifier).clearLastShared();
      _pushWidgetSharing(false);
      return GpsShareResult(GpsShareOutcome.cleared);
    } catch (e) {
      return GpsShareResult(GpsShareOutcome.failed, error: e);
    }
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  Future<GpsShareResult?> _ensurePermission() async {
    try {
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      if (!serviceOn) {
        return GpsShareResult(GpsShareOutcome.serviceDisabled);
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return GpsShareResult(GpsShareOutcome.noPermission);
      }
      return null;
    } catch (e) {
      return GpsShareResult(GpsShareOutcome.failed, error: e);
    }
  }

  void _onSettingsChanged(GpsSharingSettings? prev, GpsSharingSettings next) {
    final wasOff = prev == null || prev.mode == GpsSharingMode.off;
    final nowOff = next.mode == GpsSharingMode.off;

    // Reflect enabled/disabled badge on the home-screen widget.
    _pushWidgetSharing(!nowOff);

    // User just switched OFF → push (0,0) to clear and stop timer.
    if (!wasOff && nowOff) {
      _stopTimer();
      // Fire-and-forget; UI feedback comes from the settings card snackbar.
      unawaited(clearOnRadio());
      return;
    }

    // User just switched to AUTO → start timer + immediate share.
    if (next.mode == GpsSharingMode.auto) {
      _startTimer();
      unawaited(shareNow());
      return;
    }

    // Manual or any non-auto state → just stop the timer.
    _stopTimer();
  }

  void _onConnectionChanged(TransportState st) {
    final settings = _ref.read(gpsSharingProvider);
    if (st != TransportState.connected) {
      _stopTimer();
      return;
    }
    if (settings.mode == GpsSharingMode.auto) {
      _startTimer();
      unawaited(shareNow());
    }
  }

  void _startTimer() {
    _timer?.cancel();
    final mins = _ref.read(gpsSharingProvider).intervalMinutes;
    _timer = Timer.periodic(Duration(minutes: mins), (_) {
      final settings = _ref.read(gpsSharingProvider);
      if (settings.mode != GpsSharingMode.auto) return;
      unawaited(shareNow(enforceMinMove: true));
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// Push the live "GPS sharing on/off" badge to the home-screen widget.
  void _pushWidgetSharing(bool active) {
    unawaited(WidgetService.updateGpsSharing(active));
  }

  /// Great-circle distance in meters between two WGS-84 coordinates.
  static double _haversineMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const r = 6371000.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  static double _deg2rad(double d) => d * math.pi / 180.0;
}

/// Wires a single [GpsSharingService] alive for the app's lifetime.
final gpsSharingServiceProvider = Provider<GpsSharingService>((ref) {
  final svc = GpsSharingService(ref);
  ref.onDispose(svc.dispose);
  return svc;
});
