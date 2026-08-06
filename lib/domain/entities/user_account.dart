/// A user's paper-trading account state at `users/{userId}`.
///
/// Pure domain entity — no Firestore types.
class UserAccount {
  const UserAccount({
    required this.uid,
    required this.virtualBalance,
    required this.consecutiveLosses,
    this.buyLockedUntil,
  });

  /// Starting balance for every new account, per the product spec.
  static const double startingBalance = 100000.0;

  /// Losing sells in a row before the revenge-blocker engages.
  static const int lossStreakLimit = 3;

  /// How long a buy lock lasts once triggered.
  static const Duration lockDuration = Duration(minutes: 30);

  final String uid;
  final double virtualBalance;
  final int consecutiveLosses;

  /// Null (or in the past) means buying is currently allowed.
  final DateTime? buyLockedUntil;

  bool isBuyLockedAt(DateTime now) =>
      buyLockedUntil != null && buyLockedUntil!.isAfter(now);

  UserAccount copyWith({
    double? virtualBalance,
    int? consecutiveLosses,
    DateTime? buyLockedUntil,
    bool clearBuyLock = false,
  }) {
    return UserAccount(
      uid: uid,
      virtualBalance: virtualBalance ?? this.virtualBalance,
      consecutiveLosses: consecutiveLosses ?? this.consecutiveLosses,
      buyLockedUntil:
          clearBuyLock ? null : (buyLockedUntil ?? this.buyLockedUntil),
    );
  }

  @override
  String toString() =>
      'UserAccount($uid balance=$virtualBalance losses=$consecutiveLosses '
      'lockedUntil=$buyLockedUntil)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserAccount &&
          uid == other.uid &&
          virtualBalance == other.virtualBalance &&
          consecutiveLosses == other.consecutiveLosses &&
          buyLockedUntil == other.buyLockedUntil;

  @override
  int get hashCode =>
      Object.hash(uid, virtualBalance, consecutiveLosses, buyLockedUntil);
}
