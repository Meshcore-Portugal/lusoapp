import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart';

import '../../config/feature_toggles.dart';

/// App launcher grid — shown when the user taps the "Apps" bottom tab.
///
/// Each tile navigates to a sub-route within the shell (so the bottom nav
/// stays visible).
class AppsScreen extends StatelessWidget {
  const AppsScreen({super.key});

  static const _apps = [
    _AppEntry(
      id: 'topology',
      title: 'Topologia',
      subtitle: 'Grafo da rede e cronologia',
      icon: Icons.hub_outlined,
      color: Color(0xFFEC4899),
      route: '/apps/topology',
      feature: AppFeature.topology,
    ),
    _AppEntry(
      id: 'plan333',
      title: 'Plano 3-3-3',
      subtitle: 'Evento semanal MeshCore',
      icon: Icons.crisis_alert,
      color: Color(0xFFFF6B00),
      route: '/apps/plan333',
      feature: AppFeature.plan333,
    ),
    _AppEntry(
      id: 'telemetry',
      title: 'Telemetria',
      subtitle: 'Bateria, RF e contadores',
      icon: Icons.analytics_outlined,
      color: Color(0xFF14B8A6),
      route: '/apps/telemetry',
      feature: AppFeature.telemetry,
    ),
    _AppEntry(
      id: 'rxlog',
      title: 'RX Log',
      subtitle: 'Captura e exporta PCAP',
      icon: Icons.radar,
      color: Color(0xFF4F46E5),
      route: '/apps/rxlog',
      feature: AppFeature.rxlog,
    ),
    _AppEntry(
      id: 'noisefloor',
      title: 'RSSI / Noise Floor',
      subtitle: 'RSSI e ruído de fundo em tempo real',
      icon: Icons.graphic_eq,
      color: Color(0xFF22C55E),
      route: '/apps/noisefloor',
      feature: AppFeature.noisefloor,
    ),
    _AppEntry(
      id: 'dataexport',
      title: 'Exportar Dados',
      subtitle: 'Contactos, mensagens e mapa',
      icon: Icons.upload_file_outlined,
      color: Color(0xFFF59E0B),
      route: '/apps/dataexport',
      feature: AppFeature.dataexport,
    ),
    _AppEntry(
      id: 'event',
      title: 'Summit Edition',
      subtitle: 'Programa do Evento',
      icon: Icons.event_note,
      color: Color(0xFFFF8C00),
      route: '/apps/event',
      feature: AppFeature.event,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shortestSide = MediaQuery.sizeOf(context).shortestSide;
    final isTablet = shortestSide >= 600;
    final isWindowsDesktop =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    final largeLayout = kIsWeb || isWindowsDesktop || isTablet;
    final enabledApps =
        _apps.where((app) => FeatureToggles.isEnabled(app.feature)).toList();

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final outerPadding =
              largeLayout
                  ? const EdgeInsets.fromLTRB(24, 24, 24, 20)
                  : const EdgeInsets.fromLTRB(16, 20, 16, 16);
          final maxContentWidth = largeLayout ? 1320.0 : double.infinity;
          final availableWidth = constraints.maxWidth.clamp(0, maxContentWidth);
          final tileTargetWidth = largeLayout ? 260.0 : 180.0;
          final crossAxisCount = (availableWidth / tileTargetWidth)
              .floor()
              .clamp(2, largeLayout ? 5 : 3);

          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxContentWidth),
              child: Padding(
                padding: outerPadding,
                child: GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: largeLayout ? 16 : 14,
                    mainAxisSpacing: largeLayout ? 16 : 14,
                    childAspectRatio: largeLayout ? 1.24 : 1.0,
                  ),
                  itemCount: enabledApps.length,
                  itemBuilder: (context, index) {
                    return _AppTile(
                      entry: enabledApps[index],
                      theme: theme,
                      dense: largeLayout,
                      onTap: () => _launch(context, enabledApps[index]),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _launch(BuildContext context, _AppEntry app) {
    context.push(app.route);
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
    required this.feature,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  /// Shell route to navigate to.
  final String route;

  /// Feature-flag key for this entry.
  final AppFeature feature;
}

// ---------------------------------------------------------------------------
// App tile widget
// ---------------------------------------------------------------------------

class _AppTile extends StatelessWidget {
  const _AppTile({
    required this.entry,
    required this.theme,
    required this.dense,
    required this.onTap,
  });

  final _AppEntry entry;
  final ThemeData theme;
  final bool dense;
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
          padding: EdgeInsets.all(dense ? 14 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon container
              Container(
                width: dense ? 48 : 52,
                height: dense ? 48 : 52,
                decoration: BoxDecoration(
                  color: entry.color.withAlpha(30),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: entry.color.withAlpha(80),
                    width: 1.2,
                  ),
                ),
                child: Icon(
                  entry.icon,
                  color: entry.color,
                  size: dense ? 24 : 28,
                ),
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
