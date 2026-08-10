import 'package:flutter_test/flutter_test.dart';

import 'package:crypto_paper_trader/domain/usecases/backtest_runner.dart';
import 'package:crypto_paper_trader/domain/usecases/risk_metrics_calculator.dart';

EquityPoint _point(int dayOffset, double value) =>
    EquityPoint(timestamp: DateTime.utc(2024, 1, 1 + dayOffset), portfolioValue: value);

void main() {
  group('computeRiskMetrics — hand-calculated cases', () {
    test('100 -> 150 -> 75 over 2 days: zero mean return -> Sharpe exactly 0, drawdown 50%', () {
      // Returns: +50% (day0->1), -50% (day1->2). Mean = 0 exactly, so
      // regardless of variance/annualization, Sharpe = (0 - 0) / stdDev = 0.
      // Peak is 150 (day1); trough after the peak is 75 -> (150-75)/150 = 50%.
      final curve = [_point(0, 100), _point(1, 150), _point(2, 75)];

      final metrics = computeRiskMetrics(curve);

      expect(metrics.sharpeRatio, 0);
      expect(metrics.maxDrawdownPercent, 50);
    });

    test('a straight-line equity curve (identical returns each period) has null Sharpe', () {
      // Every return is exactly +10% -> zero variance -> undefined ratio,
      // not a divide-by-zero crash.
      final curve = [_point(0, 100), _point(1, 110), _point(2, 121), _point(3, 133.1)];

      final metrics = computeRiskMetrics(curve);

      expect(metrics.sharpeRatio, isNull);
      expect(metrics.maxDrawdownPercent, 0);
    });

    test('a monotonically falling curve has zero Sharpe-relevant peak after the first point', () {
      // Geometric decline of exactly -10% each step (100 -> 90 -> 81 ->
      // 72.9), so every period return is identical -> zero variance ->
      // Sharpe undefined, same edge case as the rising geometric curve
      // above, just falling instead.
      final curve = [_point(0, 100), _point(1, 90), _point(2, 81), _point(3, 72.9)];

      final metrics = computeRiskMetrics(curve);

      // Peak is the very first point (100); trough is the last (72.9).
      expect(metrics.maxDrawdownPercent, closeTo(27.1, 0.0001));
      expect(metrics.sharpeRatio, isNull);
    });

    test('a positive-trending curve with noise has a positive Sharpe ratio', () {
      final curve = [
        _point(0, 100),
        _point(1, 105),
        _point(2, 103),
        _point(3, 112),
        _point(4, 118),
      ];

      final metrics = computeRiskMetrics(curve);

      expect(metrics.sharpeRatio, isNotNull);
      expect(metrics.sharpeRatio, greaterThan(0));
    });

    test('a nonzero risk-free rate lowers the Sharpe ratio for the same returns', () {
      final curve = [
        _point(0, 100),
        _point(1, 105),
        _point(2, 103),
        _point(3, 112),
        _point(4, 118),
      ];

      final zeroRf = computeRiskMetrics(curve).sharpeRatio!;
      final withRf = computeRiskMetrics(curve, riskFreeRate: 0.5).sharpeRatio!;

      expect(withRf, lessThan(zeroRf));
    });

    test('fewer than 2 points yields a null Sharpe ratio and zero/definite drawdown', () {
      expect(computeRiskMetrics(const []).sharpeRatio, isNull);
      expect(computeRiskMetrics(const []).maxDrawdownPercent, 0);
      expect(computeRiskMetrics([_point(0, 100)]).sharpeRatio, isNull);
      expect(computeRiskMetrics([_point(0, 100)]).maxDrawdownPercent, 0);
    });
  });
}
