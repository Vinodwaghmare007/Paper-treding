/// A retrospective-only note on one already-closed trade — see
/// `functions/src/rationale/addTradeRationale.ts` for the server-side
/// constraints that keep this from being disguised forward guidance
/// (closed-trade-only, timestamped after the trade, content-filtered).
class TradeRationale {
  const TradeRationale({
    required this.orderId,
    required this.coinSymbol,
    required this.text,
    required this.createdAt,
    required this.flaggedForReview,
  });

  /// The closed (SELL) order this note is attached to. Not itself
  /// readable by a visitor (orders/{orderId} is owner-only) — see
  /// addTradeRationale.ts's doc comment for why [coinSymbol] is
  /// denormalized onto the rationale doc rather than requiring a second,
  /// visitor-inaccessible read.
  final String orderId;
  final String coinSymbol;
  final String text;
  final DateTime createdAt;

  /// True if the text matched a forward-looking phrasing pattern (e.g.
  /// "will", "buy now") — an imperfect soft flag, not a rejection; the
  /// note is still shown normally. Not currently surfaced in the UI
  /// beyond being available for a future moderation view.
  final bool flaggedForReview;

  factory TradeRationale.fromMap(String orderId, Map<String, dynamic> map) {
    return TradeRationale(
      orderId: orderId,
      coinSymbol: map['coin_symbol'] as String? ?? '',
      text: map['text'] as String,
      createdAt: (map['created_at'] as dynamic).toDate() as DateTime,
      flaggedForReview: map['flagged_for_review'] as bool? ?? false,
    );
  }
}
