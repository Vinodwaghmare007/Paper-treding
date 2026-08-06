/// A condition tree for the strategy backtester: AND/OR combinations of
/// indicator comparisons, each a leaf that knows how to evaluate itself
/// against precomputed indicator series.
///
/// Extensibility is the point of this design: adding a new indicator type
/// means adding one new [IndicatorRequirement] subtype, one new
/// [BacktestCondition] leaf, and (if it's a genuinely new computation) one
/// new case in the bundle-building switch in `backtest_runner.dart`. The
/// tree-walking evaluator (AND/OR combinators, and the runner's candle
/// loop) never changes — it only ever calls `condition.evaluate(...)`
/// recursively and has no per-indicator branching.
library;

enum ComparisonOperator { lessThan, greaterThan }

enum CrossDirection { up, down }

/// One computation a condition needs: an indicator + its parameters,
/// value-equatable so the same requirement referenced by multiple
/// conditions in a tree is only computed once.
sealed class IndicatorRequirement {
  const IndicatorRequirement();
}

class RsiRequirement extends IndicatorRequirement {
  const RsiRequirement(this.period);
  final int period;

  @override
  bool operator ==(Object other) =>
      other is RsiRequirement && other.period == period;
  @override
  int get hashCode => Object.hash(RsiRequirement, period);
  @override
  String toString() => 'RSI($period)';
}

class SmaRequirement extends IndicatorRequirement {
  const SmaRequirement(this.period);
  final int period;

  @override
  bool operator ==(Object other) =>
      other is SmaRequirement && other.period == period;
  @override
  int get hashCode => Object.hash(SmaRequirement, period);
  @override
  String toString() => 'SMA($period)';
}

/// MACD produces two series (the MACD line and its signal line) from one
/// underlying computation. Modeled as two distinct requirements sharing the
/// same parameters so the generic single-series bundle still works — the
/// bundle builder recognizes matching (fast, slow, signal) parameters and
/// computes MACD once for both.
class MacdLineRequirement extends IndicatorRequirement {
  const MacdLineRequirement({
    this.fastPeriod = 12,
    this.slowPeriod = 26,
    this.signalPeriod = 9,
  });
  final int fastPeriod;
  final int slowPeriod;
  final int signalPeriod;

  @override
  bool operator ==(Object other) =>
      other is MacdLineRequirement &&
      other.fastPeriod == fastPeriod &&
      other.slowPeriod == slowPeriod &&
      other.signalPeriod == signalPeriod;
  @override
  int get hashCode => Object.hash(MacdLineRequirement, fastPeriod, slowPeriod, signalPeriod);
  @override
  String toString() => 'MACD_LINE($fastPeriod,$slowPeriod,$signalPeriod)';
}

class MacdSignalRequirement extends IndicatorRequirement {
  const MacdSignalRequirement({
    this.fastPeriod = 12,
    this.slowPeriod = 26,
    this.signalPeriod = 9,
  });
  final int fastPeriod;
  final int slowPeriod;
  final int signalPeriod;

  @override
  bool operator ==(Object other) =>
      other is MacdSignalRequirement &&
      other.fastPeriod == fastPeriod &&
      other.slowPeriod == slowPeriod &&
      other.signalPeriod == signalPeriod;
  @override
  int get hashCode => Object.hash(MacdSignalRequirement, fastPeriod, slowPeriod, signalPeriod);
  @override
  String toString() => 'MACD_SIGNAL($fastPeriod,$slowPeriod,$signalPeriod)';
}

/// Precomputed indicator series for one backtest run, plus the raw close
/// prices every "price crosses X" condition needs. Built once per run by
/// walking the condition tree's [IndicatorRequirement]s before the
/// candle-by-candle evaluation loop starts, so no condition ever
/// recomputes an indicator mid-walk.
class IndicatorBundle {
  const IndicatorBundle({
    required this.closePrices,
    required Map<IndicatorRequirement, List<double>> series,
  }) : _series = series;

  final List<double> closePrices;
  final Map<IndicatorRequirement, List<double>> _series;

  List<double> seriesFor(IndicatorRequirement requirement) {
    final series = _series[requirement];
    if (series == null) {
      throw StateError(
        'Indicator not precomputed: $requirement — this means '
        'collectRequirements() didn\'t register it before the bundle was built.',
      );
    }
    return series;
  }
}

/// A boolean condition evaluated at one candle index. AND/OR nodes recurse
/// over their children; leaf nodes look up their own precomputed series.
sealed class BacktestCondition {
  const BacktestCondition();

  /// Adds every [IndicatorRequirement] this condition (and, for
  /// combinators, its children) needs precomputed before [evaluate] can run.
  void collectRequirements(Set<IndicatorRequirement> requirements);

  /// True if the condition holds at [index] in [bundle]. Returns false
  /// (never throws) for indices too early to have a defined indicator
  /// value (e.g. index 3 of an RSI(14)) — an undecided condition simply
  /// doesn't fire, it isn't an error.
  bool evaluate(IndicatorBundle bundle, int index);
}

class AndCondition extends BacktestCondition {
  const AndCondition(this.children);
  final List<BacktestCondition> children;

