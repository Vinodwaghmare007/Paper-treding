/// Server-computed public performance profile — see
/// `functions/src/traderProfile/recomputeTraderStats.ts` for exactly how
/// each stat is derived. Nothing here is ever client-writable except
/// [displayName] and [isPublic] (via profile_settings, kept separate from
/// this data — see `TraderProfileRepository`).
class TraderProfile {
  const TraderProfile({
    required this.userId,
    required this.displayName,
    required this.isPublic,
    required this.accuracyPct,
    required this.disciplineScore,
    required this.winRatePct,
    required this.totalTrades,
    required this.followerCount,
    required this.followingCount,
    this.memberSince,
  });

  final String userId;
  final String displayName;
  final bool isPublic;

  /// % of closed (SELL) trades with realized_pnl > 0 — intentionally the
  /// same computed value as [winRatePct]; see the doc comment on
  /// `computeTraderStats` in traderStats.ts for why both fields exist.
  final double accuracyPct;

  /// 0-100. Weighted blend of revenge-lock avoidance and average holding
  /// time — see traderStats.ts's DISCIPLINE_LOCK_WEIGHT/
  /// DISCIPLINE_HOLDING_WEIGHT comment for the exact formula.
  final double disciplineScore;

  final double winRatePct;
  final int totalTrades;
  final int followerCount;
  final int followingCount;
  final DateTime? memberSince;

  factory TraderProfile.fromMap(String userId, Map<String, dynamic> map) {
    final memberSinceRaw = map['member_since'];
    return TraderProfile(
      userId: userId,
      displayName: map['display_name'] as String? ?? 'Trader',
      isPublic: map['is_public'] as bool? ?? false,
      accuracyPct: (map['accuracy_pct'] as num?)?.toDouble() ?? 0,
      disciplineScore: (map['discipline_score'] as num?)?.toDouble() ?? 0,
      winRatePct: (map['win_rate_pct'] as num?)?.toDouble() ?? 0,
      totalTrades: (map['total_trades'] as num?)?.toInt() ?? 0,
      followerCount: (map['follower_count'] as num?)?.toInt() ?? 0,
      followingCount: (map['following_count'] as num?)?.toInt() ?? 0,
      memberSince: memberSinceRaw == null ? null : (memberSinceRaw as dynamic).toDate() as DateTime,
    );
  }
}
