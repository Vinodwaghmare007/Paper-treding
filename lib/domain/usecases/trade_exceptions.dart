/// A trade was rejected because it violates the paper-trading engine's
/// rules. Never thrown for infrastructure failures (network, permissions) —
/// those surface as the underlying [FirebaseException].
///
/// Shared by the live Firestore-backed [ExecuteTradeUseCase] and the
/// isolate-run backtester ([BacktestRunner]) — both apply the exact same
/// [TradeMath] rules, so the same exception types apply to either.
sealed class TradeRejected implements Exception {
  const TradeRejected(this.message);
  final String message;

  @override
  String toString() => message;
}

class InsufficientBalanceException extends TradeRejected {
  const InsufficientBalanceException({
    required this.required,
    required this.available,
  }) : super(
          'Insufficient balance: need $required, have $available',
        );

  final double required;
  final double available;
}

class InsufficientHoldingsException extends TradeRejected {
  const InsufficientHoldingsException({
    required this.requested,
    required this.held,
  }) : super('Insufficient holdings: requested $requested, hold $held');

  final double requested;
  final double held;
}

class TradingLockedException extends TradeRejected {
  const TradingLockedException(this.lockedUntil)
      : super('Buying is locked until $lockedUntil (revenge-trade cooldown)');

  final DateTime lockedUntil;
}

class InvalidTradeException extends TradeRejected {
  const InvalidTradeException(super.message);
}
