import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/radio_providers.dart';
import '../../transport/radio_transport.dart';

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

  static const _tabs = [
    '/channels',
    '/contacts',
    '/map',
    '/radio',
    '/settings',
  ];

  @override
  Widget build(BuildContext context) {
    final connectionState = ref.watch(connectionProvider);
    final selfInfo = ref.watch(selfInfoProvider);
    final batteryMv = ref.watch(batteryProvider);
    final unread = ref.watch(unreadCountsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.cell_tower, color: theme.colorScheme.primary, size: 24),
            const SizedBox(width: 8),
            Text(selfInfo?.name ?? 'MeshCore PT'),
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
          // Connection indicator
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Icon(
              connectionState == TransportState.connected
                  ? Icons.link
                  : Icons.link_off,
              color:
                  connectionState == TransportState.connected
                      ? Colors.green
                      : Colors.red,
            ),
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
            icon: Icon(Icons.settings_input_antenna_outlined),
            selectedIcon: Icon(Icons.settings_input_antenna),
            label: 'Rádio',
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Definicoes',
          ),
        ],
      ),
    );
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
    if (mv > 3300) return Colors.orange;
    return Colors.red;
  }
}
