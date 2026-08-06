import '../entities/order.dart';
import '../entities/portfolio_position.dart';
import '../entities/user_account.dart';
import 'trade_exceptions.dart';

/// Result of applying a BUY. [updatedPosition] is always present — a first
/// buy creates the position.
class BuyOutcome {
  const BuyOutcome({
    required this.updatedAccount,
    required this.updatedPosition,
    required this.order,
  });

  final UserAccount updatedAccount;
  final PortfolioPosition updatedPosition;
  final Order order;
}

/// Result of applying a SELL. [updatedPosition] is null when the sell
/// fully closes the position — the caller (Firestore transaction, or the
/// backtester's in-memory book) should remove it rather than write a
/// zero-quantity row.
class SellOutcome {
  const SellOutcome({
    required this.updatedAccount,
    required this.updatedPosition,
    required this.order,
  });

  final UserAccount updatedAccount;
  final PortfolioPosition? updatedPosition;
  final Order order;
}

/// Pure, isolate-safe trading arithmetic: weighted-average buy price,
/// realized P&L, and the revenge-blocker loss-streak/cooldown bookkeeping.
///
/// This is the single source of truth for "what does a BUY/SELL do to the
/// account and position" — both the live, Firestore-backed
/// [ExecuteTradeUseCase] and the isolate-run backtester call these same
/// functions, so a backtest result is computed by literally the same rules
/// as a live trade, not a re-implementation that can silently drift.
///
/// Deliberately has no Firebase/IO dependency: [ExecuteTradeUseCase] reads
/// state from Firestore, calls these, and writes the result back inside a
/// transaction; the backtester keeps an in-memory account/position and
/// calls these directly on a background isolate with no network access at
/// all.
class TradeMath {
  const TradeMath._();

  static void validatePositive({required double price, required double quantity}) {
    if (price <= 0) {
      throw const InvalidTradeException('Price must be positive');
    }
    if (quantity <= 0) {
      throw const InvalidTradeException('Quantity must be positive');
    }
  }

  /// Throws [TradingLockedException] if [account] is buy-locked at [now],
  /// [InsufficientBalanceException] if [price] * [quantity] exceeds the
  /// balance, or [InvalidTradeException] for non-positive inputs.
  static BuyOutcome applyBuy({
    required UserAccount account,
    required PortfolioPosition? existingPosition,
    required String coinSymbol,
    required double price,
    required double quantity,
    required DateTime now,
    required String orderId,
  }) {
    validatePositive(price: price, quantity: quantity);
    final symbol = coinSymbol.toUpperCase();

    if (account.isBuyLockedAt(now)) {
      throw TradingLockedException(account.buyLockedUntil!);
    }

    final cost = price * quantity;
    if (cost > account.virtualBalance) {
      throw InsufficientBalanceException(
        required: cost,
        available: account.virtualBalance,
      );
    }

    final existing = existingPosition ??
        PortfolioPosition(coinSymbol: symbol, totalQuantity: 0, avgBuyPrice: 0);
    final newQuantity = existing.totalQuantity + quantity;
    final newAvgPrice =
        (existing.totalQuantity * existing.avgBuyPrice + cost) / newQuantity;

    return BuyOutcome(
      updatedAccount:
          account.copyWith(virtualBalance: account.virtualBalance - cost),
      updatedPosition: PortfolioPosition(
        coinSymbol: symbol,
        totalQuantity: newQuantity,
        avgBuyPrice: newAvgPrice,
      ),
      order: Order(
        id: orderId,
        coinSymbol: symbol,
        orderType: OrderType.buy,
        price: price,
        quantity: quantity,
        timestamp: now,
      ),
    );
  }

  /// Throws [InsufficientHoldingsException] if [quantity] exceeds the held
  /// amount, or [InvalidTradeException] for non-positive inputs.
  static SellOutcome applySell({
    required UserAccount account,
    required PortfolioPosition? existingPosition,
    required String coinSymbol,
    required double price,
    required double quantity,
    required DateTime now,
    required String orderId,
  }) {
    validatePositive(price: price, quantity: quantity);
    final symbol = coinSymbol.toUpperCase();
    final existing = existingPosition ??
        PortfolioPosition(coinSymbol: symbol, totalQuantity: 0, avgBuyPrice: 0);

    if (quantity > existing.totalQuantity) {
      throw InsufficientHoldingsException(
        requested: quantity,
        held: existing.totalQuantity,
      );
    }

    final realizedPnl = (price - existing.avgBuyPrice) * quantity;
    final remainingQuantity = existing.totalQuantity - quantity;
    // Guards against float dust leaving a near-zero residual position.
    final isFullyClosed = remainingQuantity <= 1e-12;
    final proceeds = price * quantity;

    var consecutiveLosses = account.consecutiveLosses;
    DateTime? buyLockedUntil = account.buyLockedUntil;
    if (realizedPnl < 0) {
      consecutiveLosses += 1;
      if (consecutiveLosses >= UserAccount.lossStreakLimit) {
        buyLockedUntil = now.add(UserAccount.lockDuration);
      }
    } else {
      consecutiveLosses = 0;
    }

    final updatedAccount = account.copyWith(
      virtualBalance: account.virtualBalance + proceeds,
      consecutiveLosses: consecutiveLosses,
      buyLockedUntil: buyLockedUntil,
      clearBuyLock: buyLockedUntil == null,
    );

    final updatedPosition = isFullyClosed
        ? null
        : PortfolioPosition(
            coinSymbol: symbol,
            totalQuantity: remainingQuantity,
            avgBuyPrice: existing.avgBuyPrice,
          );

    final order = Order(
      id: orderId,
      coinSymbol: symbol,
      orderType: OrderType.sell,
      price: price,
      quantity: quantity,
      realizedPnl: realizedPnl,
      timestamp: now,
    );

    return SellOutcome(
      updatedAccount: updatedAccount,
      updatedPosition: updatedPosition,
      order: order,
    );
  }
}
