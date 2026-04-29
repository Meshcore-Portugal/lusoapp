part of '../telemetry_screen.dart';

// Network stats card
// ---------------------------------------------------------------------------

class _NetworkStatsCard extends StatelessWidget {
  const _NetworkStatsCard({required this.stats, required this.theme});

  final NetworkStats stats;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _StatCell(
              icon: Icons.arrow_downward,
              color: Colors.green.shade600,
              label: context.l10n.telemetryRX,
              value: '${stats.rxMessages}',
              theme: theme,
            ),
            _VertDivider(),
            _StatCell(
              icon: Icons.arrow_upward,
              color: theme.colorScheme.primary,
              label: context.l10n.telemetryTX,
              value: '${stats.txMessages}',
              theme: theme,
            ),
            _VertDivider(),
            _StatCell(
              icon: Icons.error_outline,
              color: Colors.red.shade600,
              label: context.l10n.telemetryErrors,
              value: '${stats.errors}',
              theme: theme,
            ),
            _VertDivider(),
            _StatCell(
              icon: Icons.cell_tower,
              color: Colors.orange.shade700,
              label: context.l10n.telemetryHeard,
              value: '${stats.heardNodes}',
              theme: theme,
            ),
          ],
        ),
      ),
    );
  }
}

class _VertDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      const SizedBox(height: 48, child: VerticalDivider());
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.theme,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
