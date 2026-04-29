part of '../telemetry_screen.dart';

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
