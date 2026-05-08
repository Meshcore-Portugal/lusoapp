import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../protocol/commands.dart';
import '../../../providers/radio_providers.dart';

/// Real-time RSSI + Noise Floor chart.
///
/// Polls `CMD_GET_STATS / STATS_TYPE_RADIO` every 2 seconds and renders both
/// series on a shared fixed-range area chart (-60 dBm … -120 dBm).
class NoiseFloorScreen extends ConsumerStatefulWidget {
  const NoiseFloorScreen({super.key});

  @override
  ConsumerState<NoiseFloorScreen> createState() => _NoiseFloorScreenState();
}

class _NoiseFloorScreenState extends ConsumerState<NoiseFloorScreen> {
  Timer? _pollTimer;
  bool _showRssi = true;
  bool _showNoise = true;

  @override
  void initState() {
    super.initState();
    _poll();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
  }

  void _poll() {
    final service = ref.read(radioServiceProvider);
    service?.requestStats(statsTypeRadio).catchError((_) {});
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final noiseHistory = ref.watch(noiseFloorHistoryProvider);
    final rssiHistory = ref.watch(rssiHistoryProvider);
    final current = ref.watch(radioStatsRadioProvider);
    final theme = Theme.of(context);

    final rssiDbm = current?.lastRssi;
    final noiseDbm = current?.noiseFloor;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        title: const Text('RSSI / Noise Floor'),
        backgroundColor: const Color(0xFF0D1117),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Current value readout — tappable chips toggle visibility
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ValueChip(
                  label: 'RSSI',
                  value: rssiDbm != null ? '${rssiDbm}dBm' : '—',
                  color: const Color(0xFF38BDF8),
                  active: _showRssi,
                  theme: theme,
                  onTap: () => setState(() => _showRssi = !_showRssi),
                ),
                const SizedBox(width: 24),
                _ValueChip(
                  label: 'Noise Floor',
                  value: noiseDbm != null ? '${noiseDbm}dBm' : '—',
                  color: const Color(0xFF4ADE80),
                  active: _showNoise,
                  theme: theme,
                  onTap: () => setState(() => _showNoise = !_showNoise),
                ),
              ],
            ),
          ),

          // Chart
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 8, right: 16, bottom: 16),
              child: _RfChart(
                noiseHistory: _showNoise ? noiseHistory : const [],
                rssiHistory: _showRssi ? rssiHistory : const [],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Value chip
// ---------------------------------------------------------------------------

class _ValueChip extends StatelessWidget {
  const _ValueChip({
    required this.label,
    required this.value,
    required this.color,
    required this.active,
    required this.theme,
    required this.onTap,
  });

  final String label;
  final String value;
  final Color color;
  final bool active;
  final ThemeData theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = active ? color : color.withAlpha(60);
    final effectiveValueColor =
        active ? Colors.white : Colors.white.withAlpha(60);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: effectiveColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: effectiveColor,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                active ? Icons.visibility : Icons.visibility_off,
                size: 12,
                color: effectiveColor,
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: effectiveValueColor,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chart widget
// ---------------------------------------------------------------------------

class _RfChart extends StatelessWidget {
  const _RfChart({required this.noiseHistory, required this.rssiHistory});

  final List<NoiseFloorReading> noiseHistory;
  final List<RssiReading> rssiHistory;

  static const double _yMax = -60.0;
  static const double _yMin = -120.0;
  static const double _yRange = _yMax - _yMin;
  static const int _visiblePoints = 120;

  static const List<int> _yTicks = [
    -60,
    -65,
    -70,
    -75,
    -80,
    -85,
    -90,
    -95,
    -100,
    -105,
    -110,
    -115,
    -120,
  ];

  @override
  Widget build(BuildContext context) {
    const yLabelWidth = 44.0;

    return Row(
      children: [
        SizedBox(
          width: yLabelWidth,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  for (final tick in _yTicks)
                    Positioned(
                      top:
                          _yToFraction(tick.toDouble()) *
                              constraints.maxHeight -
                          6,
                      right: 4,
                      child: Text(
                        '$tick',
                        style: const TextStyle(
                          color: Color(0xFF718096),
                          fontSize: 10,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        Expanded(
          child: CustomPaint(
            painter: _ChartPainter(
              noiseHistory: noiseHistory,
              rssiHistory: rssiHistory,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ],
    );
  }

  static double _yToFraction(double dBm) => (_yMax - dBm) / _yRange;
}

// ---------------------------------------------------------------------------
// CustomPainter — draws both series
// ---------------------------------------------------------------------------

class _ChartPainter extends CustomPainter {
  const _ChartPainter({required this.noiseHistory, required this.rssiHistory});

  final List<NoiseFloorReading> noiseHistory;
  final List<RssiReading> rssiHistory;

  static const double _yMax = -60.0;
  static const double _yMin = -120.0;
  static const double _yRange = _yMax - _yMin;
  static const int _visiblePoints = 120;

  static const Color _noiseColor = Color(0xFF4ADE80); // green
  static const Color _rssiColor = Color(0xFF38BDF8); // sky blue

  static const List<int> _gridTicks = [
    -60,
    -65,
    -70,
    -75,
    -80,
    -85,
    -90,
    -95,
    -100,
    -105,
    -110,
    -115,
    -120,
  ];

  double _yToY(double dBm, double h) => (_yMax - dBm) / _yRange * h;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // --- Grid ---
    final gridPaint =
        Paint()
          ..color = const Color(0xFF2D3748)
          ..strokeWidth = 0.8
          ..style = PaintingStyle.stroke;

    for (final tick in _gridTicks) {
      final y = _yToY(tick.toDouble(), h);
      _drawDashedPath(
        canvas,
        Path()
          ..moveTo(0, y)
          ..lineTo(w, y),
        gridPaint,
        dashLen: 6,
        gapLen: 4,
      );
    }

    // Draw noise floor first (behind RSSI)
    _drawSeries(
      canvas,
      size,
      noiseHistory.map((r) => r.dBm).toList(),
      _noiseColor,
    );
    _drawSeries(
      canvas,
      size,
      rssiHistory.map((r) => r.dBm).toList(),
      _rssiColor,
    );
  }

  void _drawSeries(Canvas canvas, Size size, List<int> data, Color color) {
    if (data.isEmpty) return;
    final w = size.width;
    final h = size.height;

    final visible =
        data.length > _visiblePoints
            ? data.sublist(data.length - _visiblePoints)
            : data;

    final count = visible.length;

    double xOfPoint(int i) {
      if (count >= _visiblePoints) return i / (_visiblePoints - 1) * w;
      final offset = (_visiblePoints - count) / (_visiblePoints - 1) * w;
      return offset + i / (_visiblePoints - 1) * w;
    }

    double yOfPoint(int i) =>
        _yToY(visible[i].toDouble().clamp(_yMin, _yMax), h);

    if (count < 2) {
      canvas.drawLine(
        Offset(0, yOfPoint(0)),
        Offset(w, yOfPoint(0)),
        Paint()
          ..color = color
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
      return;
    }

    // Area fill
    final fillPath = Path();
    fillPath.moveTo(xOfPoint(0), h);
    fillPath.lineTo(xOfPoint(0), yOfPoint(0));
    for (var i = 1; i < count; i++) {
      fillPath.lineTo(xOfPoint(i), yOfPoint(i));
    }
    fillPath.lineTo(xOfPoint(count - 1), h);
    fillPath.close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withAlpha(120), color.withAlpha(20)],
        ).createShader(Rect.fromLTWH(0, 0, w, h))
        ..style = PaintingStyle.fill,
    );

    // Line
    final linePath = Path();
    linePath.moveTo(xOfPoint(0), yOfPoint(0));
    for (var i = 1; i < count; i++) {
      linePath.lineTo(xOfPoint(i), yOfPoint(i));
    }

    canvas.drawPath(
      linePath,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Tip dot
    final tipX = xOfPoint(count - 1);
    final tipY = yOfPoint(count - 1);
    canvas.drawCircle(Offset(tipX, tipY), 4, Paint()..color = color);
    canvas.drawCircle(
      Offset(tipX, tipY),
      4,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  void _drawDashedPath(
    Canvas canvas,
    Path path,
    Paint paint, {
    required double dashLen,
    required double gapLen,
  }) {
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      var draw = true;
      while (distance < metric.length) {
        final len = draw ? dashLen : gapLen;
        if (draw) {
          canvas.drawPath(
            metric.extractPath(
              distance,
              math.min(distance + len, metric.length),
            ),
            paint,
          );
        }
        distance += len;
        draw = !draw;
      }
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.noiseHistory != noiseHistory || old.rssiHistory != rssiHistory;
}
