import 'skill_level.dart';

/// A user's paper-trading account state at `users/{userId}`.
///
/// Pure domain entity — no Firestore types.
class UserAccount {
  const UserAccount({
    required this.uid,
    required this.virtualBalance,
    required this.consecutiveLosses,
    this.startingBalance = defaultStartingBalance,
    this.createdAt,
    this.buyLockedUntil,
    this.skillLevel = SkillLevel.beginner,
  });

  /// Starting balance given to every new account today, per the product
  /// spec. [startingBalance] below is each account's own immutable
  /// snapshot of this at creation time — distinct constants because if
  /// starting balances ever become configurable per-user, the default
  /// changes independently of any given account's actual value.
  static const double defaultStartingBalance = 100000.0;

  /// Losing sells in a row before the revenge-blocker engages.
  static const int lossStreakLimit = 3;

  /// How long a buy lock lasts once triggered.
  static const Duration lockDuration = Duration(minutes: 30);

  final String uid;
  final double virtualBalance;
  final int consecutiveLosses;

  /// Snapshot of the balance this account started with — never changes
  /// after creation. Powers the Portfolio Twin cohort bucketing
  /// (days-since-signup x starting-balance tier).
  final double startingBalance;

  /// When this account was created — powers the "days since signup"
  /// cohort dimension. Null for accounts that predate this field, or for
  /// synthetic accounts (e.g. the backtester's in-memory simulation) where
  /// "signup date" isn't a meaningful concept; the cohort Cloud Function
  /// skips users with no value here rather than guessing.
  final DateTime? createdAt;

  /// Null (or in the past) means buying is currently allowed.
  final DateTime? buyLockedUntil;

  /// Server-computed by functions/src/chat/updateSkillLevelOnOrder.ts from
  /// completed-trade count; never written by the client. Defaults to
  /// [SkillLevel.beginner], matching the same default the Firestore rules'
  /// callerSkillLevel() falls back to for accounts with no completed
  /// trades yet.
  final SkillLevel skillLevel;

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
      startingBalance: startingBalance,
      createdAt: createdAt,
      buyLockedUntil:
          clearBuyLock ? null : (buyLockedUntil ?? this.buyLockedUntil),
      skillLevel: skillLevel,
    );
  }

  @override
  String toString() =>
      'UserAccount($uid balance=$virtualBalance losses=$consecutiveLosses '
      'lockedUntil=$buyLockedUntil startingBalance=$startingBalance '
      'createdAt=$createdAt skillLevel=$skillLevel)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserAccount &&
          uid == other.uid &&
          virtualBalance == other.virtualBalance &&
          consecutiveLosses == other.consecutiveLosses &&
          buyLockedUntil == other.buyLockedUntil &&
          startingBalance == other.startingBalance &&
          createdAt == other.createdAt &&
          skillLevel == other.skillLevel;

  @override
  int get hashCode => Object.hash(
        uid,
        virtualBalance,
        consecutiveLosses,
        buyLockedUntil,
        startingBalance,
        createdAt,
        skillLevel,
      );
}
