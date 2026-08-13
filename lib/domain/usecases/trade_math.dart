import '../entities/order.dart';
import '../entities/portfolio_position.dart';
import '../entities/user_account.dart';
import 'trade_exceptions.dart';

/// Result of applying a BUY. [updatedPosition] is null when the buy fully
/// covers (closes) a short position — the caller should remove the
/// position doc rather than write a zero-quantity row, same convention as
/// [SellOutcome].
class BuyOutcome {
  const BuyOutcome({
    required this.updatedAccount,
    required this.updatedPosition,
    required this.order,
  });

  final UserAccount updatedAccount;
  final PortfolioPosition? updatedPosition;
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

/// Pure, isolate-safe trading arithmetic: weighted-average entry price,
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
///
/// ## Short-selling
///
/// [PortfolioPosition.totalQuantity] is signed: positive is a long
/// position, negative is a short. A BUY either opens/adds to a long
/// (existing quantity >= 0) or covers/reduces a short (existing quantity
/// < 0); a SELL either closes/reduces a long (existing quantity > 0) or
/// opens/adds to a short (existing quantity <= 0). Which branch runs is
/// decided entirely by the existing position's sign — there is no separate
/// "short mode" flag anywhere.
///
/// A single order is never allowed to flip a position through zero (e.g.
/// sell 5 when long 2, which would close the long *and* open a short in
/// one fill) — [InvalidTradeException] is thrown instead, asking the user
/// to close the existing side fully first. This keeps realized P&L
/// unambiguous (one order closes at most one position) and keeps the
/// money-math surface smaller to reason about and test.
///
/// Opening or adding to a short is gated by the same
/// `price * quantity <= virtualBalance` collateral check used for a long
/// buy — a deliberate simplification, not real margin/liquidation
/// mechanics. There's no forced liquidation if a short moves further
/// against the user; they simply can't grow it (or a new one) once the
/// notional would exceed their balance, and covering an expensive losing
/// short can itself fail with [InsufficientBalanceException] if the cost
/// to buy back exceeds the current balance.
///
/// The revenge-blocker's buy-lock only blocks *opening or adding to* a
/// long — never covering a short. Covering reduces risk, so gating it
/// behind the same lock that exists to stop impulsive fresh buying would
/// work against the lock's own purpose (trapping a user in a losing short
/// they can't reduce). Selling to close a long, and selling to open/add a
/// short, are likewise never blocked by the buy-lock — it has only ever
/// gated BUYs.
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

  /// Applies a realized close/cover P&L to the revenge-blocker's
  /// loss-streak state. Shared by [applySell]'s long-close path and
  /// [applyBuy]'s short-cover path so "closing a position at a loss" means
  /// the same thing to the lock regardless of which side did the closing.
  static ({int consecutiveLosses, DateTime? buyLockedUntil}) _applyRealizedPnl({
    required UserAccount account,
    required double realizedPnl,
    required DateTime now,
  }) {
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
    return (consecutiveLosses: consecutiveLosses, buyLockedUntil: buyLockedUntil);
  }

  /// Throws [InvalidTradeException] for non-positive inputs or if this buy
  /// would flip a short straight to a long in one order (cover fully
  /// first). When opening/adding to a long: throws
  /// [TradingLockedException] if [account] is buy-locked at [now], or
  /// [InsufficientBalanceException] if [price] * [quantity] exceeds the
  /// balance. When covering a short: never blocked by the buy-lock, but
  /// still throws [InsufficientBalanceException] if the cost to buy back
  /// exceeds the balance.
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
    final existing = existingPosition ??
        PortfolioPosition(coinSymbol: symbol, totalQuantity: 0, avgBuyPrice: 0);
    final cost = price * quantity;

