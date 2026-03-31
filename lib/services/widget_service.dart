import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:home_widget/home_widget.dart';

/// Pushes radio state to the Android home screen widget.
///
/// All calls are no-ops on web and iOS — the widget only exists on Android.
class WidgetService {
  WidgetService._();

  static const _androidProvider = 'MeshCoreWidgetProvider';

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  /// Update all widget fields and request a redraw.
  ///
  /// [radioName]    — radio node name (e.g. "GZ7d0 C8/M")
  /// [connected]    — whether the radio is currently connected
  /// [batteryPct]   — battery percentage 0–100 (0 when unknown)
  /// [contactCount] — number of known contacts
  /// [channelCount] — number of named channels
  static Future<void> update({
    required String radioName,
    required bool connected,
    required int batteryPct,
    required int contactCount,
    required int channelCount,
  }) async {
    if (!_supported) return;
    try {
      final now = DateTime.now();
      final ts =
          '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}';

      await Future.wait([
        HomeWidget.saveWidgetData<String>('radio_name', radioName),
        HomeWidget.saveWidgetData<bool>('connected', connected),
        HomeWidget.saveWidgetData<int>('battery_pct', batteryPct),
        HomeWidget.saveWidgetData<int>('contact_count', contactCount),
        HomeWidget.saveWidgetData<int>('channel_count', channelCount),
        HomeWidget.saveWidgetData<String>('last_updated', ts),
      ]);

      await HomeWidget.updateWidget(androidName: _androidProvider);
    } catch (_) {
      // Widget errors are non-fatal.
    }
  }
}
