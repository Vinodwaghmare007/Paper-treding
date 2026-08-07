/// The community's current "market weather" — a coarse volatility read on
/// BTCUSDT, computed server-side by functions/src/weather/
/// computeMarketWeather.ts every 4 hours. Pure domain entity — no
/// Firestore types (see market_weather_source.dart, which fetches this via
/// a plain REST call rather than the Firestore SDK).
class MarketWeather {
  const MarketWeather({
    required this.tier,
    required this.iconKey,
    required this.stdDevPct,
    required this.symbol,
    required this.updatedAt,
  });

  /// One of "Calm", "Active", "Volatile", "Extreme" — kept as the raw
  /// server string rather than a parallel Dart enum since it's used only
  /// for display, and a typo'd/renamed tier should degrade to "show the
  /// text as-is" rather than throw.
  final String tier;
  final String iconKey;
  final double stdDevPct;
  final String symbol;
  final DateTime updatedAt;
}