  @override
  void collectRequirements(Set<IndicatorRequirement> requirements) {
    for (final child in children) {
      child.collectRequirements(requirements);
    }
  }

  @override
  bool evaluate(IndicatorBundle bundle, int index) =>
      children.every((c) => c.evaluate(bundle, index));
}

class OrCondition extends BacktestCondition {
  const OrCondition(this.children);
  final List<BacktestCondition> children;

  @override
  void collectRequirements(Set<IndicatorRequirement> requirements) {
    for (final child in children) {
      child.collectRequirements(requirements);
    }
  }

  @override
  bool evaluate(IndicatorBundle bundle, int index) =>
      children.any((c) => c.evaluate(bundle, index));
}

/// RSI(period) < threshold, or RSI(period) > threshold.
class RsiThresholdCondition extends BacktestCondition {
  const RsiThresholdCondition({
    required this.period,
    required this.comparisonOperator,
    required this.threshold,
  });

  final int period;
  final ComparisonOperator comparisonOperator;
  final double threshold;

  @override
  void collectRequirements(Set<IndicatorRequirement> requirements) {
    requirements.add(RsiRequirement(period));
  }

  @override
  bool evaluate(IndicatorBundle bundle, int index) {
    final series = bundle.seriesFor(RsiRequirement(period));
    if (index < 0 || index >= series.length) return false;
    final value = series[index];
    if (value.isNaN) return false;
    return comparisonOperator == ComparisonOperator.lessThan
        ? value < threshold
        : value > threshold;
  }
}

/// RSI(period) crosses up/down through threshold between the previous and
/// current candle.
class RsiCrossesThresholdCondition extends BacktestCondition {
  const RsiCrossesThresholdCondition({
    required this.period,
    required this.direction,
    required this.threshold,
  });

  final int period;
  final CrossDirection direction;
  final double threshold;

  @override
  void collectRequirements(Set<IndicatorRequirement> requirements) {
    requirements.add(RsiRequirement(period));
  }

  @override
  bool evaluate(IndicatorBundle bundle, int index) {
    if (index < 1) return false;
    final series = bundle.seriesFor(RsiRequirement(period));
    if (index >= series.length) return false;
    final previous = series[index - 1];
    final current = series[index];
    if (previous.isNaN || current.isNaN) return false;
    return direction == CrossDirection.up
        ? previous <= threshold && current > threshold
        : previous >= threshold && current < threshold;
  }
}

/// MACD line crosses up/down through its signal line between the previous
/// and current candle — the standard MACD entry/exit trigger.
class MacdCrossCondition extends BacktestCondition {
  const MacdCrossCondition({
    this.fastPeriod = 12,
    this.slowPeriod = 26,
    this.signalPeriod = 9,
    required this.direction,
  });

  final int fastPeriod;
  final int slowPeriod;
  final int signalPeriod;
  final CrossDirection direction;

  @override
  void collectRequirements(Set<IndicatorRequirement> requirements) {
    requirements.add(MacdLineRequirement(
        fastPeriod: fastPeriod, slowPeriod: slowPeriod, signalPeriod: signalPeriod));
    requirements.add(MacdSignalRequirement(
        fastPeriod: fastPeriod, slowPeriod: slowPeriod, signalPeriod: signalPeriod));
  }

  @override
  bool evaluate(IndicatorBundle bundle, int index) {
    if (index < 1) return false;
    final line = bundle.seriesFor(
        MacdLineRequirement(fastPeriod: fastPeriod, slowPeriod: slowPeriod, signalPeriod: signalPeriod));
    final signal = bundle.seriesFor(
        MacdSignalRequirement(fastPeriod: fastPeriod, slowPeriod: slowPeriod, signalPeriod: signalPeriod));
    if (index >= line.length || index >= signal.length) return false;

    final prevDiff = line[index - 1] - signal[index - 1];
    final currDiff = line[index] - signal[index];
    if (prevDiff.isNaN || currDiff.isNaN) return false;

    return direction == CrossDirection.up
        ? prevDiff <= 0 && currDiff > 0
        : prevDiff >= 0 && currDiff < 0;
  }
}

/// Close price crosses up/down through SMA(period) between the previous
/// and current candle.
class PriceCrossesSmaCondition extends BacktestCondition {
  const PriceCrossesSmaCondition({
    required this.period,
    required this.direction,
  });

  final int period;
  final CrossDirection direction;

  @override
  void collectRequirements(Set<IndicatorRequirement> requirements) {
    requirements.add(SmaRequirement(period));
  }

  @override
  bool evaluate(IndicatorBundle bundle, int index) {
    if (index < 1) return false;
    final sma = bundle.seriesFor(SmaRequirement(period));
    final prices = bundle.closePrices;
    if (index >= sma.length || index >= prices.length) return false;

    final prevSma = sma[index - 1];
    final currSma = sma[index];
    if (prevSma.isNaN || currSma.isNaN) return false;

    final prevPrice = prices[index - 1];
    final currPrice = prices[index];

    return direction == CrossDirection.up
        ? prevPrice <= prevSma && currPrice > currSma
        : prevPrice >= prevSma && currPrice < currSma;
  }
}
