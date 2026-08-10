enum AlertDirection {
  above('above'),
  below('below');

  const AlertDirection(this.value);
  final String value;

  static AlertDirection fromValue(String value) =>
      AlertDirection.values.firstWhere((d) => d.value == value, orElse: () => AlertDirection.above);
}

/// `users/{uid}/alerts/{alertId}` — see functions/src/alerts/
/// checkPriceAlerts.ts for how `is_active`/`triggered_at` get flipped
/// server-side once the target price is crossed.
class PriceAlert {
  const PriceAlert({
    required this.id,
    required this.coinSymbol,
    required this.targetPrice,
    required this.direction,
    required this.isActive,
    required this.createdAt,
    required this.triggeredAt,
  });

  factory PriceAlert.fromMap(String id, Map<String, dynamic> map) {
    final createdAtRaw = map['created_at'];
    final triggeredAtRaw = map['triggered_at'];
    return PriceAlert(
      id: id,
      coinSymbol: map['coin_symbol'] as String,
      targetPrice: (map['target_price'] as num).toDouble(),
      direction: AlertDirection.fromValue(map['direction'] as String),
      isActive: map['is_active'] as bool? ?? false,
      createdAt:
          createdAtRaw == null ? DateTime.now() : (createdAtRaw as dynamic).toDate() as DateTime,
      triggeredAt:
          triggeredAtRaw == null ? null : (triggeredAtRaw as dynamic).toDate() as DateTime,
    );
  }

  final String id;
  final String coinSymbol;
  final double targetPrice;
  final AlertDirection direction;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? triggeredAt;
}
