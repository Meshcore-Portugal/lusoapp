import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;

import 'providers/radio_providers.dart';
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
    if (mounted) {
      await ref.read(notificationSettingsProvider.notifier).loadFromStorage();
      await ref.read(plan333EnabledProvider.notifier).loadFromStorage();
      await ref.read(plan333ConfigProvider.notifier).loadFromStorage();
      await ref.read(qslLogProvider.notifier).loadFromStorage();
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
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    // Watch persisted theme preference — replaces the former hardcoded ThemeMode.dark.
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'LusoAPP',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    );
  }
}
