enum ConditionalOrderKind {
  stopLoss('STOP_LOSS'),
  takeProfit('TAKE_PROFIT');

  const ConditionalOrderKind(this.code);
  final String code;

  static ConditionalOrderKind fromCode(String code) =>
      ConditionalOrderKind.values.firstWhere((k) => k.code == code, orElse: () => stopLoss);
}

/// A pending stop-loss or take-profit at `users/{userId}/conditional_orders/
/// {orderId}` — checked every minute server-side by
/// functions/src/trading/checkConditionalOrders.ts against live prices, and
/// executed there (not on the client) so it fires even while the app is
/// closed, same as a real broker's stop-loss.
///
/// v1 scope: only ever closes/reduces an existing LONG position —
/// [ConditionalOrderKind.stopLoss] fires when the price falls to/through
/// [triggerPrice], [ConditionalOrderKind.takeProfit] when it rises to/
/// through it. There's no separate direction field; which way it fires is
/// implied entirely by [kind].
///
/// Pure domain entity — no Firestore types.
class ConditionalOrder {
  const ConditionalOrder({
    required this.id,
    required this.coinSymbol,
    required this.kind,
    required this.triggerPrice,
    required this.quantity,
    required this.isActive,
    required this.createdAt,
    required this.triggeredAt,
  });

  factory ConditionalOrder.fromMap(String id, Map<String, dynamic> map) {
    final createdAtRaw = map['created_at'];
    final triggeredAtRaw = map['triggered_at'];
    return ConditionalOrder(
      id: id,
      coinSymbol: map['coin_symbol'] as String,
      kind: ConditionalOrderKind.fromCode(map['kind'] as String),
      triggerPrice: (map['trigger_price'] as num).toDouble(),
      quantity: (map['quantity'] as num).toDouble(),
      isActive: map['is_active'] as bool? ?? false,
      createdAt:
          createdAtRaw == null ? DateTime.now() : (createdAtRaw as dynamic).toDate() as DateTime,
      triggeredAt:
          triggeredAtRaw == null ? null : (triggeredAtRaw as dynamic).toDate() as DateTime,
    );
  }

  final String id;
  final String coinSymbol;
  final ConditionalOrderKind kind;
  final double triggerPrice;
  final double quantity;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? triggeredAt;

  bool get isStopLoss => kind == ConditionalOrderKind.stopLoss;
  bool get isTakeProfit => kind == ConditionalOrderKind.takeProfit;
}
