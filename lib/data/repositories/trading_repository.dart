import 'package:cloud_firestore/cloud_firestore.dart' hide Order;

import '../../domain/entities/order.dart';
import '../../domain/entities/portfolio_position.dart';
import '../../domain/entities/user_account.dart';
import '../../domain/usecases/execute_trade.dart';
import '../firestore/firestore_paths.dart';
import '../firestore/trading_mappers.dart';

/// Read side of the trading feature: live streams of a user's account,
/// portfolio, and order history, plus a factory for the write-side
/// [ExecuteTradeUseCase] bound to that same user.
class TradingRepository {
  TradingRepository(FirebaseFirestore firestore)
      : _firestore = firestore,
        _paths = FirestorePaths(firestore);

  final FirebaseFirestore _firestore;
  final FirestorePaths _paths;

  Stream<UserAccount> watchAccount(String uid) {
    return _paths.user(uid).snapshots().map(UserAccountFirestoreMapping.fromDoc);
  }

  Stream<List<PortfolioPosition>> watchPortfolio(String uid) {
    return _paths.portfolio(uid).snapshots().map(
          (snap) => snap.docs
              .map(PortfolioPositionFirestoreMapping.fromDoc)
              .toList(growable: false),
        );
  }

  /// Most recent orders first, capped at [limit] — generous enough that
  /// client-side windowing (e.g. "trades in the trailing 60 minutes" for
  /// the anti-gamification monitor) stays accurate without a dedicated
  /// Firestore range query per window size.
  Stream<List<Order>> watchOrders(String uid, {int limit = 200}) {
    return _paths
        .orders(uid)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(OrderFirestoreMapping.fromDoc)
              .toList(growable: false),
        );
  }

  ExecuteTradeUseCase tradeEngineFor(String uid) {
    return ExecuteTradeUseCase(_firestore, uid: uid);
  }
}
