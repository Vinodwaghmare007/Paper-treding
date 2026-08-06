import 'package:cloud_firestore/cloud_firestore.dart' hide Order;

import '../../data/firestore/firestore_paths.dart';
import '../../data/firestore/trading_mappers.dart';
import '../entities/order.dart';
import 'trade_exceptions.dart';
import 'trade_math.dart';

export 'trade_exceptions.dart';

/// The paper-trading engine: BUY and SELL, each executed as a single atomic
/// Firestore transaction across the user's account, portfolio position, and
/// a new order record.
///
/// The actual arithmetic — weighted-average buy price, realized P&L, and
/// the revenge-blocker loss-streak/cooldown bookkeeping — lives in
/// [TradeMath], shared with the isolate-run backtester. This class only
/// owns reading prior state from Firestore and writing the result back
/// inside a transaction.
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
    // Fail fast on garbage input without ever opening a transaction, and
    // short-circuit a locked account before touching the position doc at
    // all — same two properties the pre-refactor implementation had.
    TradeMath.validatePositive(price: price, quantity: quantity);
    final symbol = coinSymbol.toUpperCase();

    return _firestore.runTransaction<Order>((transaction) async {
      final now = _now().toUtc();
      final userRef = _paths.user(_uid);
      final userSnap = await transaction.get(userRef);
      final account = UserAccountFirestoreMapping.fromDoc(userSnap);

      if (account.isBuyLockedAt(now)) {
        throw TradingLockedException(account.buyLockedUntil!);
      }

      final positionRef = _paths.portfolioPosition(_uid, symbol);
      final positionSnap = await transaction.get(positionRef);
      final existing = positionSnap.exists
          ? PortfolioPositionFirestoreMapping.fromDoc(positionSnap)
          : null;

      final orderRef = _paths.newOrderRef(_uid);
      final outcome = TradeMath.applyBuy(
        account: account,
        existingPosition: existing,
        coinSymbol: symbol,
        price: price,
        quantity: quantity,
        now: now,
        orderId: orderRef.id,
      );

      transaction
        ..set(positionRef, outcome.updatedPosition.toMap())
        ..update(userRef, outcome.updatedAccount.toUpdateMap())
        ..set(orderRef, outcome.order.toMap());

      return outcome.order;
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
    TradeMath.validatePositive(price: price, quantity: quantity);
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
          : null;

      final orderRef = _paths.newOrderRef(_uid);
      final outcome = TradeMath.applySell(
        account: account,
        existingPosition: existing,
        coinSymbol: symbol,
        price: price,
        quantity: quantity,
        now: now,
        orderId: orderRef.id,
      );

      if (outcome.updatedPosition == null) {
        transaction.delete(positionRef);
      } else {
        transaction.set(positionRef, outcome.updatedPosition!.toMap());
      }
      transaction
        ..update(userRef, outcome.updatedAccount.toUpdateMap())
        ..set(orderRef, outcome.order.toMap());

      return outcome.order;
    });
  }
}
