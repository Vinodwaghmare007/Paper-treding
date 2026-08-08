/// One entry from `users/{uid}/public_activity` — see
/// `functions/src/traderProfile/publicActivity.ts` for the fixed set of
/// event shapes this can be. Deliberately a closed enum of factual event
/// types, never a free-text field.
sealed class ActivityEvent {
  const ActivityEvent({required this.userId, required this.displayName, required this.createdAt});

  final String userId;
  final String displayName;
  final DateTime createdAt;

  static ActivityEvent? fromMap(
    String userId,
    String displayName,
    Map<String, dynamic> map,
  ) {
    final createdAt = (map['created_at'] as dynamic).toDate() as DateTime;
    return switch (map['type']) {
      'trade' => TradeActivityEvent(
          userId: userId,
          displayName: displayName,
          createdAt: createdAt,
          coinSymbol: map['coin_symbol'] as String,
          outcome: map['outcome'] as String,
        ),
      'rationale' => RationaleActivityEvent(
          userId: userId,
          displayName: displayName,
          createdAt: createdAt,
          orderId: map['order_id'] as String,
          coinSymbol: map['coin_symbol'] as String?,
        ),
      'certification' => CertificationActivityEvent(
          userId: userId,
          displayName: displayName,
          createdAt: createdAt,
          milestoneType: map['milestone_type'] as String,
        ),
      _ => null, // forward-compatible: an unrecognized future type is skipped, not crashed on
    };
  }
}

class TradeActivityEvent extends ActivityEvent {
  const TradeActivityEvent({
    required super.userId,
    required super.displayName,
    required super.createdAt,
    required this.coinSymbol,
    required this.outcome,
  });

  final String coinSymbol;

  /// "profit" | "loss" | "breakeven" — matches publicActivity.ts exactly.
  final String outcome;
}

class RationaleActivityEvent extends ActivityEvent {
  const RationaleActivityEvent({
    required super.userId,
    required super.displayName,
    required super.createdAt,
    required this.orderId,
    required this.coinSymbol,
  });

  final String orderId;
  final String? coinSymbol;
}

class CertificationActivityEvent extends ActivityEvent {
  const CertificationActivityEvent({
    required super.userId,
    required super.displayName,
    required super.createdAt,
    required this.milestoneType,
  });

  final String milestoneType;
}
