import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/l10n.dart';
import '../../providers/radio_providers.dart';
import '../../transport/radio_transport.dart';
import '../../utils/battery_utils.dart';
import '../theme.dart';

String _sanitizeUtf16Ui(String s) {
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c >= 0xD800 && c <= 0xDFFF) {
      final buf = StringBuffer();
      for (var j = 0; j < s.length; j++) {
        final u = s.codeUnitAt(j);
        if (u >= 0xD800 && u <= 0xDBFF) {
          if (j + 1 < s.length) {
            final u2 = s.codeUnitAt(j + 1);
            if (u2 >= 0xDC00 && u2 <= 0xDFFF) {
              buf.write(s[j]);
              buf.write(s[j + 1]);
              j++;
              continue;
            }
          }
          buf.writeCharCode(0xFFFD);
        } else if (u >= 0xDC00 && u <= 0xDFFF) {
          buf.writeCharCode(0xFFFD);
        } else {
          buf.write(s[j]);
        }
      }
      return buf.toString();
    }
  }
  return s;
}

String _safeUiText(String? value, {required String fallback}) {
  final sanitized = _sanitizeUtf16Ui(value ?? '').trim();
  return sanitized.isEmpty ? fallback : sanitized;
}

/// Main shell screen with bottom navigation.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({
    super.key,
    required this.navigationShell,
    required this.currentPath,
  });
  final StatefulNavigationShell navigationShell;
  final String currentPath;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
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

  @override
  Widget build(BuildContext context) {
    // Watch only the connection state enum, not the full object
    final connectionState = ref.watch(
      connectionProvider.select((state) => state),
    );
    final selfName = ref.watch(selfInfoProvider.select((info) => info?.name));
    final batteryMv = ref.watch(batteryProvider);
    final unreadChannels = ref.watch(
      unreadCountsProvider.select((counts) => counts.totalChannels),
    );
    final unreadContacts = ref.watch(
      unreadCountsProvider.select((counts) => counts.totalContacts),
    );
    final theme = Theme.of(context);

    final currentPath = widget.currentPath;
    final tabIndex = widget.navigationShell.currentIndex;
    final isIos = defaultTargetPlatform == TargetPlatform.iOS;
    final isChannelsChatPage = currentPath.startsWith('/channels/');
    final isContactsChatPage =
        currentPath.startsWith('/chat/') ||
        currentPath.startsWith('/room/') ||
        currentPath.startsWith('/repeater/');
    final showIosChatBack = isIos && (isChannelsChatPage || isContactsChatPage);

    // When inside an apps sub-page, show a back arrow and the app's name.
    final appSubTitle = _appSubTitle(context, currentPath);
    final isAppsSubPage = appSubTitle != null;
    final shortestSide = MediaQuery.sizeOf(context).shortestSide;
    final isTablet = shortestSide >= 600;
    final isWindowsDesktop =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    final useLargeNav = kIsWeb || isWindowsDesktop || isTablet;
    final useExtendedRail = MediaQuery.sizeOf(context).width >= 1280;

    final channelsIcon = Badge(
      isLabelVisible: unreadChannels > 0,
      label: Text(unreadChannels > 99 ? '99+' : '$unreadChannels'),
      child: const Icon(Icons.forum_outlined),
    );
    final channelsSelectedIcon = Badge(
      isLabelVisible: unreadChannels > 0,
      label: Text(unreadChannels > 99 ? '99+' : '$unreadChannels'),
      child: const Icon(Icons.forum),
    );
    final contactsIcon = Badge(
      isLabelVisible: unreadContacts > 0,
      label: Text(unreadContacts > 99 ? '99+' : '$unreadContacts'),
      child: const Icon(Icons.contacts_outlined),
    );
    final contactsSelectedIcon = Badge(
      isLabelVisible: unreadContacts > 0,
      label: Text(unreadContacts > 99 ? '99+' : '$unreadContacts'),
      child: const Icon(Icons.contacts),
    );

    return BackButtonListener(
      onBackButtonPressed: () async {
        _handleBack(context);
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          leading:
              showIosChatBack
                  ? IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded),
                    tooltip: context.l10n.commonBack,
                    onPressed: () {
                      if (isChannelsChatPage) {
                        context.go('/channels');
                      } else {
                        context.go('/contacts');
                      }
                    },
                  )
                  : isAppsSubPage
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
                      Text(_safeUiText(selfName, fallback: 'LusoAPP')),
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
        body:
            useLargeNav
                ? Row(
                  children: [
                    SafeArea(
                      child: NavigationRail(
                        selectedIndex: tabIndex,
                        extended: useExtendedRail,
                        minExtendedWidth: 180,
                        onDestinationSelected: (index) {
                          widget.navigationShell.goBranch(
                            index,
                            initialLocation: true,
                          );
                        },
                        labelType:
                            useExtendedRail
                                ? NavigationRailLabelType.none
                                : NavigationRailLabelType.selected,
                        destinations: [
                          NavigationRailDestination(
                            icon: channelsIcon,
                            selectedIcon: channelsSelectedIcon,
                            label: Text(context.l10n.navChannels),
                          ),
                          NavigationRailDestination(
                            icon: contactsIcon,
                            selectedIcon: contactsSelectedIcon,
                            label: Text(context.l10n.navContacts),
                          ),
                          NavigationRailDestination(
                            icon: const Icon(Icons.map_outlined),
                            selectedIcon: const Icon(Icons.map),
                            label: Text(context.l10n.navMap),
                          ),
                          NavigationRailDestination(
                            icon: const Icon(Icons.apps_outlined),
                            selectedIcon: const Icon(Icons.apps),
                            label: Text(context.l10n.navApps),
                          ),
                          NavigationRailDestination(
                            icon: const Icon(Icons.settings_outlined),
                            selectedIcon: const Icon(Icons.settings),
                            label: Text(context.l10n.navSettings),
                          ),
                        ],
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: widget.navigationShell),
                  ],
                )
                : widget.navigationShell,
        bottomNavigationBar:
            useLargeNav
                ? null
                : NavigationBar(
                  selectedIndex: tabIndex,
                  onDestinationSelected: (index) {
                    widget.navigationShell.goBranch(
                      index,
                      initialLocation: true,
                    );
                  },
                  destinations: [
                    NavigationDestination(
                      icon: channelsIcon,
                      selectedIcon: channelsSelectedIcon,
                      label: context.l10n.navChannels,
                    ),
                    NavigationDestination(
                      icon: contactsIcon,
                      selectedIcon: contactsSelectedIcon,
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
    final currentPath = widget.currentPath;
    final isRootTab = _tabs.contains(currentPath);
    if (isRootTab) {
      if (currentPath == _tabs[0]) {
        unawaited(_confirmExit(context));
      } else {
        widget.navigationShell.goBranch(0, initialLocation: false);
      }
      return;
    }
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
    } else {
      widget.navigationShell.goBranch(0, initialLocation: false);
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
    return batteryPercentFromMv(mv);
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
