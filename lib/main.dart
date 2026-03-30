import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/radio_providers.dart';
import 'services/notification_service.dart';
import 'services/storage_service.dart';
import 'ui/router.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

    // Restore cached channels for offline browsing.
    await ref.read(channelsProvider.notifier).loadFromStorage();

    // Restore last connected device for the quick-connect card.
    final last = await StorageService.instance.loadLastDevice();
    if (last != null && mounted) {
      ref.read(lastDeviceProvider.notifier).state = last;
    }

    // Initialise the local notification service and load saved settings.
    await NotificationService.instance.init();
    if (mounted) {
      await ref.read(notificationSettingsProvider.notifier).loadFromStorage();
      await ref.read(favoritesProvider.notifier).loadFromStorage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'MeshCore PT',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: router,
    );
  }
}
