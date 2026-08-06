import 'package:cloud_firestore/cloud_firestore.dart' hide Order;

import '../../data/firestore/firestore_paths.dart';
import '../../data/firestore/trading_mappers.dart';
import '../entities/order.dart';
import '../entities/portfolio_position.dart';
import '../entities/user_account.dart';

/// A trade was rejected because it violates the paper-trading engine's
/// rules. Never thrown for infrastructure failures (network, permissions) —
/// those surface as the underlying [FirebaseException].
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

/// The paper-trading engine: BUY and SELL, each executed as a single atomic
/// Firestore transaction across the user's account, portfolio position, and
/// a new order record.
///
/// Also owns the "revenge-blocker" bookkeeping: a losing SELL increments
/// `consecutive_losses`; a break-even-or-better SELL resets it to zero;
/// reaching [UserAccount.lossStreakLimit] arms a
/// [UserAccount.lockDuration] cooldown on new BUYs.
class ExecuteTradeUseCase {
  ExecuteTradeUseCase(
    FirebaseFirestore firestore, {
    required String uid,
    DateTime Function()? clock,
  })  : _paths = FirestorePaths(firestore),
        _firestore = firestore,
        _uid = uid,
        _now = clock ?? DateTime.now;

  final FirebaseFirestore _firestore;
  final FirestorePaths _paths;
  final String _uid;
  final DateTime Function() _now;

  /// Buys [quantity] of [coinSymbol] at [price]. Deducts the cost from the
  /// virtual balance and folds the fill into the position's weighted-average
  /// buy price. Rejected while a revenge-trade lock is active.
  Future<Order> buy({
    required String coinSymbol,
    required double price,
    required double quantity,
  }) {
    _validatePositive(price: price, quantity: quantity);
    final symbol = coinSymbol.toUpperCase();

    return _firestore.runTransaction<Order>((transaction) async {
      final now = _now().toUtc();
      final userRef = _paths.user(_uid);
      final userSnap = await transaction.get(userRef);
      final account = UserAccountFirestoreMapping.fromDoc(userSnap);

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

      final positionRef = _paths.portfolioPosition(_uid, symbol);
      final positionSnap = await transaction.get(positionRef);
      final existing = positionSnap.exists
          ? PortfolioPositionFirestoreMapping.fromDoc(positionSnap)
          : PortfolioPosition(
              coinSymbol: symbol, totalQuantity: 0, avgBuyPrice: 0);

      final newQuantity = existing.totalQuantity + quantity;
      final newAvgPrice =
          (existing.totalQuantity * existing.avgBuyPrice + cost) /
              newQuantity;
      final updatedPosition = PortfolioPosition(
        coinSymbol: symbol,
        totalQuantity: newQuantity,
        avgBuyPrice: newAvgPrice,
      );

      final updatedAccount =
          account.copyWith(virtualBalance: account.virtualBalance - cost);

      final orderRef = _paths.newOrderRef(_uid);
      final order = Order(
        id: orderRef.id,
        coinSymbol: symbol,
        orderType: OrderType.buy,
        price: price,
        quantity: quantity,
        timestamp: now,
      );

      transaction
        ..set(positionRef, updatedPosition.toMap())
        ..update(userRef, updatedAccount.toUpdateMap())
        ..set(orderRef, order.toMap());

      return order;
    });
  }

  /// Sells [quantity] of [coinSymbol] at [price]. Requires holding at least
  /// [quantity]; realized P&L is booked against the position's average buy
  /// price and proceeds are credited to the virtual balance. Updates the
  /// revenge-blocker loss streak and, if it reaches the limit, arms a new
  /// buy lock.
  Future<Order> sell({
    required String coinSymbol,
    required double price,
    required double quantity,
  }) {
    _validatePositive(price: price, quantity: quantity);
    final symbol = coinSymbol.toUpperCase();

    return _firestore.runTransaction<Order>((transaction) async {
      final now = _now().toUtc();
      final userRef = _paths.user(_uid);
      final userSnap = await transaction.get(userRef);
      final account = UserAccountFirestoreMapping.fromDoc(userSnap);

      final positionRef = _paths.portfolioPosition(_uid, symbol);
      final positionSnap = await transaction.get(positionRef);
      final existing = positionSnap.exists
          ? PortfolioPositionFirestoreMapping.fromDoc(positionSnap)
          : PortfolioPosition(
              coinSymbol: symbol, totalQuantity: 0, avgBuyPrice: 0);

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

      final orderRef = _paths.newOrderRef(_uid);
      final order = Order(
        id: orderRef.id,
        coinSymbol: symbol,
        orderType: OrderType.sell,
        price: price,
        quantity: quantity,
        realizedPnl: realizedPnl,
        timestamp: now,
      );

      if (isFullyClosed) {
        transaction.delete(positionRef);
      } else {
        final updatedPosition = PortfolioPosition(
          coinSymbol: symbol,
          totalQuantity: remainingQuantity,
          avgBuyPrice: existing.avgBuyPrice,
        );
        transaction.set(positionRef, updatedPosition.toMap());
      }
      transaction
        ..update(userRef, updatedAccount.toUpdateMap())
        ..set(orderRef, order.toMap());

      return order;
    });
  }

  void _validatePositive({required double price, required double quantity}) {
    if (price <= 0) {
      throw const InvalidTradeException('Price must be positive');
    }
    if (quantity <= 0) {
      throw const InvalidTradeException('Quantity must be positive');
    }
  }

}
