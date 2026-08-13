/// A held quantity of one coin, keyed by symbol at
/// `users/{userId}/portfolio/{coinSymbol}`.
///
/// [totalQuantity] is signed: positive is a long position, negative is a
/// short (see [TradeMath]'s doc comment for the full short-selling model).
/// [avgBuyPrice] is the weighted-average entry price either way — for a
/// short that's the average price the position was *sold* to open, not a
/// literal "buy" price.
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

  bool get isShort => totalQuantity < 0;
  bool get isLong => totalQuantity > 0;

  double get costBasis => totalQuantity * avgBuyPrice;

  /// Unrealized P&L at [currentPrice]. Sign-agnostic: for a short (negative
  /// [totalQuantity]), a [currentPrice] below [avgBuyPrice] yields a
  /// positive (profitable) result with no extra branching needed.
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
