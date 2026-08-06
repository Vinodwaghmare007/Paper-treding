/// A held quantity of one coin, keyed by symbol at
/// `users/{userId}/portfolio/{coinSymbol}`.
///
/// Pure domain entity — no Firestore types.
class PortfolioPosition {
  const PortfolioPosition({
    required this.coinSymbol,
    required this.totalQuantity,
    required this.avgBuyPrice,
  });

  final String coinSymbol;
  final double totalQuantity;
  final double avgBuyPrice;

  double get costBasis => totalQuantity * avgBuyPrice;

  /// Unrealized P&L at [currentPrice].
  double unrealizedPnl(double currentPrice) =>
      (currentPrice - avgBuyPrice) * totalQuantity;

  double marketValue(double currentPrice) => totalQuantity * currentPrice;

  @override
  String toString() =>
      'PortfolioPosition($coinSymbol qty=$totalQuantity avg=$avgBuyPrice)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PortfolioPosition &&
          coinSymbol == other.coinSymbol &&
          totalQuantity == other.totalQuantity &&
          avgBuyPrice == other.avgBuyPrice;

  @override
  int get hashCode => Object.hash(coinSymbol, totalQuantity, avgBuyPrice);
}
