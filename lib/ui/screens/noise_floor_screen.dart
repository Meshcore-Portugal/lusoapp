import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../protocol/commands.dart';
import '../../providers/radio_providers.dart';

/// Real-time noise floor chart.
///
/// Polls `CMD_GET_STATS / STATS_TYPE_RADIO` every 2 seconds while the screen
/// is active and renders a fixed-range area chart (-60 dBm … -120 dBm) that
/// scrolls as new readings arrive.
class NoiseFloorScreen extends ConsumerStatefulWidget {
  const NoiseFloorScreen({super.key});

  @override
  ConsumerState<NoiseFloorScreen> createState() => _NoiseFloorScreenState();
}

class _NoiseFloorScreenState extends ConsumerState<NoiseFloorScreen> {
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    // Fire an immediate request and then poll every 2 s.
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
    final history = ref.watch(noiseFloorHistoryProvider);
    final current = ref.watch(radioStatsRadioProvider);
    final theme = Theme.of(context);

    final currentDbm = current?.noiseFloor;
    final label = currentDbm != null ? '${currentDbm}dBm' : '—';

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        title: const Text('Noise Floor'),
        backgroundColor: const Color(0xFF0D1117),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Current value readout
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              label,
              style: theme.textTheme.headlineMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
          ),

          // Chart
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 8, right: 16, bottom: 16),
              child: _NoiseFloorChart(history: history),
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

/// Fixed-range (-60 … -120 dBm) scrolling area chart.
/// Shows the last [_visiblePoints] readings; older readings scroll off the
/// left edge as new ones arrive.
class _NoiseFloorChart extends StatelessWidget {
  const _NoiseFloorChart({required this.history});

  final List<NoiseFloorReading> history;

  // Visible Y range
  static const double _yMax = -60.0;
  static const double _yMin = -120.0;
  static const double _yRange = _yMax - _yMin; // 60

  // How many readings to show at once
  static const int _visiblePoints = 120;

  // Y-axis labels every 5 dBm
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
        // Y-axis labels
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
                          color: Color(0xFFD97706),
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

        // Chart area
        Expanded(
          child: CustomPaint(
            painter: _ChartPainter(history: history),
            child: const SizedBox.expand(),
          ),
        ),
      ],
    );
  }

  /// Maps a dBm value to a top-offset fraction (0 = top = -60 dBm).
  static double _yToFraction(double dBm) {
    return (_yMax - dBm) / _yRange;
  }
}

// ---------------------------------------------------------------------------
// CustomPainter
// ---------------------------------------------------------------------------

class _ChartPainter extends CustomPainter {
  const _ChartPainter({required this.history});

  final List<NoiseFloorReading> history;

  static const double _yMax = -60.0;
  static const double _yMin = -120.0;
  static const double _yRange = _yMax - _yMin;
  static const int _visiblePoints = 120;

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

  double _yToY(double dBm, double height) {
    return (_yMax - dBm) / _yRange * height;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // --- Grid lines ---
    final gridPaint =
        Paint()
          ..color = const Color(0xFF2D3748)
          ..strokeWidth = 0.8
          ..style = PaintingStyle.stroke;

    for (final tick in _gridTicks) {
      final y = _yToY(tick.toDouble(), h);
      final path =
          Path()
            ..moveTo(0, y)
            ..lineTo(w, y);
      // Dashed line effect
      _drawDashedPath(canvas, path, gridPaint, dashLen: 6, gapLen: 4);
    }

    if (history.isEmpty) return;

    // Use the last _visiblePoints readings
    final visible =
        history.length > _visiblePoints
            ? history.sublist(history.length - _visiblePoints)
            : history;

    if (visible.length < 2) {
      // Only 1 point — draw a horizontal line at that value
      final y = _yToY(visible.first.dBm.toDouble().clamp(_yMin, _yMax), h);
      final linePaint =
          Paint()
            ..color = const Color(0xFF4ADE80)
            ..strokeWidth = 2
            ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(0, y), Offset(w, y), linePaint);
      return;
    }

    final count = visible.length;
    double xOf(int i) => i / (_visiblePoints - 1) * w;
    double yOf(int i) =>
        _yToY(visible[i].dBm.toDouble().clamp(_yMin, _yMax), h);

    // Align the rightmost point to the right edge.
    // The leftmost rendered point starts at xOf(0) in a full-width context
    // where the total visible window always represents _visiblePoints slots.
    // When history is shorter, compress to the right.
    double xOfPoint(int i) {
      if (count >= _visiblePoints) return xOf(i);
      // Compress: latest point is at right edge.
      final offset = (_visiblePoints - count) / (_visiblePoints - 1) * w;
      return offset + i / (_visiblePoints - 1) * w;
    }

    // --- Area fill ---
    final fillPath = Path();
    fillPath.moveTo(xOfPoint(0), h);
    fillPath.lineTo(xOfPoint(0), yOf(0));
    for (var i = 1; i < count; i++) {
      fillPath.lineTo(xOfPoint(i), yOf(i));
    }
    fillPath.lineTo(xOfPoint(count - 1), h);
    fillPath.close();

    final fillPaint =
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF4ADE80).withAlpha(180),
              const Color(0xFF4ADE80).withAlpha(40),
            ],
          ).createShader(Rect.fromLTWH(0, 0, w, h))
          ..style = PaintingStyle.fill;

    canvas.drawPath(fillPath, fillPaint);

    // --- Line ---
    final linePath = Path();
    linePath.moveTo(xOfPoint(0), yOf(0));
    for (var i = 1; i < count; i++) {
      linePath.lineTo(xOfPoint(i), yOf(i));
    }

    final linePaint =
        Paint()
          ..color = const Color(0xFF4ADE80)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(linePath, linePaint);

    // --- Tip dot ---
    final tipX = xOfPoint(count - 1);
    final tipY = yOf(count - 1);
    canvas.drawCircle(
      Offset(tipX, tipY),
      4,
      Paint()..color = const Color(0xFF4ADE80),
    );
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
    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      var distance = 0.0;
      var draw = true;
      while (distance < metric.length) {
        final len = draw ? dashLen : gapLen;
        if (draw) {
          final end = math.min(distance + len, metric.length);
          canvas.drawPath(metric.extractPath(distance, end), paint);
        }
        distance += len;
        draw = !draw;
      }
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) => old.history != history;
}
