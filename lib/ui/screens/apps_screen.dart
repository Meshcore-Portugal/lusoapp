import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'qr_scanner_screen.dart';

/// App launcher grid — shown when the user taps the "Apps" bottom tab.
///
/// Each tile navigates to a sub-route within the shell (so the bottom nav
/// stays visible) except for the QR scanner, which is pushed as a modal.
class AppsScreen extends StatelessWidget {
  const AppsScreen({super.key});

  static const _apps = [
    _AppEntry(
      id: 'event',
      title: 'Summit Edition',
      subtitle: 'Programa do Evento',
      icon: Icons.event_note,
      color: Color(0xFFFF8C00),
      route: '/apps/event',
    ),
    _AppEntry(
      id: 'plan333',
      title: 'Plano 3-3-3',
      subtitle: 'Evento semanal MeshCore',
      icon: Icons.crisis_alert,
      color: Color(0xFFFF6B00),
      route: '/apps/plan333',
    ),
    _AppEntry(
      id: 'telemetry',
      title: 'Telemetria',
      subtitle: 'Bateria, RF e contadores',
      icon: Icons.analytics_outlined,
      color: Color(0xFF14B8A6),
      route: '/apps/telemetry',
    ),
    _AppEntry(
      id: 'qr',
      title: 'Leitor QR',
      subtitle: 'Digitalizar código QR',
      icon: Icons.qr_code_scanner,
      color: Color(0xFF9C6FFF),
      route: null, // modal — handled separately
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 1.0,
          ),
          itemCount: _apps.length,
          itemBuilder: (context, index) {
            return _AppTile(
              entry: _apps[index],
              theme: theme,
              onTap: () => _launch(context, _apps[index]),
            );
          },
        ),
      ),
    );
  }

  void _launch(BuildContext context, _AppEntry app) {
    if (app.route != null) {
      context.push(app.route!);
    } else {
      // QR scanner is a modal that returns the scanned value.
      Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const QrScannerScreen()),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// App entry data holder (compile-time const)
// ---------------------------------------------------------------------------

class _AppEntry {
  const _AppEntry({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.route,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  /// Shell route to navigate to, or null for a modal push.
  final String? route;
}

// ---------------------------------------------------------------------------
// App tile widget
// ---------------------------------------------------------------------------

class _AppTile extends StatelessWidget {
  const _AppTile({
    required this.entry,
    required this.theme,
    required this.onTap,
  });

  final _AppEntry entry;
  final ThemeData theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: entry.color.withAlpha(40),
        highlightColor: entry.color.withAlpha(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon container
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: entry.color.withAlpha(30),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: entry.color.withAlpha(80),
                    width: 1.2,
                  ),
                ),
                child: Icon(entry.icon, color: entry.color, size: 28),
              ),
              const Spacer(),
              // Title
              Text(
                entry.title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              // Subtitle
              Text(
                entry.subtitle,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
