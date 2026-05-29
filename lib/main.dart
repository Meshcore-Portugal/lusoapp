import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;

import 'providers/radio_providers.dart';
import 'providers/canned_messages_provider.dart';
import 'providers/gps_sharing_provider.dart';
import 'providers/map_visibility_provider.dart';
import 'providers/sos_settings_provider.dart';
import 'services/gps_sharing_service.dart';
import 'transport/radio_transport.dart' show ConnectionMode, TransportState;
import 'services/notification_service.dart';
import 'services/plan333_service.dart';
import 'services/sos_service.dart';
import 'services/storage_service.dart';
import 'services/widget_service.dart';
import 'l10n/l10n.dart';
import 'ui/router.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Timezone data required for Plan 3-3-3 scheduled notifications.
  tz_data.initializeTimeZones();

  if (!kIsWeb) {
    await FMTCObjectBoxBackend().initialise();
    await const FMTCStore('mapStore').manage.create();
  }

  runApp(const ProviderScope(child: McAppPt()));
}

class McAppPt extends ConsumerStatefulWidget {
  const McAppPt({super.key});

  @override
  ConsumerState<McAppPt> createState() => _McAppPtState();
}

final _lifecycleObserver = AppLifecycleObserver();

class _McAppPtState extends ConsumerState<McAppPt> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
    _initStorage();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    super.dispose();
  }

  Future<void> _initStorage() async {
    // Restore cached contacts so the contacts screen is populated
    // before the user connects to a radio.
    await ref.read(contactsProvider.notifier).loadFromStorage();

    // Restore persisted unread counts so badges survive app restarts.
    await ref.read(unreadCountsProvider.notifier).loadFromStorage();

    // Restore persisted message paths so path details are available after reboot.
    await ref.read(packetHeardProvider.notifier).loadFromStorage();

    // Restore the recent-devices list (most-recent first) for the
    // multi-radio quick-connect section.  loadRecentDevices() handles
    // one-time migration from the legacy single-device keys.
    final recent = await StorageService.instance.loadRecentDevices();
    if (mounted) {
      ref.read(recentDevicesProvider.notifier).state = recent;
      if (recent.isNotEmpty) {
        ref.read(lastDeviceProvider.notifier).state = recent.first;
      }
    }

    // Restore cached channels for offline browsing.
    // Load from the device-scoped store when a previous device is known,
    // so that channels are correctly associated with the last radio used.
    if (recent.isNotEmpty) {
      await ref
          .read(channelsProvider.notifier)
          .loadFromStorageForRadio(recent.first.id);
    } else {
      // Fallback: no known device yet — load from the legacy global key.
      await ref.read(channelsProvider.notifier).loadFromStorage();
    }

    // Initialise the local notification service and load saved settings.
    await NotificationService.instance.init();

    // Wire notification tap → in-app navigation (foreground / background).
    NotificationService.onTap = (payload) {
      final router = ref.read(routerProvider);
      if (payload.startsWith('private:')) {
        final keyHex = payload.substring('private:'.length);
        router.go('/chat/$keyHex');
      } else if (payload.startsWith('channel:')) {
        final index = int.tryParse(payload.substring('channel:'.length));
        if (index != null) router.go('/channels/$index');
      }
    };

    // Handle cold-start: app was launched by tapping a notification.
    final launchPayload =
        await NotificationService.instance.getAppLaunchPayload();
    if (launchPayload != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        NotificationService.onTap?.call(launchPayload);
      });
    }

    if (mounted) {
      await ref.read(notificationSettingsProvider.notifier).loadFromStorage();
      await ref.read(plan333EnabledProvider.notifier).loadFromStorage();
      await ref.read(plan333ConfigProvider.notifier).loadFromStorage();
      await ref.read(qslLogProvider.notifier).loadFromStorage();
      await ref.read(cannedMessagesProvider.notifier).loadFromStorage();
      await ref.read(gpsSharingProvider.notifier).loadFromStorage();

      // Restore SOS destination/template settings.
      await ref.read(sosSettingsProvider.notifier).loadFromStorage();
      await ref.read(mapHiddenContactsProvider.notifier).loadFromStorage();
      // Eagerly initialize the auto-send notifier (starts background timer).
      ref.read(plan333AutoSendProvider);
      // Eagerly initialize the GPS sharing service so its listeners attach
      // and the timer starts if the user previously enabled Auto mode.
      ref.read(gpsSharingServiceProvider);
    }

    // Push initial widget state with cached data (or disconnected state).
    if (mounted) {
      final selfInfo = ref.read(selfInfoProvider);
      final contacts = ref.read(contactsProvider);
      final channels = ref.read(channelsProvider);

      await WidgetService.update(
        radioName: selfInfo?.name ?? '—',
        connected: false,
        batteryPct: 0,
        contactCount: contacts.length,
        channelCount: channels.where((c) => !c.isEmpty).length,
        gpsSharing: ref.read(gpsSharingProvider).isEnabled,
      );
    }

    // Wire home-screen widget button taps → in-app actions.
    WidgetService.onAction = _handleWidgetAction;
    await WidgetService.registerClickHandlers();
  }

  void _handleWidgetAction(WidgetAction action) {
    if (!mounted) return;
    final router = ref.read(routerProvider);
    switch (action) {
      case WidgetAction.open:
        // Just bring the app to the foreground — no navigation change.
        break;
      case WidgetAction.openChats:
        router.go('/channels');
      case WidgetAction.openMap:
        router.go('/map');
      case WidgetAction.openConnect:
        _handlePowerToggle();
      case WidgetAction.openPlan333:
        router.go('/apps/plan333');
      case WidgetAction.openTelemetry:
        router.go('/apps/telemetry');
      case WidgetAction.sendAdvert:
        final svc = ref.read(radioServiceProvider);
        final connected =
            ref.read(connectionProvider) == TransportState.connected;
        final messenger = _rootMessenger();
        if (svc != null && connected) {
          svc.sendAdvert(flood: false);
          messenger?.showSnackBar(
            const SnackBar(
              content: Text('📡 Anúncio enviado'),
              duration: Duration(seconds: 2),
            ),
          );
        } else {
          messenger?.showSnackBar(
            const SnackBar(
              content: Text('Rádio desligado — liga primeiro'),
              duration: Duration(seconds: 2),
            ),
          );
          router.go('/connect');
        }
      case WidgetAction.sendEmergency:
        final messenger = _rootMessenger();
        final emergency = ref.read(cannedMessagesProvider.notifier).emergency;
        final base = emergency?.text;
        final result = ref
            .read(sosServiceProvider)
            .sendConfiguredSos(baseTextOverride: base);

        result.then((r) {
          if (!mounted) return;
          switch (r.outcome) {
            case SosSendOutcome.sent:
              messenger?.showSnackBar(
                const SnackBar(
                  backgroundColor: Color(0xFFD32F2F),
                  content: Text(
                    '🆘 SOS enviado',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  duration: Duration(seconds: 4),
                ),
              );
              router.go('/channels');
            case SosSendOutcome.notConnected:
              messenger?.showSnackBar(
                const SnackBar(
                  content: Text('Rádio desligado — liga para enviar SOS'),
                  duration: Duration(seconds: 3),
                ),
              );
              router.go('/connect');
            case SosSendOutcome.missingContact:
              messenger?.showSnackBar(
                const SnackBar(
                  content: Text(
                    '🆘 Contacto SOS não configurado/encontrado — abre Definições',
                  ),
                  duration: Duration(seconds: 3),
                ),
              );
              router.go('/settings');
            case SosSendOutcome.permissionDenied:
            case SosSendOutcome.locationDisabled:
            case SosSendOutcome.failed:
              messenger?.showSnackBar(
                SnackBar(
                  content: Text(
                    r.detail?.isNotEmpty == true
                        ? 'Falha ao enviar SOS: ${r.detail}'
                        : 'Falha ao enviar SOS',
                  ),
                  duration: const Duration(seconds: 3),
                ),
              );
              router.go('/settings');
          }
        });
    }
  }

  /// Resolve the app's `ScaffoldMessenger` from the root navigator context.
  /// Widget click dispatch runs from `_McAppPtState`, whose `context` lives
  /// *above* `MaterialApp` and therefore has neither `MaterialLocalizations`
  /// nor a `ScaffoldMessenger` ancestor — so `ScaffoldMessenger.maybeOf(context)`
  /// silently returns null and snackbars never appear.
  ScaffoldMessengerState? _rootMessenger() {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null) return null;
    return ScaffoldMessenger.maybeOf(ctx);
  }

  /// Widget power button: toggle the radio connection with a confirmation
  /// dialog in both directions. When disconnected and a previously used
  /// device is known, reconnect to it directly; otherwise route to the
  /// connect screen so the user can pick a device.
  Future<void> _handlePowerToggle() async {
    if (!mounted) return;
    final router = ref.read(routerProvider);
    final connection = ref.read(connectionProvider.notifier);
    final state = ref.read(connectionProvider);
    // Dialogs need a context with MaterialLocalizations — the McAppPt
    // `context` sits above MaterialApp and would fail the assertion. The
    // root navigator's context is inside the MaterialApp subtree.
    final navContext = rootNavigatorKey.currentContext;
    if (navContext == null) return;

    if (state == TransportState.connected) {
      final confirm = await showDialog<bool>(
        context: navContext,
        builder:
            (ctx) => AlertDialog(
              title: const Text('Desligar rádio?'),
              content: const Text('A ligação ao rádio será terminada.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Desligar'),
                ),
              ],
            ),
      );
      if (confirm == true && mounted) {
        await connection.disconnect();
      }
      return;
    }

    final last = ref.read(lastDeviceProvider);
    if (last == null) {
      router.go('/connect');
      return;
    }

    final confirm = await showDialog<bool>(
      context: navContext,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Ligar ao rádio?'),
            content: Text('Vai ligar ao último dispositivo: ${last.name}.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Ligar'),
              ),
            ],
          ),
    );
    if (confirm != true || !mounted) return;

    bool ok;
    switch (last.type) {
      case 'ble':
        ok = await connection.connectBle(last.id, last.name);
      case 'serialKiss':
        ok = await connection.connectSerial(
          last.id,
          last.name,
          mode: ConnectionMode.kiss,
        );
      case 'webSerial':
        ok = await connection.connectWebSerial(
          last.id,
          last.name,
          mode: ConnectionMode.companion,
        );
      case 'webSerialKiss':
        ok = await connection.connectWebSerial(
          last.id,
          last.name,
          mode: ConnectionMode.kiss,
        );
      default:
        ok = await connection.connectSerial(
          last.id,
          last.name,
          mode: ConnectionMode.companion,
        );
    }
    if (!mounted || ok) return;
    _rootMessenger()?.showSnackBar(
      const SnackBar(
        content: Text('Falha ao ligar ao dispositivo'),
        duration: Duration(seconds: 3),
      ),
    );
    router.go('/connect');
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    final accent = ref.watch(accentColorProvider);
    final appTextScale = ref.watch(appTextScaleProvider);

    return MaterialApp.router(
      title: 'LusoAPP',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(brightness: Brightness.light, accent: accent),
      darkTheme: AppTheme.build(brightness: Brightness.dark, accent: accent),
      themeMode: themeMode,
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: TextScaler.linear(appTextScale),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    );
  }
}