    if (existing.totalQuantity >= 0) {
      // Opening or adding to a long.
      if (account.isBuyLockedAt(now)) {
        throw TradingLockedException(account.buyLockedUntil!);
      }
      if (cost > account.virtualBalance) {
        throw InsufficientBalanceException(
          required: cost,
          available: account.virtualBalance,
        );
      }

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

    // Covering (reducing/closing) a short. Never gated by the buy-lock —
    // this is risk-reducing, not fresh exposure.
    final shortQuantity = -existing.totalQuantity;
    if (quantity > shortQuantity) {
      throw const InvalidTradeException(
        'This would flip a short straight to a long in one order. '
        'Cover the short fully first, then buy separately.',
      );
    }
    if (cost > account.virtualBalance) {
      throw InsufficientBalanceException(
        required: cost,
        available: account.virtualBalance,
      );
    }

    final realizedPnl = (existing.avgBuyPrice - price) * quantity;
    final remainingQuantity = existing.totalQuantity + quantity;
    // Guards against float dust leaving a near-zero residual position.
    final isFullyClosed = remainingQuantity >= -1e-12;

    final lock = _applyRealizedPnl(account: account, realizedPnl: realizedPnl, now: now);
    final updatedAccount = account.copyWith(
      virtualBalance: account.virtualBalance - cost,
      consecutiveLosses: lock.consecutiveLosses,
      buyLockedUntil: lock.buyLockedUntil,
      clearBuyLock: lock.buyLockedUntil == null,
    );

    return BuyOutcome(
      updatedAccount: updatedAccount,
      updatedPosition: isFullyClosed
          ? null
          : PortfolioPosition(
              coinSymbol: symbol,
              totalQuantity: remainingQuantity,
              avgBuyPrice: existing.avgBuyPrice,
            ),
      order: Order(
        id: orderId,
        coinSymbol: symbol,
        orderType: OrderType.buy,
        price: price,
        quantity: quantity,
        realizedPnl: realizedPnl,
        timestamp: now,
      ),
    );
  }

  /// Throws [InsufficientHoldingsException] if [quantity] exceeds a held
  /// long (also the guard against flipping a long straight to a short in
  /// one order — close the long fully first), [InsufficientBalanceException]
  /// if opening/adding to a short would exceed the collateral check, or
  /// [InvalidTradeException] for non-positive inputs.
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
    final proceeds = price * quantity;

    if (existing.totalQuantity > 0) {
      // Closing or reducing a long.
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

      final lock = _applyRealizedPnl(account: account, realizedPnl: realizedPnl, now: now);
      final updatedAccount = account.copyWith(
        virtualBalance: account.virtualBalance + proceeds,
        consecutiveLosses: lock.consecutiveLosses,
        buyLockedUntil: lock.buyLockedUntil,
        clearBuyLock: lock.buyLockedUntil == null,
      );

      final updatedPosition = isFullyClosed
          ? null
          : PortfolioPosition(
              coinSymbol: symbol,
              totalQuantity: remainingQuantity,
              avgBuyPrice: existing.avgBuyPrice,
            );

      return SellOutcome(
        updatedAccount: updatedAccount,
        updatedPosition: updatedPosition,
        order: Order(
          id: orderId,
          coinSymbol: symbol,
          orderType: OrderType.sell,
          price: price,
          quantity: quantity,
          realizedPnl: realizedPnl,
          timestamp: now,
        ),
      );
    }

    // Opening or adding to a short. Same collateral check as a long buy —
    // never blocked by the buy-lock (that only gates BUYs).
    if (proceeds > account.virtualBalance) {
      throw InsufficientBalanceException(
        required: proceeds,
        available: account.virtualBalance,
      );
    }

    final existingShortQuantity = -existing.totalQuantity;
    final newShortQuantity = existingShortQuantity + quantity;
    final newAvgPrice =
        (existingShortQuantity * existing.avgBuyPrice + proceeds) / newShortQuantity;

    return SellOutcome(
      updatedAccount:
          account.copyWith(virtualBalance: account.virtualBalance + proceeds),
      updatedPosition: PortfolioPosition(
        coinSymbol: symbol,
        totalQuantity: -newShortQuantity,
        avgBuyPrice: newAvgPrice,
      ),
      order: Order(
        id: orderId,
        coinSymbol: symbol,
        orderType: OrderType.sell,
        price: price,
        quantity: quantity,
        timestamp: now,
      ),
    );
  }
}
