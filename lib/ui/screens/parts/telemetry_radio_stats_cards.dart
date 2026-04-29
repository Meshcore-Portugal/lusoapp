part of '../telemetry_screen.dart';

// Radio core stats card
// ---------------------------------------------------------------------------

class _RadioCoreStatsCard extends StatelessWidget {
  const _RadioCoreStatsCard({required this.stats, required this.theme});

  final StatsCoreResponse stats;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final uptime = _formatUptime(stats.uptimeSecs);
    final volts = (stats.batteryMv / 1000.0).toStringAsFixed(3);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatCell(
                  icon: Icons.battery_charging_full,
                  color: Colors.green.shade600,
                  label: context.l10n.telemetryBattery,
                  value: '$volts V',
                  theme: theme,
                ),
                _VertDivider(),
                _StatCell(
                  icon: Icons.timer_outlined,
                  color: theme.colorScheme.primary,
                  label: context.l10n.telemetryUptime,
                  value: uptime,
                  theme: theme,
                ),
                _VertDivider(),
                _StatCell(
                  icon: Icons.inbox,
                  color: theme.colorScheme.secondary,
                  label: context.l10n.telemetryTxQueue,
                  value: '${stats.queueLen}',
                  theme: theme,
                ),
              ],
            ),
            if (stats.errors != 0) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    Icons.warning_amber,
                    size: 16,
                    color: Colors.orange.shade600,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${context.l10n.telemetryErrorsPrefix} 0x${stats.errors.toRadixString(16).padLeft(4, '0').toUpperCase()}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.orange.shade700,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatUptime(int secs) {
    if (secs < 60) return '${secs}s';
    if (secs < 3600) return '${secs ~/ 60}min';
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    if (h < 24) return '${h}h ${m}min';
    final d = h ~/ 24;
    return '${d}d ${h % 24}h';
  }
}

// ---------------------------------------------------------------------------
// Radio RF stats card
// ---------------------------------------------------------------------------

class _RadioRfStatsCard extends StatelessWidget {
  const _RadioRfStatsCard({required this.stats, required this.theme});

  final StatsRadioResponse stats;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final snr = stats.lastSnrDb.toStringAsFixed(2);
    final txAir = _formatAirtime(stats.txAirSecs);
    final rxAir = _formatAirtime(stats.rxAirSecs);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatCell(
                  icon: Icons.signal_cellular_alt,
                  color: _rssiColor(stats.lastRssi, theme),
                  label: context.l10n.telemetryRSSI,
                  value: '${stats.lastRssi} dBm',
                  theme: theme,
                ),
                _VertDivider(),
                _StatCell(
                  icon: Icons.noise_aware,
                  color: theme.colorScheme.onSurfaceVariant,
                  label: context.l10n.telemetryNoise,
                  value: '${stats.noiseFloor} dBm',
                  theme: theme,
                ),
                _VertDivider(),
                _StatCell(
                  icon: Icons.show_chart,
                  color: _snrColor(stats.lastSnrDb, theme),
                  label: context.l10n.telemetrySNR,
                  value: '$snr dB',
                  theme: theme,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatCell(
                  icon: Icons.upload_outlined,
                  color: theme.colorScheme.primary,
                  label: context.l10n.telemetryAirtimeTX,
                  value: txAir,
                  theme: theme,
                ),
                _VertDivider(),
                _StatCell(
                  icon: Icons.download_outlined,
                  color: Colors.green.shade600,
                  label: context.l10n.telemetryAirtimeRX,
                  value: rxAir,
                  theme: theme,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _rssiColor(int rssi, ThemeData theme) {
    if (rssi >= -90) return Colors.green.shade600;
    if (rssi >= -110) return Colors.orange.shade600;
    return Colors.red.shade600;
  }

  Color _snrColor(double snr, ThemeData theme) {
    if (snr >= 5) return Colors.green.shade600;
    if (snr >= 0) return Colors.orange.shade600;
    return Colors.red.shade600;
  }

  String _formatAirtime(int secs) {
    if (secs < 60) return '${secs}s';
    if (secs < 3600) return '${secs ~/ 60}min ${secs % 60}s';
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    return '${h}h ${m}min';
  }
}

// ---------------------------------------------------------------------------
// Radio packet counters card
// ---------------------------------------------------------------------------

class _RadioPacketStatsCard extends StatelessWidget {
  const _RadioPacketStatsCard({required this.stats, required this.theme});

  final StatsPacketsResponse stats;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatCell(
                  icon: Icons.arrow_downward,
                  color: Colors.green.shade600,
                  label: context.l10n.telemetryRXTotal,
                  value: '${stats.recv}',
                  theme: theme,
                ),
                _VertDivider(),
                _StatCell(
                  icon: Icons.arrow_upward,
                  color: theme.colorScheme.primary,
                  label: context.l10n.telemetryTXTotal,
                  value: '${stats.sent}',
                  theme: theme,
                ),
                if (stats.recvErrors != null) ...[
                  _VertDivider(),
                  _StatCell(
                    icon: Icons.error_outline,
                    color: Colors.red.shade600,
                    label: context.l10n.telemetryErrorsRX,
                    value: '${stats.recvErrors}',
                    theme: theme,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatCell(
                  icon: Icons.waves,
                  color: theme.colorScheme.secondary,
                  label: context.l10n.telemetryFloodTX,
                  value: '${stats.floodTx}',
                  theme: theme,
                ),
                _VertDivider(),
                _StatCell(
                  icon: Icons.waves,
                  color: Colors.teal.shade600,
                  label: context.l10n.telemetryFloodRX,
                  value: '${stats.floodRx}',
                  theme: theme,
                ),
                _VertDivider(),
                _StatCell(
                  icon: Icons.alt_route,
                  color: Colors.indigo.shade400,
                  label: context.l10n.telemetryDirectTX,
                  value: '${stats.directTx}',
                  theme: theme,
                ),
                _VertDivider(),
                _StatCell(
                  icon: Icons.alt_route,
                  color: Colors.cyan.shade600,
                  label: context.l10n.telemetryDirectRX,
                  value: '${stats.directRx}',
                  theme: theme,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({super.key, required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({
    required this.icon,
    required this.message,
    required this.theme,
  });

  final IconData icon;
  final String message;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(icon, size: 40, color: theme.colorScheme.outlineVariant),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
