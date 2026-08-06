/// Pure technical-indicator functions shared by the strategy backtester.
///
/// Every function returns a list the same length as its input, with
/// `double.nan` at indices too early to have a defined value (e.g. index 3
/// of an SMA(20)) — callers check `.isNaN` rather than the function
/// throwing or truncating the series, so indices stay aligned with the
/// input candle array.
library;

/// Simple moving average over the trailing [period] prices.
List<double> calculateSMA(List<double> prices, int period) {
  if (period < 1) throw ArgumentError.value(period, 'period', 'must be >= 1');
  final result = List<double>.filled(prices.length, double.nan);
  var sum = 0.0;
  for (var i = 0; i < prices.length; i++) {
    sum += prices[i];
    if (i >= period) sum -= prices[i - period];
    if (i >= period - 1) result[i] = sum / period;
  }
  return result;
}

/// Exponential moving average over [period]. Seeds with a simple average of
/// the first [period] *consecutive non-NaN* input values (rather than
/// requiring the whole series to be NaN-free), so this also works directly
/// on an already-NaN-prefixed series — e.g. seeding MACD's signal line from
/// the MACD line, which itself starts with `slowPeriod - 1` leading NaNs.
List<double> calculateEMA(List<double> prices, int period) {
  if (period < 1) throw ArgumentError.value(period, 'period', 'must be >= 1');
  final result = List<double>.filled(prices.length, double.nan);
  final multiplier = 2 / (period + 1);

  var validRunStart = 0;
  var seeded = false;

  for (var i = 0; i < prices.length; i++) {
    if (prices[i].isNaN) {
      validRunStart = i + 1;
      seeded = false;
      continue;
    }
    if (!seeded) {
      if (i - validRunStart + 1 == period) {
        var sum = 0.0;
        for (var j = validRunStart; j <= i; j++) {
          sum += prices[j];
        }
        result[i] = sum / period;
        seeded = true;
      }
    } else {
      result[i] = (prices[i] - result[i - 1]) * multiplier + result[i - 1];
    }
  }
  return result;
}

/// Relative Strength Index using Wilder's smoothing (the original,
/// standard RSI formula — not a simple-moving-average approximation):
///
/// * The first average gain/loss (at index [period]) is a plain average of
///   the first [period] gains/losses.
/// * Every average after that is smoothed:
///   `avg[i] = (avg[i-1] * (period - 1) + value[i]) / period`.
/// * `RSI = 100 - 100 / (1 + avgGain/avgLoss)`, with the standard boundary
///   cases: no losses at all -> RSI 100; no gains at all -> RSI 0; neither
///   (a perfectly flat window) -> RSI 50.
List<double> calculateRSI(List<double> prices, int period) {
  if (period < 1) throw ArgumentError.value(period, 'period', 'must be >= 1');
  final result = List<double>.filled(prices.length, double.nan);
  if (prices.length <= period) return result;

  final gains = List<double>.filled(prices.length, 0);
  final losses = List<double>.filled(prices.length, 0);
  for (var i = 1; i < prices.length; i++) {
    final change = prices[i] - prices[i - 1];
    gains[i] = change > 0 ? change : 0;
    losses[i] = change < 0 ? -change : 0;
  }

  var avgGain = 0.0;
  var avgLoss = 0.0;
  for (var i = 1; i <= period; i++) {
    avgGain += gains[i];
    avgLoss += losses[i];
  }
  avgGain /= period;
  avgLoss /= period;
  result[period] = _rsiFromAverages(avgGain, avgLoss);

  for (var i = period + 1; i < prices.length; i++) {
    avgGain = (avgGain * (period - 1) + gains[i]) / period;
    avgLoss = (avgLoss * (period - 1) + losses[i]) / period;
    result[i] = _rsiFromAverages(avgGain, avgLoss);
  }
  return result;
}

double _rsiFromAverages(double avgGain, double avgLoss) {
  if (avgGain == 0 && avgLoss == 0) return 50;
  if (avgLoss == 0) return 100;
  if (avgGain == 0) return 0;
  final rs = avgGain / avgLoss;
  return 100 - 100 / (1 + rs);
}

/// MACD line (`EMA(fastPeriod) - EMA(slowPeriod)`) and its signal line
/// (`EMA(macdLine, signalPeriod)`).
typedef MacdSeries = ({List<double> macdLine, List<double> signalLine});

MacdSeries calculateMACD(
  List<double> prices, {
  int fastPeriod = 12,
  int slowPeriod = 26,
  int signalPeriod = 9,
}) {
  if (fastPeriod >= slowPeriod) {
    throw ArgumentError('fastPeriod ($fastPeriod) must be less than slowPeriod ($slowPeriod)');
  }
  final fastEma = calculateEMA(prices, fastPeriod);
  final slowEma = calculateEMA(prices, slowPeriod);
  final macdLine = List<double>.generate(prices.length, (i) {
    if (fastEma[i].isNaN || slowEma[i].isNaN) return double.nan;
    return fastEma[i] - slowEma[i];
  });
  final signalLine = calculateEMA(macdLine, signalPeriod);
  return (macdLine: macdLine, signalLine: signalLine);
}
