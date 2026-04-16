import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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

  /// Map of known app sub-routes to their display titles.
  static const _appSubTitles = {
    '/apps/plan333': 'Plano 3-3-3',
    '/apps/telemetry': 'Telemetria',
  };

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
    final appSubTitle = _appSubTitles[currentPath];
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
                  tooltip: 'Voltar',
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
            label: 'Canais',
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
            label: 'Contactos',
          ),
          const NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Mapa',
          ),
          const NavigationDestination(
            icon: Icon(Icons.apps_outlined),
            selectedIcon: Icon(Icons.apps),
            label: 'Apps',
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Definições',
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
        builder: (ctx) => AlertDialog(
          title: const Text('Sair da LusoAPP?'),
          content: const Text(
            'A ligação ao rádio será terminada e a aplicação encerrada.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sair'),
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
        await ref.read(connectionProvider.notifier).disconnect();
      }
    } else {
      context.go('/connect');
    }
  }

  int _batteryPercent(int mv) {
    // LiPo curve: 4200 mV = 100%, 3200 mV = 0%
    return (((mv.clamp(3200, 4200) - 3200) / 1000) * 100).round();
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
