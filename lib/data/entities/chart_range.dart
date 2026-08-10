/// A chart time-range option, each paired with the Binance kline interval
/// used to render it. Longer ranges use a coarser interval rather than
/// literally fetching years of 1-minute candles — 5 years of 1m candles
/// would be millions of bars; keeping every range's candle count under
/// ~400 keeps every range a single REST call (Binance caps one request at
/// 1000 candles) and a normal-sized chart payload.
enum ChartRange {
  day1('1D', '5m', 288),
  week1('1W', '1h', 168),
  days30('30D', '4h', 180),
  days90('90D', '1d', 90),
  year1('1Y', '1d', 365),
  year5('5Y', '1w', 261);

  const ChartRange(this.label, this.klineInterval, this.candleLimit);

  /// Short button label, e.g. `'1D'`.
  final String label;

  /// Binance kline interval used both for the seed REST fetch and the live
  /// WebSocket subscription — they must match, or the live tick's candle
  /// bucket won't line up with the seeded history's bucket size.
  final String klineInterval;

  /// How many candles to request at [klineInterval] to cover this range.
  final int candleLimit;
}
