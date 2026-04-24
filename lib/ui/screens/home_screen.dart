import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/l10n.dart';
import '../../providers/radio_providers.dart';
import '../../transport/radio_transport.dart';
import '../theme.dart';

/// Main shell screen with bottom navigation.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentIndex = 0;
  bool _showVolts = false;
  bool _exitDialogOpen = false;

  static const _tabs = ['/channels', '/contacts', '/map', '/apps', '/settings'];

  /// Returns the display title for known app sub-routes.
  String? _appSubTitle(BuildContext context, String path) {
    return switch (path) {
      '/apps/plan333' => context.l10n.appsPlano333Title,
      '/apps/telemetry' => context.l10n.appsTelemetryTitle,
      '/apps/rxlog' => context.l10n.appsRxLogTitle,
      _ => null,
    };
  }

  /// Returns the tab index whose prefix matches [path].
  static int _tabIndexForPath(String path) {
    // Private chat and room screens are launched from the Contacts tab.
    if (path.startsWith('/chat/') || path.startsWith('/room/')) return 1;
    for (var i = 0; i < _tabs.length; i++) {
      if (path == _tabs[i] || path.startsWith('${_tabs[i]}/')) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final connectionState = ref.watch(connectionProvider);
    final selfInfo = ref.watch(selfInfoProvider);
    final batteryMv = ref.watch(batteryProvider);
    final unread = ref.watch(unreadCountsProvider);
    final theme = Theme.of(context);

    // Keep the nav bar indicator in sync with the live route (handles deep
    // links and context.go() calls from within sub-screens).
    final currentPath = GoRouterState.of(context).uri.path;
    final tabIndex = _tabIndexForPath(currentPath);
    if (tabIndex != _currentIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _currentIndex = tabIndex);
      });
    }

    // When inside an apps sub-page, show a back arrow and the app's name.
    final appSubTitle = _appSubTitle(context, currentPath);
    final isAppsSubPage = appSubTitle != null;

    return BackButtonListener(
      onBackButtonPressed: () async {
        _handleBack(context);
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          leading:
              isAppsSubPage
                  ? IconButton(
                    icon: const Icon(Icons.arrow_back),
                    tooltip: context.l10n.commonBack,
                    onPressed: () {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go('/apps');
                      }
                    },
                  )
                  : null,
          title:
              isAppsSubPage
                  ? Text(appSubTitle)
                  : Row(
                    children: [
                      Icon(
                        Icons.cell_tower,
                        color: theme.colorScheme.primary,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Text(selfInfo?.name ?? 'LusoAPP'),
                    ],
                  ),
          actions: [
            // Signal bars indicator — best SNR from last 5 min of RX log
            const _SignalIndicator(),
            // Battery indicator — tap to toggle % / voltage
            if (batteryMv > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _showVolts = !_showVolts),
                  child: Chip(
                    avatar: Icon(
                      _batteryIcon(batteryMv),
                      size: 18,
                      color: _batteryColor(batteryMv),
                    ),
                    label: Text(
                      _showVolts
                          ? '${(batteryMv / 1000).toStringAsFixed(3)}V'
                          : '${_batteryPercent(batteryMv)}%',
                    ),
                  ),
                ),
              ),
            // Connection indicator — tap to connect / disconnect
            IconButton(
              icon: Icon(
                connectionState == TransportState.connected
                    ? Icons.link
                    : Icons.link_off,
                color:
                    connectionState == TransportState.connected
                        ? Colors.green
                        : Colors.red,
              ),
              onPressed: () => _onConnectionIconTap(context, connectionState),
            ),
          ],
        ),
        body: widget.child,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) {
            setState(() => _currentIndex = index);
            context.go(_tabs[index]);
          },
          destinations: [
            NavigationDestination(
              icon: Badge(
                isLabelVisible: unread.totalChannels > 0,
                label: Text(
                  unread.totalChannels > 99 ? '99+' : '${unread.totalChannels}',
                ),
                child: const Icon(Icons.forum_outlined),
              ),
              selectedIcon: Badge(
                isLabelVisible: unread.totalChannels > 0,
                label: Text(
                  unread.totalChannels > 99 ? '99+' : '${unread.totalChannels}',
                ),
                child: const Icon(Icons.forum),
              ),
              label: context.l10n.navChannels,
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: unread.totalContacts > 0,
                label: Text(
                  unread.totalContacts > 99 ? '99+' : '${unread.totalContacts}',
                ),
                child: const Icon(Icons.contacts_outlined),
              ),
              selectedIcon: Badge(
                isLabelVisible: unread.totalContacts > 0,
                label: Text(
                  unread.totalContacts > 99 ? '99+' : '${unread.totalContacts}',
                ),
                child: const Icon(Icons.contacts),
              ),
              label: context.l10n.navContacts,
            ),
            NavigationDestination(
              icon: const Icon(Icons.map_outlined),
              selectedIcon: const Icon(Icons.map),
              label: context.l10n.navMap,
            ),
            NavigationDestination(
              icon: const Icon(Icons.apps_outlined),
              selectedIcon: const Icon(Icons.apps),
              label: context.l10n.navApps,
            ),
            NavigationDestination(
              icon: const Icon(Icons.settings_outlined),
              selectedIcon: const Icon(Icons.settings),
              label: context.l10n.navSettings,
            ),
          ],
        ),
      ),
    );
  }

  void _handleBack(BuildContext context) {
    final currentPath = GoRouterState.of(context).uri.path;
    final isRootTab = _tabs.contains(currentPath);
    if (isRootTab) {
      if (currentPath == _tabs[0]) {
        unawaited(_confirmExit(context));
      } else {
        context.go(_tabs[0]);
        setState(() => _currentIndex = 0);
      }
      return;
    }
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
    } else {
      context.go(_tabs[0]);
      setState(() => _currentIndex = 0);
    }
  }

  Future<void> _confirmExit(BuildContext context) async {
    if (_exitDialogOpen) return;
    _exitDialogOpen = true;
    bool? shouldExit;
    try {
      shouldExit = await showDialog<bool>(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: Text(context.l10n.homeExitTitle),
              content: Text(context.l10n.homeExitContent),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(context.l10n.commonCancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(context.l10n.homeExit),
                ),
              ],
            ),
      );
    } finally {
      _exitDialogOpen = false;
    }
    if (shouldExit == true) await SystemNavigator.pop();
  }

  Future<void> _onConnectionIconTap(
    BuildContext context,
    TransportState state,
  ) async {
    if (state == TransportState.connected) {
      final confirm = await showDialog<bool>(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: Text(context.l10n.homeDisconnectTitle),
              content: Text(context.l10n.homeDisconnectContent),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(context.l10n.commonCancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(context.l10n.homeDisconnect),
                ),
              ],
            ),
      );
      if (confirm == true && mounted) {
        await ref.read(connectionProvider.notifier).disconnect();
      }
    } else {
      context.go('/connect');
    }
  }

  int _batteryPercent(int mv) {
    // LiPo curve: matches MeshCore firmware defaults (3000–4200 mV)
    return (((mv.clamp(3000, 4200) - 3000) / 1200) * 100).round();
  }

  IconData _batteryIcon(int mv) {
    if (mv > 3900) return Icons.battery_full;
    if (mv > 3600) return Icons.battery_5_bar;
    if (mv > 3300) return Icons.battery_3_bar;
    return Icons.battery_1_bar;
  }

  Color _batteryColor(int mv) {
    if (mv > 3600) return Colors.green;
    if (mv > 3300) return AppTheme.primary;
    return Colors.red;
  }
}

