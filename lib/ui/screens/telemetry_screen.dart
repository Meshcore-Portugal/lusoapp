import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../protocol/cayenne_lpp.dart';
import '../../protocol/companion_decoder.dart';
import '../../l10n/l10n.dart';
import '../../providers/radio_providers.dart';

/// Telemetry dashboard — battery history chart, CayenneLPP sensor readings,
/// and network statistics.
class TelemetryScreen extends ConsumerStatefulWidget {
  const TelemetryScreen({super.key});

  @override
  ConsumerState<TelemetryScreen> createState() => _TelemetryScreenState();
}

class _TelemetryScreenState extends ConsumerState<TelemetryScreen> {
  final _rfSectionKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final scrollToRf = ref.read(telemetryScrollToRfProvider);
      if (scrollToRf) {
        ref.read(telemetryScrollToRfProvider.notifier).state = false;
        final ctx = _rfSectionKey.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOut,
            alignment: 0.0,
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final batteryMv = ref.watch(batteryProvider);
    final battHistoryRaw = ref.watch(batteryHistoryProvider);
    final stats = ref.watch(networkStatsProvider);
    final telemetry = ref.watch(telemetryProvider);
    final statsCore = ref.watch(radioStatsCoreProvider);
    final statsRadio = ref.watch(radioStatsRadioProvider);
    final statsPackets = ref.watch(radioStatsPacketsProvider);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ---- Battery section ----
        _SectionHeader(
          label: context.l10n.telemetryBattery,
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
        _SectionHeader(
          label: context.l10n.telemetryNetStats,
          icon: Icons.bar_chart,
        ),
        const SizedBox(height: 8),
        _NetworkStatsCard(stats: stats, theme: theme),
        const SizedBox(height: 20),

        // ---- Radio core stats section ----
        _SectionHeader(
          label: context.l10n.telemetryRadioState,
          icon: Icons.memory,
        ),
        const SizedBox(height: 8),
        if (statsCore == null)
          _EmptyHint(
            icon: Icons.hourglass_empty,
            message: context.l10n.telemetryRadioWaiting,
            theme: theme,
          )
        else
          _RadioCoreStatsCard(stats: statsCore, theme: theme),
        const SizedBox(height: 20),

        // ---- Radio RF stats section ----
        _SectionHeader(
          key: _rfSectionKey,
          label: context.l10n.telemetryRadioRF,
          icon: Icons.cell_tower,
        ),
        const SizedBox(height: 8),
        if (statsRadio == null)
          _EmptyHint(
            icon: Icons.hourglass_empty,
            message: context.l10n.telemetryRFWaiting,
            theme: theme,
          )
        else
          _RadioRfStatsCard(stats: statsRadio, theme: theme),
        const SizedBox(height: 20),

        // ---- Packet counters section ----
        _SectionHeader(
          label: context.l10n.telemetryPacketCounters,
          icon: Icons.swap_horiz,
        ),
        const SizedBox(height: 8),
        if (statsPackets == null)
          _EmptyHint(
            icon: Icons.hourglass_empty,
            message: context.l10n.telemetryCountersWaiting,
            theme: theme,
          )
        else
          _RadioPacketStatsCard(stats: statsPackets, theme: theme),
        const SizedBox(height: 20),

        // ---- CayenneLPP sensor readings ----
        _SectionHeader(
          label: context.l10n.telemetrySensors,
          icon: Icons.sensors,
        ),
        const SizedBox(height: 8),
        if (telemetry.isEmpty)
          _EmptyHint(
            icon: Icons.sensors_off,
            message: context.l10n.telemetryNoData,
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
                          : context.l10n.commonNoData,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                if (hasData)
                  Text(
                    '${history.length} ${context.l10n.telemetrySamplesSuffix}',
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
                    context.l10n.telemetryNow,
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
                  context.l10n.telemetryHistoryHint,
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
                  '${context.l10n.telemetryCardPrefix} $timeStr',
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
