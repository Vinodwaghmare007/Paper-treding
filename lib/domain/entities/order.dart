/// Side of a trade. Matches the `order_type` field in
/// `users/{userId}/orders/{orderId}`.
enum OrderType { buy, sell }

extension OrderTypeCode on OrderType {
  String get code => switch (this) {
        OrderType.buy => 'BUY',
        OrderType.sell => 'SELL',
      };

  static OrderType fromCode(String code) => switch (code) {
        'BUY' => OrderType.buy,
        'SELL' => OrderType.sell,
        _ => throw ArgumentError.value(code, 'code', 'Unknown order type'),
      };
}

/// A single executed paper-trading order.
///
/// Pure domain entity — no Firestore types. `realizedPnl` is only ever set
/// on SELL orders; BUY orders leave it null.
class Order {
  const Order({
    required this.id,
    required this.coinSymbol,
    required this.orderType,
    required this.price,
    required this.quantity,
    required this.timestamp,
    this.realizedPnl,
  });

  final String id;
  final String coinSymbol;
  final OrderType orderType;
  final double price;
  final double quantity;
  final double? realizedPnl;
  final DateTime timestamp;

  double get total => price * quantity;

  @override
  String toString() =>
      'Order($id $coinSymbol ${orderType.code} qty=$quantity @ $price '
      'pnl=$realizedPnl)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Order &&
          id == other.id &&
          coinSymbol == other.coinSymbol &&
          orderType == other.orderType &&
          price == other.price &&
          quantity == other.quantity &&
          realizedPnl == other.realizedPnl &&
          timestamp == other.timestamp;

  @override
  int get hashCode => Object.hash(
        id,
        coinSymbol,
        orderType,
        price,
        quantity,
        realizedPnl,
        timestamp,
      );
}
