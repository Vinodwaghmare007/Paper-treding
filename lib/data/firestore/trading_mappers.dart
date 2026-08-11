import 'package:cloud_firestore/cloud_firestore.dart' hide Order;

import '../../domain/entities/order.dart';
import '../../domain/entities/portfolio_position.dart';
import '../../domain/entities/skill_level.dart';
import '../../domain/entities/user_account.dart';

/// Converts between the pure domain entities and their Firestore document
/// shape. Kept out of `domain/` so the entities stay Firebase-free.
extension UserAccountFirestoreMapping on UserAccount {
  static UserAccount fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) {
      throw StateError('users/${doc.id} does not exist');
    }
    final lockedTs = data['buy_locked_until'];
    final createdAtTs = data['created_at'];
    final proAccessUntilTs = data['pro_access_until'];
    return UserAccount(
      uid: doc.id,
      virtualBalance: (data['virtual_balance'] as num).toDouble(),
      consecutiveLosses: (data['consecutive_losses'] as num).toInt(),
      buyLockedUntil:
          lockedTs is Timestamp ? lockedTs.toDate().toUtc() : null,
      startingBalance:
          (data['starting_balance'] as num?)?.toDouble() ?? UserAccount.defaultStartingBalance,
      createdAt: createdAtTs is Timestamp ? createdAtTs.toDate().toUtc() : null,
      skillLevel: SkillLevelCode.fromCode(
        data['skill_level'] as String? ?? 'beginner',
      ),
      puzzleStreak: (data['puzzle_streak'] as num?)?.toInt() ?? 0,
      puzzleLastPlayedDate: data['puzzle_last_played_date'] as String?,
      orgId: data['org_id'] as String?,
      referralCode: data['referral_code'] as String?,
      referredBy: data['referred_by'] as String?,
      proDaysEarned: (data['pro_days_earned'] as num?)?.toInt() ?? 0,
      proAccessUntil: proAccessUntilTs is Timestamp ? proAccessUntilTs.toDate().toUtc() : null,
    );
  }

  Map<String, dynamic> toUpdateMap() => {
        'virtual_balance': virtualBalance,
        'consecutive_losses': consecutiveLosses,
        'buy_locked_until':
            buyLockedUntil == null ? null : Timestamp.fromDate(buyLockedUntil!),
      };

  static Map<String, dynamic> initialDoc() => {
        'virtual_balance': UserAccount.defaultStartingBalance,
        'starting_balance': UserAccount.defaultStartingBalance,
        'consecutive_losses': 0,
        'buy_locked_until': null,
        'created_at': FieldValue.serverTimestamp(),
        // Growth phase fields — every one of these is only ever written
        // later by a Cloud Function (see firestore.rules' isValidAccountUpdate
        // forgery guards); the initial doc always starts them unset/zero.
        'org_id': null,
        'referral_code': null,
        'referred_by': null,
        'pro_days_earned': 0,
        'pro_access_until': null,
      };
}

extension PortfolioPositionFirestoreMapping on PortfolioPosition {
  static PortfolioPosition fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) {
      throw StateError('portfolio doc ${doc.id} does not exist');
    }
    return PortfolioPosition(
      coinSymbol: doc.id,
      totalQuantity: (data['total_quantity'] as num).toDouble(),
      avgBuyPrice: (data['avg_buy_price'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toMap() => {
        'total_quantity': totalQuantity,
        'avg_buy_price': avgBuyPrice,
      };
}

extension OrderFirestoreMapping on Order {
  static Order fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) {
      throw StateError('order doc ${doc.id} does not exist');
    }
    final ts = data['timestamp'] as Timestamp;
    return Order(
      id: doc.id,
      coinSymbol: data['coin_symbol'] as String,
      orderType: OrderTypeCode.fromCode(data['order_type'] as String),
      price: (data['price'] as num).toDouble(),
      quantity: (data['quantity'] as num).toDouble(),
      realizedPnl: (data['realized_pnl'] as num?)?.toDouble(),
      timestamp: ts.toDate().toUtc(),
    );
  }

  // Written as a client Timestamp (not FieldValue.serverTimestamp()) so the
  // value committed inside the trade transaction is known synchronously —
  // execute_trade returns this same Order to the caller without a re-read.
  Map<String, dynamic> toMap() => {
        'coin_symbol': coinSymbol,
        'order_type': orderType.code,
        'price': price,
        'quantity': quantity,
        'realized_pnl': realizedPnl,
        'timestamp': Timestamp.fromDate(timestamp),
      };
}
