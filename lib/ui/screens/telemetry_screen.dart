import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../protocol/cayenne_lpp.dart';
import '../../providers/radio_providers.dart';

/// Telemetry dashboard — battery history chart, CayenneLPP sensor readings,
/// and network statistics.
class TelemetryScreen extends ConsumerWidget {
  const TelemetryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final batteryMv = ref.watch(batteryProvider);
    final battHistoryRaw = ref.watch(batteryHistoryProvider);
    final stats = ref.watch(networkStatsProvider);
    final telemetry = ref.watch(telemetryProvider);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ---- Battery section ----
        const _SectionHeader(
          label: 'Bateria',
          icon: Icons.battery_charging_full,
        ),
        const SizedBox(height: 8),
        _BatteryCard(
          currentMv: batteryMv,
          history: battHistoryRaw,
          theme: theme,
        ),
        const SizedBox(height: 20),

        // ---- Network stats section ----
        const _SectionHeader(
          label: 'Estatísticas da Rede',
          icon: Icons.bar_chart,
        ),
        const SizedBox(height: 8),
        _NetworkStatsCard(stats: stats, theme: theme),
        const SizedBox(height: 20),

        // ---- CayenneLPP sensor readings ----
        const _SectionHeader(
          label: 'Sensores (Telemetria)',
          icon: Icons.sensors,
        ),
        const SizedBox(height: 8),
        if (telemetry.isEmpty)
          _EmptyHint(
            icon: Icons.sensors_off,
            message: 'Nenhuma telemetria recebida.',
            theme: theme,
          )
        else
          for (final entry in telemetry)
            _TelemetryEntryCard(entry: entry, theme: theme),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Battery card
// ---------------------------------------------------------------------------

class _BatteryCard extends StatelessWidget {
  const _BatteryCard({
    required this.currentMv,
    required this.history,
    required this.theme,
  });

  final int currentMv;
  final List<BatteryReading> history;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final hasData = history.isNotEmpty;
    final volts = currentMv > 0 ? (currentMv / 1000.0).toStringAsFixed(2) : '—';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Current reading row
            Row(
              children: [
                Icon(
                  _batteryIcon(currentMv),
                  color: _batteryColor(currentMv, theme),
                  size: 32,
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$volts V',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: _batteryColor(currentMv, theme),
                      ),
                    ),
                    Text(
                      currentMv > 0
                          ? '${_batteryPercent(currentMv)}%'
                          : 'Sem dados',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                if (hasData)
                  Text(
                    '${history.length} amostras',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),

            // Sparkline chart
            if (history.length > 1) ...[
              const SizedBox(height: 16),
              SizedBox(
                height: 80,
                child: _BatterySparkline(history: history, theme: theme),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _timeLabel(history.first.timestamp),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    'Agora',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ] else if (!hasData)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'O histórico aparece após a primeira leitura de bateria.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _timeLabel(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Há ${diff.inSeconds}s';
    if (diff.inHours < 1) return 'Há ${diff.inMinutes}min';
    return 'Há ${diff.inHours}h';
  }

  IconData _batteryIcon(int mv) {
    if (mv <= 0) return Icons.battery_unknown;
    if (mv > 3900) return Icons.battery_full;
    if (mv > 3700) return Icons.battery_5_bar;
    if (mv > 3500) return Icons.battery_3_bar;
    return Icons.battery_1_bar;
  }

  Color _batteryColor(int mv, ThemeData theme) {
    if (mv <= 0) return theme.colorScheme.onSurfaceVariant;
    if (mv > 3700) return Colors.green.shade600;
    if (mv > 3500) return Colors.orange.shade600;
    return Colors.red.shade600;
  }

  int _batteryPercent(int mv) {
    // Approximate LiPo discharge curve: 4200mV=100%  3200mV=0%
    final clamped = mv.clamp(3200, 4200);
    return (((clamped - 3200) / 1000) * 100).round();
  }
}

// ---------------------------------------------------------------------------
// Battery sparkline painter
// ---------------------------------------------------------------------------

class _BatterySparkline extends StatelessWidget {
  const _BatterySparkline({required this.history, required this.theme});

  final List<BatteryReading> history;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SparklinePainter(history: history, theme: theme),
      child: const SizedBox.expand(),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({required this.history, required this.theme});

  final List<BatteryReading> history;
  final ThemeData theme;

  @override
  void paint(Canvas canvas, Size size) {
    if (history.length < 2) return;

    final values = history.map((r) => r.millivolts.toDouble()).toList();
    final minV = values.reduce(math.min);
    final maxV = values.reduce(math.max);
    final range = (maxV - minV).clamp(50.0, double.infinity);

    final linePaint =
        Paint()
          ..color = theme.colorScheme.primary
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;

    final fillPaint =
        Paint()
          ..color = theme.colorScheme.primary.withAlpha(30)
          ..style = PaintingStyle.fill;

    final path = Path();
    final fillPath = Path();

    for (var i = 0; i < values.length; i++) {
      final x = i / (values.length - 1) * size.width;
      final y = size.height - ((values[i] - minV) / range * size.height);
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);

    // Min/max labels
    final labelStyle = TextStyle(
      color: theme.colorScheme.onSurfaceVariant,
      fontSize: 9,
    );
    _drawLabel(
      canvas,
      size,
      '${(maxV / 1000).toStringAsFixed(2)}V',
      0,
      labelStyle,
    );
    _drawLabel(
      canvas,
      size,
      '${(minV / 1000).toStringAsFixed(2)}V',
      size.height - 11,
      labelStyle,
    );
  }

  void _drawLabel(
    Canvas canvas,
    Size size,
    String text,
    double y,
    TextStyle style,
  ) {
    final span = TextSpan(text: text, style: style);
    final tp = TextPainter(text: span, textDirection: TextDirection.ltr)
      ..layout();
    tp.paint(canvas, Offset(size.width - tp.width - 2, y));
  }

  @override
  bool shouldRepaint(_SparklinePainter old) => old.history != history;
}

// ---------------------------------------------------------------------------
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
              label: 'RX',
              value: '${stats.rxMessages}',
              theme: theme,
            ),
            _VertDivider(),
            _StatCell(
              icon: Icons.arrow_upward,
              color: theme.colorScheme.primary,
              label: 'TX',
              value: '${stats.txMessages}',
              theme: theme,
            ),
            _VertDivider(),
            _StatCell(
              icon: Icons.error_outline,
              color: Colors.red.shade600,
              label: 'Erros',
              value: '${stats.errors}',
              theme: theme,
            ),
            _VertDivider(),
            _StatCell(
              icon: Icons.cell_tower,
              color: Colors.orange.shade700,
              label: 'Ouvidos',
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
// Telemetry entry card
// ---------------------------------------------------------------------------

class _TelemetryEntryCard extends StatelessWidget {
  const _TelemetryEntryCard({required this.entry, required this.theme});

  final TelemetryEntry entry;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final timeStr = _formatTime(entry.timestamp);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.sensors, size: 16),
                const SizedBox(width: 6),
                Text(
                  'Telemetria — $timeStr',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in entry.readings)
                  _ReadingChip(reading: r, theme: theme),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

class _ReadingChip extends StatelessWidget {
  const _ReadingChip({required this.reading, required this.theme});

  final CayenneReading reading;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outline.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${reading.type.label} (ch${reading.channel})',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            reading.formatted,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.icon});

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
