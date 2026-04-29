import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'storage_service.dart';

/// Wraps [FlutterLocalNotificationsPlugin] and exposes a simple API for
/// firing message notifications, respecting the user's [NotificationSettings].
///
/// Platforms:
/// - Android: uses a dedicated high-importance channel "meshcore_messages".
/// - iOS / macOS: uses UNUserNotificationCenter alerts.
/// - Windows / Linux: supported by flutter_local_notifications >= 18.
/// - Web: notifications are unsupported; all calls are no-ops.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const _androidChannelId = 'meshcore_messages';
  static const _androidChannelName = 'Mensagens MeshCore';
  static const _androidChannelDesc =
      'Notificacoes de mensagens privadas e de canal';

  static const _plan333ChannelId = 'plan333_alerts';
  static const _plan333ChannelName = 'Alertas Plano 3-3-3';
  static const _plan333ChannelDesc =
      'Lembretes das janelas de escuta do Plano 3-3-3';

  // Notification IDs for Saturday Mesh 3-3-3 reminders.
  static const _plan333Remind10Id = 1008; // 10 min before (20:50)
  static const _plan333Remind5Id = 1009; //  5 min before (20:55)
  // Lisbon timezone — correct for the Portuguese Plano 3-3-3.
  static const _lisbon = 'Europe/Lisbon';

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  int _nextId = 0;

  /// Called when the user taps a notification while the app is running or
  /// resumes from background.  Set this from main.dart after the router is
  /// ready.  Receives the payload string, e.g. "private:<keyHex>" or
  /// "channel:<index>".
  static void Function(String payload)? onTap;

  /// Notification settings, loaded from storage and kept in sync by
  /// [NotificationSettingsNotifier].  Updated externally via [settings].
  NotificationSettings _settings = const NotificationSettings();

  set settings(NotificationSettings s) => _settings = s;

  /// Initialise the plugin.  Must be called once, before any `show*` call.
  Future<void> init() async {
    if (_initialized) return;

    // Web has no local notification support.
    if (kIsWeb) {
      _initialized = true;
      return;
    }

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const macSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const linuxSettings = LinuxInitializationSettings(
      defaultActionName: 'Abrir',
    );

    InitializationSettings initSettings;

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        initSettings = const InitializationSettings(android: androidSettings);
      case TargetPlatform.iOS:
        initSettings = const InitializationSettings(iOS: iosSettings);
      case TargetPlatform.macOS:
        initSettings = const InitializationSettings(macOS: macSettings);
      case TargetPlatform.linux:
        initSettings = const InitializationSettings(linux: linuxSettings);
      case TargetPlatform.windows:
        // Windows initialisation — no special settings needed beyond defaults.
        initSettings = const InitializationSettings();
      default:
        _initialized = true;
        return;
    }

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        final payload = details.payload;
        if (payload != null && payload.isNotEmpty) {
          NotificationService.onTap?.call(payload);
        }
      },
    );

    // Create Android notification channels once.
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android =
          _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _androidChannelId,
          _androidChannelName,
          description: _androidChannelDesc,
          importance: Importance.high,
          playSound: true,
        ),
      );
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _plan333ChannelId,
          _plan333ChannelName,
          description: _plan333ChannelDesc,
          importance: Importance.high,
          playSound: true,
        ),
      );
    }

    _initialized = true;
  }

  /// Request the OS notification permission (Android 13+, iOS, macOS).
  /// Returns true if granted.
  Future<bool> requestPermission() async {
    if (kIsWeb) return false;

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        final impl =
            _plugin
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >();
        return (await impl?.requestNotificationsPermission()) ?? false;
      case TargetPlatform.iOS:
        final impl =
            _plugin
                .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin
                >();
        return (await impl?.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            )) ??
            false;
      case TargetPlatform.macOS:
        final impl =
            _plugin
                .resolvePlatformSpecificImplementation<
                  MacOSFlutterLocalNotificationsPlugin
                >();
        return (await impl?.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            )) ??
            false;
      default:
        return true;
    }
  }

  /// Check whether the OS has granted notification permission.
  Future<bool> isPermissionGranted() async {
    if (kIsWeb) return false;
    if (defaultTargetPlatform == TargetPlatform.android) {
      final impl =
          _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();
      return (await impl?.areNotificationsEnabled()) ?? false;
    }
    // iOS/macOS/Windows/Linux — assume granted (checked during request).
    return true;
  }

  /// Show a notification for an incoming private message.
  ///
  /// [senderName] — display name of the sender.
  /// [text] — message body (may be empty for non-text messages).
  /// [senderKeyHex] — full hex public key of the sender; used as navigation
  ///   payload so tapping the notification opens the correct chat.
  /// [isAppInForeground] — pass the current app lifecycle state to honour the
  ///   "only when background" setting.
  Future<void> showPrivateMessage({
    required String senderName,
    required String text,
    String? senderKeyHex,
    bool isAppInForeground = false,
  }) async {
    if (!_shouldSend(
      categoryEnabled: _settings.privateMessages,
      isAppInForeground: isAppInForeground,
    )) {
      return;
    }

    await _show(
      title: senderName,
      body: text.isNotEmpty ? text : '(mensagem recebida)',
      payload: senderKeyHex != null ? 'private:$senderKeyHex' : null,
    );
  }

  /// Show a notification for an incoming channel message.
  ///
  /// [channelName] — name of the channel (may be 'Canal N' if unnamed).
  /// [channelIndex] — channel slot index; used as navigation payload.
  /// [senderName] — display name of the sender.
  /// [text] — message body.
  Future<void> showChannelMessage({
    required String channelName,
    required String senderName,
    required String text,
    int? channelIndex,
    bool isAppInForeground = false,
  }) async {
    if (!_shouldSend(
      categoryEnabled: _settings.channelMessages,
      isAppInForeground: isAppInForeground,
    )) {
      return;
    }

    await _show(
      title: channelName,
      body: '$senderName: ${text.isNotEmpty ? text : "(mensagem)"}',
      payload: channelIndex != null ? 'channel:$channelIndex' : null,
    );
  }

  // ---------------------------------------------------------------------------
  // Plan 3-3-3 scheduled alerts
  // ---------------------------------------------------------------------------

  // Platforms that support zonedSchedule (timed repeating notifications).
  static bool get _supportsZonedSchedule =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  /// Fire an immediate test notification to verify the notification channel.
  /// Debug / diagnostic use only.
  Future<String> showPlan333TestNotification() async {
    if (!_initialized) return 'Serviço não inicializado';
    if (kIsWeb) return 'Notificações não suportadas na web';

    const androidDetails = AndroidNotificationDetails(
      _plan333ChannelId,
      _plan333ChannelName,
      channelDescription: _plan333ChannelDesc,
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
      macOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
    );

    await _plugin.show(
      1099,
      'Mesh 3-3-3 — Teste',
      'Notificação de teste. Sistema de alertas a funcionar!',
      details,
    );
    return 'OK';
  }

  /// Returns how many Plan333 reminders are currently pending in the OS.
  Future<int> pendingPlan333Count() async {
    if (!_initialized || kIsWeb) return 0;
    if (!_supportsZonedSchedule) return 0;
    final all = await _plugin.pendingNotificationRequests();
    return all
        .where((n) => n.id == _plan333Remind10Id || n.id == _plan333Remind5Id)
        .length;
  }

  /// Schedule 8 daily window alerts + 1 weekly Saturday training reminder.
  /// Safe to call multiple times — cancels existing Plan333 notifications first.
  Future<void> schedulePlan333Alerts() async {
    if (!_initialized || kIsWeb) return;
    // zonedSchedule is only available on Android, iOS, and macOS.
    if (!_supportsZonedSchedule) return;

    await cancelPlan333Alerts();

    final location = tz.getLocation(_lisbon);

    const androidDetails = AndroidNotificationDetails(
      _plan333ChannelId,
      _plan333ChannelName,
      channelDescription: _plan333ChannelDesc,
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
      macOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
    );

    final now = tz.TZDateTime.now(location);

    // Helper: next Saturday at a given hour:minute.
    tz.TZDateTime nextSaturday(int hour, int minute) {
      var t = tz.TZDateTime(
        location,
        now.year,
        now.month,
        now.day,
        hour,
        minute,
      );
      if (t.isBefore(now)) t = t.add(const Duration(days: 1));
      while (t.weekday != DateTime.saturday) {
        t = t.add(const Duration(days: 1));
      }
      return t;
    }

    // 10 min before Mesh 3-3-3 (20:50 Saturday)
    await _plugin.zonedSchedule(
      _plan333Remind10Id,
      'Mesh 3-3-3 — em 10 minutos!',
      'O evento semanal de sábado começa às 21:00.',
      nextSaturday(20, 50),
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );

    // 5 min before Mesh 3-3-3 (20:55 Saturday)
    await _plugin.zonedSchedule(
      _plan333Remind5Id,
      'Mesh 3-3-3 — em 5 minutos!',
      'Prepare o rádio para o evento semanal às 21:00.',
      nextSaturday(20, 55),
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// Returns the payload string from the notification that launched the app
  /// (cold-start / killed-state tap), or null if the app was not launched via
  /// a notification.  Call this once during startup, after [init].
  Future<String?> getAppLaunchPayload() async {
    if (!_initialized || kIsWeb) return null;
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) return null;
    return details.notificationResponse?.payload;
  }

  /// Cancel all Plan 3-3-3 scheduled notifications.
  Future<void> cancelPlan333Alerts() async {
    if (!_initialized || kIsWeb) return;
    if (!_supportsZonedSchedule) return;
    await _plugin.cancel(_plan333Remind10Id);
    await _plugin.cancel(_plan333Remind5Id);
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  bool _shouldSend({
    required bool categoryEnabled,
    required bool isAppInForeground,
  }) {
    if (!_initialized) return false;
    if (kIsWeb) return false;
    if (!_settings.enabled) return false;
    if (!categoryEnabled) return false;
    if (_settings.onlyWhenBackground && isAppInForeground) return false;
    return true;
  }

  Future<void> _show({
    required String title,
    required String body,
    String? payload,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      _androidChannelId,
      _androidChannelName,
      channelDescription: _androidChannelDesc,
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
    );
    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      macOS: iosDetails,
    );

    await _plugin.show(_nextId++, title, body, details, payload: payload);
  }
}

/// AppLifecycleState tracker used by the notification service to decide
/// whether the app is in the foreground.
///
/// Register once with [WidgetsBinding.instance.addObserver] in main.dart.
class AppLifecycleObserver extends WidgetsBindingObserver {
  static AppLifecycleState _state = AppLifecycleState.resumed;

  static bool get isInForeground => _state == AppLifecycleState.resumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _state = state;
  }
}
