/// One row of `public_leaderboard/{weekly|all_time}` — see
/// `functions/src/traderProfile/computeLeaderboard.ts` for the blended
/// ranking formula.
class LeaderboardEntry {
  const LeaderboardEntry({
    required this.userId,
    required this.displayName,
    required this.disciplineScore,
    required this.winRatePct,
    required this.blendedScore,
  });

  final String userId;
  final String displayName;
  final double disciplineScore;
  final double winRatePct;
  final double blendedScore;

  factory LeaderboardEntry.fromMap(Map<String, dynamic> map) {
    return LeaderboardEntry(
      userId: map['user_id'] as String,
      displayName: map['display_name'] as String? ?? 'Trader',
      disciplineScore: (map['discipline_score'] as num?)?.toDouble() ?? 0,
      winRatePct: (map['win_rate_pct'] as num?)?.toDouble() ?? 0,
      blendedScore: (map['blended_score'] as num?)?.toDouble() ?? 0,
    );
  }
}

enum LeaderboardWindow { weekly, allTime }

extension LeaderboardWindowPath on LeaderboardWindow {
  String get docId => switch (this) {
        LeaderboardWindow.weekly => 'weekly',
        LeaderboardWindow.allTime => 'all_time',
      };

  String get label => switch (this) {
        LeaderboardWindow.weekly => 'Weekly',
        LeaderboardWindow.allTime => 'All-Time',
      };
}
