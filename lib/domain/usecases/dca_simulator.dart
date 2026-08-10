import '../../data/models/kline_tick.dart';

enum DcaFrequency {
  weekly('Weekly'),
  monthly('Monthly');

  const DcaFrequency(this.label);
  final String label;
}

/// One point on the DCA simulator's two-line comparison chart —
/// cumulative amount invested vs. cumulative mark-to-market value, both
/// as of [date] (the date of a scheduled purchase).
class DcaSeriesPoint {
  const DcaSeriesPoint({
    required this.date,
    required this.investedCumulative,
    required this.valueCumulative,
  });

  final DateTime date;
  final double investedCumulative;
  final double valueCumulative;
}

class DcaResult {
  const DcaResult({
    required this.totalInvested,
    required this.totalUnits,
    required this.currentValue,
    required this.series,
  });

  final double totalInvested;
  final double totalUnits;

  /// `totalUnits * latest available price` — the final data point's close.
  final double currentValue;
  final List<DcaSeriesPoint> series;

  double get returnPercent =>
      totalInvested == 0 ? 0 : (currentValue - totalInvested) / totalInvested * 100;
}

/// Thrown when there's no historical data to simulate against at all.
class DcaSimulatorException implements Exception {
  DcaSimulatorException(this.message);
  final String message;

  @override
  String toString() => 'DcaSimulatorException: $message';
}

/// Pure "what if I'd invested a fixed amount on a schedule" simulation —
/// takes already-fetched daily [candles] rather than doing its own
/// network I/O, so it runs on the exact same historical data source as
/// the 5-year chart (whichever `BinanceRestService.fetchKlinesRange` call
/// the caller made) instead of a separate dataset, and so it's directly
/// unit-testable against a hand-built candle list.
///
/// [candles] must be sorted oldest-first (the convention every other
/// candle list in this app already uses) and cover at least [startDate]
/// through [endDate] — a purchase date past the last available candle
/// uses that last candle's price rather than failing, since real trading
/// data always lags "now" by at least one candle interval.
DcaResult simulateDca({
  required List<Candle> candles,
  required double recurringAmount,
  required DcaFrequency frequency,
  required DateTime startDate,
  required DateTime endDate,
}) {
  if (candles.isEmpty) {
    throw DcaSimulatorException('No historical price data available for this range.');
  }
  if (recurringAmount <= 0) {
    throw DcaSimulatorException('The recurring amount must be greater than zero.');
  }

  final sorted = [...candles]..sort((a, b) => a.openTimeMs.compareTo(b.openTimeMs));

  double priceOnOrAfter(DateTime date) {
    final targetMs = date.toUtc().millisecondsSinceEpoch;
    for (final candle in sorted) {
      if (candle.openTimeMs >= targetMs) return candle.close;
    }
    return sorted.last.close;
  }

  final purchaseDates = <DateTime>[];
  var cursor = startDate.toUtc();
  final end = endDate.toUtc();
  while (!cursor.isAfter(end)) {
    purchaseDates.add(cursor);
    cursor = frequency == DcaFrequency.weekly
        ? cursor.add(const Duration(days: 7))
        : DateTime.utc(cursor.year, cursor.month + 1, cursor.day);
  }

  var totalInvested = 0.0;
  var totalUnits = 0.0;
  final series = <DcaSeriesPoint>[];

  for (final date in purchaseDates) {
    final price = priceOnOrAfter(date);
    totalInvested += recurringAmount;
    totalUnits += recurringAmount / price;
    series.add(DcaSeriesPoint(
      date: date,
      investedCumulative: totalInvested,
      valueCumulative: totalUnits * price,
    ));
  }

  final latestPrice = sorted.last.close;
  return DcaResult(
    totalInvested: totalInvested,
    totalUnits: totalUnits,
    currentValue: totalUnits * latestPrice,
    series: series,
  );
}
