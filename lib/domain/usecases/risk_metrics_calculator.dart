import 'dart:math';

import 'backtest_runner.dart';

/// Sharpe Ratio and Max Drawdown for a backtest's equity curve — shown
/// alongside the existing P&L/win-rate stats on the backtest results
/// screen (backtester_screen.dart's `_ResultsSection`).
class RiskMetrics {
  const RiskMetrics({required this.sharpeRatio, required this.maxDrawdownPercent});

  /// Null when there's not enough data to compute a meaningful ratio:
  /// fewer than 2 equity-curve points (no return to measure at all), or
  /// zero return variance (a division by zero the formula can't answer —
  /// e.g. a backtest with no trades at all, where the curve is flat).
  final double? sharpeRatio;

  final double maxDrawdownPercent;
}

/// Computes annualized Sharpe Ratio and max drawdown from a backtest's
/// (possibly irregularly-sampled) equity curve.
///
/// [riskFreeRate] is an *annualized* rate as a fraction (0.05 = 5%/year),
/// defaulting to 0. Zero is the appropriate default for this app rather
/// than e.g. a T-bill rate: this is an educational crypto paper-trading
/// simulator used by people in many different countries, each with its
/// own "risk-free" benchmark (US T-bills, Indian G-secs, etc.) — there is
/// no single correct non-zero default, and 0 keeps the ratio meaning
/// "return per unit of risk taken" rather than silently assuming a US-
/// centric benchmark nobody configured. Callers who want a specific
/// benchmark can pass their own rate.
RiskMetrics computeRiskMetrics(List<EquityPoint> equityCurve, {double riskFreeRate = 0}) {
  return RiskMetrics(
    sharpeRatio: _computeSharpeRatio(equityCurve, riskFreeRate),
    maxDrawdownPercent: _computeMaxDrawdownPercent(equityCurve),
  );
}

double? _computeSharpeRatio(List<EquityPoint> equityCurve, double riskFreeRate) {
  if (equityCurve.length < 2) return null;

  final periodReturns = <double>[];
  for (var i = 1; i < equityCurve.length; i++) {
    final prev = equityCurve[i - 1].portfolioValue;
    final curr = equityCurve[i].portfolioValue;
    if (prev <= 0) continue;
    periodReturns.add((curr - prev) / prev);
  }
  if (periodReturns.length < 2) return null;

  final meanReturn = periodReturns.reduce((a, b) => a + b) / periodReturns.length;
  final sumSquaredDiffs = periodReturns
      .map((r) => (r - meanReturn) * (r - meanReturn))
      .reduce((a, b) => a + b);
  // Sample variance (n-1 denominator) — periodReturns.length >= 2 here,
  // so this never divides by zero.
  final variance = sumSquaredDiffs / (periodReturns.length - 1);
  final periodStdDev = sqrt(variance);
  if (periodStdDev == 0) return null;

  // Annualizes by deriving how many return-periods actually occur in a
  // year from the curve's own real elapsed time, rather than assuming a
  // fixed "daily" or "monthly" cadence — the equity curve's sampling
  // interval varies with backtest length (see backtest_runner.dart's
  // `sampleEvery`), so this has to work for any interval.
  final totalDurationDays =
      equityCurve.last.timestamp.difference(equityCurve.first.timestamp).inMinutes / (60 * 24);
  if (totalDurationDays <= 0) return null;
  final periodsPerYear = (periodReturns.length / totalDurationDays) * 365;

  final annualizedMeanReturn = meanReturn * periodsPerYear;
  final annualizedStdDev = periodStdDev * sqrt(periodsPerYear);
  if (annualizedStdDev == 0) return null;

  return (annualizedMeanReturn - riskFreeRate) / annualizedStdDev;
}

double _computeMaxDrawdownPercent(List<EquityPoint> equityCurve) {
  if (equityCurve.isEmpty) return 0;

  var peak = equityCurve.first.portfolioValue;
  var maxDrawdown = 0.0;
  for (final point in equityCurve) {
    if (point.portfolioValue > peak) peak = point.portfolioValue;
    if (peak > 0) {
      final drawdown = (peak - point.portfolioValue) / peak * 100;
      if (drawdown > maxDrawdown) maxDrawdown = drawdown;
    }
  }
  return maxDrawdown;
}
