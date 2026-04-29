import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;

import 'providers/radio_providers.dart';
import 'providers/canned_messages_provider.dart';
import 'protocol/protocol.dart' show ChatMessage;
import 'transport/radio_transport.dart' show TransportState;
import 'services/notification_service.dart';
import 'services/plan333_service.dart';
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
      // Eagerly initialize the auto-send notifier (starts background timer).
      ref.read(plan333AutoSendProvider);
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
        router.go('/connect');
      case WidgetAction.sendAdvert:
        final svc = ref.read(radioServiceProvider);
        final connected =
            ref.read(connectionProvider) == TransportState.connected;
        final messenger = ScaffoldMessenger.maybeOf(context);
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
        final svc = ref.read(radioServiceProvider);
        final connected =
            ref.read(connectionProvider) == TransportState.connected;
        final messenger = ScaffoldMessenger.maybeOf(context);
        final emergency = ref.read(cannedMessagesProvider.notifier).emergency;
        if (emergency == null) {
          messenger?.showSnackBar(
            const SnackBar(
              content: Text(
                '🆘 Sem mensagem de emergência configurada — abre Definições',
              ),
              duration: Duration(seconds: 3),
            ),
          );
          router.go('/settings');
          break;
        }
        if (svc == null || !connected) {
          messenger?.showSnackBar(
            const SnackBar(
              content: Text('Rádio desligado — liga para enviar SOS'),
              duration: Duration(seconds: 3),
            ),
          );
          router.go('/connect');
          break;
        }
        final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        ref
            .read(messagesProvider.notifier)
            .addOutgoing(
              ChatMessage(
                text: emergency.text,
                timestamp: ts,
                isOutgoing: true,
                channelIndex: 0,
              ),
            );
        svc.sendChannelMessage(0, emergency.text, timestamp: ts);
        messenger?.showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFD32F2F),
            content: Text(
              '🆘 Emergência enviada: ${emergency.text}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            duration: const Duration(seconds: 4),
          ),
        );
        router.go('/channels');
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    final accent = ref.watch(accentColorProvider);

    return MaterialApp.router(
      title: 'LusoAPP',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(brightness: Brightness.light, accent: accent),
      darkTheme: AppTheme.build(brightness: Brightness.dark, accent: accent),
      themeMode: themeMode,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    );
  }
}