// ---------------------------------------------------------------------------
// Signal bars indicator (best LoRa SNR from last 5 min of received packets)
// ---------------------------------------------------------------------------

class _SignalIndicator extends ConsumerWidget {
  const _SignalIndicator();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snr = ref.watch(bestSignalSnrProvider);
    return GestureDetector(
      onTap: () {
        ref.read(telemetryScrollToRfProvider.notifier).state = true;
        context.go('/apps/telemetry');
      },
      child: _SignalBarsIcon(snr: snr),
    );
  }
}

class _SignalBarsIcon extends StatelessWidget {
  const _SignalBarsIcon({required this.snr});
  final double? snr;

  /// Map LoRa SNR → 0-4 bar count.
  /// LoRa SNR range: typically -20 dB (marginal) to +10 dB (excellent).
  static int _bars(double snr) {
    if (snr >= 0) return 4; // excellent
    if (snr >= -5) return 3; // good
    if (snr >= -10) return 2; // fair
    return 1; // weak
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snrValue =
        snr; // local copy — required for null promotion of public field

    if (snrValue == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Tooltip(
          message: context.l10n.signalNone,
          child: _SignalBars(
            bars: 0,
            color: theme.colorScheme.onSurface.withAlpha(80),
          ),
        ),
      );
    }

    final bars = _bars(snrValue);
    final Color color;
    final String quality;

    switch (bars) {
      case 4:
        color = Colors.green;
        quality = context.l10n.signalExcellent;
      case 3:
        color = Colors.lightGreen;
        quality = context.l10n.signalGood;
      case 2:
        color = Colors.orange;
        quality = context.l10n.signalFair;
      default:
        color = Colors.red;
        quality = context.l10n.signalWeak;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: '$quality — SNR ${snrValue.toStringAsFixed(1)} dB',
        child: _SignalBars(bars: bars, color: color),
      ),
    );
  }
}

/// Draws 4 vertical bars of increasing height — like a phone signal indicator.
/// [bars] = 0 means all bars are hollow (no signal).
class _SignalBars extends StatelessWidget {
  const _SignalBars({required this.bars, required this.color});
  final int bars; // 0–4
  final Color color;

  @override
  Widget build(BuildContext context) {
    const totalBars = 4;
    const maxHeight = 18.0;
    const barWidth = 4.0;

    return SizedBox(
      width: totalBars * barWidth + (totalBars - 1) * 1.5,
      height: maxHeight,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(totalBars, (i) {
          final barH = maxHeight * (i + 1) / totalBars;
          final filled = i < bars;
          return SizedBox(
            width: barWidth,
            height: barH,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: filled ? color : color.withAlpha(55),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(1.5),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
