/// Hourly, symbol-scoped aggregate of the community's BUY vs SELL orders,
/// written by functions/src/sentiment/aggregateSentiment.ts. Aggregate
/// counts/percentages only — never traceable to an individual user or
/// order. Pure domain entity — no Firestore types.
class CommunitySentiment {
  const CommunitySentiment({
    required this.symbol,
    required this.bullishPct,
    required this.bearishPct,
    required this.totalOrders,
    required this.windowMinutes,
    required this.updatedAt,
  });

  final String symbol;

  /// Null when [totalOrders] is 0 — there's nothing to compute a
  /// percentage of yet.
  final double? bullishPct;
  final double? bearishPct;
  final int totalOrders;
  final int windowMinutes;
  final DateTime updatedAt;

  bool get hasEnoughData => totalOrders > 0;
}
