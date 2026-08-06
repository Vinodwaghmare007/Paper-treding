import 'package:flutter/material.dart';

import '../../domain/usecases/backtest_runner.dart';

/// A minimal line chart for a backtest's equity curve. Hand-rolled with
/// [CustomPainter] rather than pulling in a charting package — an equity
/// curve is a single polyline plus a min/max label, which doesn't justify a
/// new dependency on top of the JS-based Lightweight Charts already used
/// for the live/replay candle chart.
class EquityCurveChart extends StatelessWidget {
  const EquityCurveChart({super.key, required this.points, required this.startingBalance});

  final List<EquityPoint> points;
  final double startingBalance;

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) {
      return const Center(
        child: Text('Not enough data to chart.', style: TextStyle(color: Colors.white38)),
      );
    }
    final values = points.map((p) => p.portfolioValue).toList();
    final minValue = values.reduce((a, b) => a < b ? a : b);
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    final endedUp = values.last >= startingBalance;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(maxValue.toStringAsFixed(0), style: const TextStyle(color: Colors.white38, fontSize: 10)),
            ],
          ),
        ),
        Expanded(
          child: CustomPaint(
            painter: _EquityCurvePainter(
              values: values,
              minValue: minValue,
              maxValue: maxValue,
              startingBalance: startingBalance,
              lineColor: endedUp ? const Color(0xFF26A69A) : const Color(0xFFEF5350),
            ),
            size: Size.infinite,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(minValue.toStringAsFixed(0), style: const TextStyle(color: Colors.white38, fontSize: 10)),
        ),
      ],
    );
  }
}

class _EquityCurvePainter extends CustomPainter {
  _EquityCurvePainter({
    required this.values,
    required this.minValue,
    required this.maxValue,
    required this.startingBalance,
    required this.lineColor,
  });

  final List<double> values;
  final double minValue;
  final double maxValue;
  final double startingBalance;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final range = (maxValue - minValue).abs() < 1e-9 ? 1.0 : maxValue - minValue;

    double yFor(double value) => size.height - ((value - minValue) / range) * size.height;
    double xFor(int index) => values.length <= 1 ? 0 : (index / (values.length - 1)) * size.width;

    // A dashed reference line at the starting balance, so the eye has a
    // "break-even" baseline to compare the curve against.
    if (startingBalance >= minValue && startingBalance <= maxValue) {
      final baselineY = yFor(startingBalance);
      final dashPaint = Paint()
        ..color = Colors.white24
        ..strokeWidth = 1;
      var x = 0.0;
      while (x < size.width) {
        canvas.drawLine(Offset(x, baselineY), Offset(x + 4, baselineY), dashPaint);
        x += 8;
      }
    }

    final path = Path()..moveTo(xFor(0), yFor(values[0]));
    for (var i = 1; i < values.length; i++) {
      path.lineTo(xFor(i), yFor(values[i]));
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _EquityCurvePainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.lineColor != lineColor;
}
