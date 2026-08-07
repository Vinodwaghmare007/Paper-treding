/// A cohort's published median portfolio value, from
/// functions/src/cohorts/computeCohortMedians.ts. Never any individual
/// user's value — [memberCount] is included so the UI can be honest about
/// how many "similar traders" the median represents. Pure domain entity —
/// no Firestore types.
class CohortMedian {
  const CohortMedian({
    required this.cohortKey,
    required this.medianPortfolioValue,
    required this.memberCount,
    required this.updatedAt,
  });

  final String cohortKey;
  final double medianPortfolioValue;
  final int memberCount;
  final DateTime updatedAt;
}
