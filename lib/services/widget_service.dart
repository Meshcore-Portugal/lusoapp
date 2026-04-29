import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:home_widget/home_widget.dart';

/// Pushes radio state to the Android home screen widget and routes
/// widget button taps back to the app.
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

  // ---------------------------------------------------------------------------
  // Click handling — routes widget button taps back to the app.
  // ---------------------------------------------------------------------------

  /// Callback fired when a widget button is tapped.
  static void Function(WidgetAction action)? onAction;

  static StreamSubscription<Uri?>? _clickSub;

  /// Wire the widget click stream and dispatch the cold-start launch URI.
  /// Safe to call on every platform — no-ops outside Android.
  static Future<void> registerClickHandlers() async {
    if (!_supported) return;
    try {
      // Cold start: app was launched by tapping a widget button.
      final initialUri = await HomeWidget.initiallyLaunchedFromHomeWidget();
      if (initialUri != null) _dispatch(initialUri);

      // Warm start: app was already alive and a widget button was tapped.
      await _clickSub?.cancel();
      _clickSub = HomeWidget.widgetClicked.listen((uri) {
        if (uri != null) _dispatch(uri);
      });
    } catch (_) {
      // Non-fatal — widget interactivity simply won't work.
    }
  }

  static void _dispatch(Uri uri) {
    final action = WidgetAction.fromUri(uri);
    if (action == null) return;
    onAction?.call(action);
  }
}

/// Discrete actions the home-screen widget can request.
enum WidgetAction {
  /// Tap on the widget header — just bring the app to the foreground.
  open,

  /// Send an advert from the connected radio (no-op when disconnected).
  sendAdvert,

  /// Broadcast the user's emergency canned message on channel 0.
  sendEmergency,

  /// Navigate to the channels list.
  openChats,

  /// Navigate to the map screen.
  openMap,

  /// Navigate to the connect screen (device picker).
  openConnect;

  static WidgetAction? fromUri(Uri uri) {
    if (uri.scheme != 'meshcore-widget') return null;
    final path = '${uri.host}${uri.path}'; // host is "open" or "action"/"nav"
    return switch (path) {
      'open' => WidgetAction.open,
      'action/advert' => WidgetAction.sendAdvert,
      'action/sos' => WidgetAction.sendEmergency,
      'nav/channels' => WidgetAction.openChats,
      'nav/map' => WidgetAction.openMap,
      'nav/connect' => WidgetAction.openConnect,
      _ => null,
    };
  }
}
