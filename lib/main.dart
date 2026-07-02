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
import 'transport/radio_transport.dart' show TransportState;
import 'services/notification_service.dart';
import 'services/plan333_service.dart';
import 'services/sos_service.dart';
import 'services/storage_service.dart';
import 'services/widget_service.dart';
import 'protocol/models.dart';
import 'l10n/l10n.dart';
import 'ui/router.dart' show routerProvider, rootNavigatorKey;
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
  ProviderSubscription<DeviceInfo?>? _deviceInfoSub;
  ProviderSubscription<TransportState>? _connectionSub;
  bool _didShowPathHashMigrationModal = false;
  bool _didApplyPathHashMigration = false;
  bool _isStorageReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
    _listenPathHashMigrationNotice();
    _initStorage();
  }

  @override
  void dispose() {
    _deviceInfoSub?.close();
    _connectionSub?.close();
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    super.dispose();
  }

  void _listenPathHashMigrationNotice() {
    _deviceInfoSub = ref.listenManual<DeviceInfo?>(deviceInfoProvider, (
      previous,
      next,
    ) {
      _maybeShowPathHashMigrationNotice(next);
      // Note: apply is NOT triggered here because deviceInfoProvider is
      // populated during _fetchInitialData, before connectionProvider
      // transitions to connected. The _connectionSub below handles that.
    });

    // Fires AFTER _fetchInitialData completes, when the radio service is
    // fully ready to receive commands. This is the correct moment to apply
    // the path-hash migration command.
    _connectionSub = ref.listenManual<TransportState>(connectionProvider, (
      previous,
      next,
    ) {
      if (next == TransportState.connected) {
        _maybeApplyPathHashMigration(ref.read(deviceInfoProvider));
      }
    });

    // If the provider already has a value when the listener is attached,
    // evaluate it immediately so the notice is not missed on app startup.
    _maybeShowPathHashMigrationNotice(ref.read(deviceInfoProvider));
    _maybeApplyPathHashMigration(ref.read(deviceInfoProvider));
  }

  void _maybeShowPathHashMigrationNotice(DeviceInfo? info) {
    if (_didShowPathHashMigrationModal) return;
    if (!_isStorageReady) return; // wait until app has finished loading
    if (info == null) return;

    final mode = info.pathHashMode;
    // 0 = explicit 1-byte mode; null = firmware did not report the field,
    // which is treated as default 1-byte behavior.
    if (mode != null && mode != 0) return;

    // Warning only shown before the migration date.
    if (!DateTime.now().isBefore(DateTime(2026, 7, 2))) return;

    _didShowPathHashMigrationModal = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showMigrationOverlay(
        icon: Icons.cell_tower_rounded,
        iconBgFn: (cs) => cs.primaryContainer,
        iconFgFn: (cs) => cs.onPrimaryContainer,
        titleFn: (l10n) => l10n.pathHashMigrationNoticeTitle,
        bodyFn: (l10n) => l10n.pathHashMigrationNoticeBody,
      );
    });
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

    // Mark loading complete and evaluate the migration notice now that
    // the app is fully ready (device info may have arrived already).
    _isStorageReady = true;
    _maybeShowPathHashMigrationNotice(ref.read(deviceInfoProvider));
    _maybeApplyPathHashMigration(ref.read(deviceInfoProvider));
  }

  /// On or after 2/7/2026: automatically switch the radio to 2-byte path hash
  /// mode and show a confirmation modal.
  void _maybeApplyPathHashMigration(DeviceInfo? info) {
    if (_didApplyPathHashMigration) return;
    if (!_isStorageReady) return;
    if (info == null) return;

    final mode = info.pathHashMode;
    if (mode != null && mode != 0) return; // already on 2-byte (or higher)

    // Only apply on or after July 2, 2026.
    if (DateTime.now().isBefore(DateTime(2026, 7, 2))) return;

    // Only send when the radio is actually connected. If not ready yet,
    // return WITHOUT setting the flag so the next device-info update retries.
    final svc = ref.read(radioServiceProvider);
    final connected = ref.read(connectionProvider) == TransportState.connected;
    if (svc == null || !connected) return;

    // Mark done only after we are certain the command will be dispatched.
    _didApplyPathHashMigration = true;
    svc.setPathHashMode(1).catchError((_) {});

    // Optimistically update deviceInfoProvider so all UI (e.g. the
    // Experimental card in Radio Settings) reflects the new mode immediately.
    final current = ref.read(deviceInfoProvider);
    if (current != null) {
      ref.read(deviceInfoProvider.notifier).state = DeviceInfo(
        firmwareVersion: current.firmwareVersion,
        deviceName: current.deviceName,
        batteryMillivolts: current.batteryMillivolts,
        storageUsed: current.storageUsed,
        storageTotal: current.storageTotal,
        maxContacts: current.maxContacts,
        maxChannels: current.maxChannels,
        blePin: current.blePin,
        firmwareBuild: current.firmwareBuild,
        model: current.model,
        versionString: current.versionString,
        clientRepeat: current.clientRepeat,
        pathHashMode: 1,
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showMigrationOverlay(
        icon: Icons.check_circle_rounded,
        iconBgFn: (cs) => cs.secondaryContainer,
        iconFgFn: (cs) => cs.onSecondaryContainer,
        titleFn: (l10n) => l10n.pathHashMigrationAppliedTitle,
        bodyFn: (l10n) => l10n.pathHashMigrationAppliedBody,
      );
    });
  }

  /// Shows a modal dialog using GoRouter’s overlay directly via an
  /// [OverlayEntry]. Dismissal calls [entry.remove()] — no Navigator.pop(),
  /// no GoRouter route-delegate involvement, no ‘last page’ assertions.
  void _showMigrationOverlay({
    required IconData icon,
    required Color Function(ColorScheme) iconBgFn,
    required Color Function(ColorScheme) iconFgFn,
    required String Function(AppLocalizations) titleFn,
    required String Function(AppLocalizations) bodyFn,
  }) {
    final overlay = rootNavigatorKey.currentState?.overlay;
    if (overlay == null || !overlay.mounted) return;
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        final colorScheme = Theme.of(ctx).colorScheme;
        final textTheme = Theme.of(ctx).textTheme;
        return _MigrationDialog(
          icon: icon,
          iconBg: iconBgFn(colorScheme),
          iconFg: iconFgFn(colorScheme),
          title: titleFn(l10n),
          body: bodyFn(l10n),
          okLabel: l10n.commonOk,
          titleStyle: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          bodyStyle: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          onDismiss: () => entry.remove(),
        );
      },
    );
    overlay.insert(entry);
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
        final messenger = ScaffoldMessenger.maybeOf(context);
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

/// Overlay-based migration dialog. Shown via [OverlayEntry] so dismissal
/// calls [onDismiss] (entry.remove()) and never touches Navigator.pop() or
/// GoRouter\u2019s route delegate.
class _MigrationDialog extends StatelessWidget {
  const _MigrationDialog({
    required this.icon,
    required this.iconBg,
    required this.iconFg,
    required this.title,
    required this.body,
    required this.okLabel,
    required this.onDismiss,
    this.titleStyle,
    this.bodyStyle,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconFg;
  final String title;
  final String body;
  final String okLabel;
  final VoidCallback onDismiss;
  final TextStyle? titleStyle;
  final TextStyle? bodyStyle;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, __) => onDismiss(),
      child: Material(
        color: Colors.transparent,
        child: GestureDetector(
          onTap: onDismiss,
          child: Container(
            color: Colors.black54,
            alignment: Alignment.center,
            child: GestureDetector(
              onTap: () {}, // absorb taps on the card itself
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).dialogTheme.backgroundColor ??
                        Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: iconBg,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, size: 34, color: iconFg),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        title,
                        style: titleStyle,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(body, style: bodyStyle, textAlign: TextAlign.center),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: onDismiss,
                          child: Text(okLabel),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
