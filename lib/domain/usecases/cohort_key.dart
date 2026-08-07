/// Mirrors functions/src/cohorts/computeCohortMedians.ts's bucketing
/// exactly — this has to compute the *same* cohort key the server used to
/// publish `public_cohort_medians/{cohortKey}`, or the Portfolio Twin card
/// would silently read the wrong (or a nonexistent) cohort.
const _signupBucketsByMaxDays = <(int maxDays, String label)>[
  (7, '0to6days'),
  (30, '7to29days'),
  (90, '30to89days'),
];
const _finalSignupBucketLabel = '90plusDays';

String _signupBucket(int daysSinceSignup) {
  for (final (maxDays, label) in _signupBucketsByMaxDays) {
    if (daysSinceSignup < maxDays) return label;
  }
  return _finalSignupBucketLabel;
}

/// JS's `String(startingBalance)` drops the trailing `.0` for whole
/// numbers (`String(100000)` -> `"100000"`), which Dart's `double.toString`
/// does not (`100000.0.toString()` -> `"100000.0"`). Every account has the
/// same whole-number starting balance today, so this covers the case that
/// actually occurs; a future non-whole starting balance would need a more
/// careful match against JS's `Number.prototype.toString` to stay in sync.
String _startingBalanceTier(double startingBalance) {
  return startingBalance.truncateToDouble() == startingBalance
      ? startingBalance.toInt().toString()
      : startingBalance.toString();
}

/// The `public_cohort_medians/{cohortKey}` doc id this account's cohort is
/// published under, or null if [createdAt] is unknown (matches the server,
/// which skips accounts with no signup timestamp entirely).
String? cohortKeyFor({
  required DateTime? createdAt,
  required double startingBalance,
  DateTime? now,
}) {
  if (createdAt == null) return null;
  final daysSinceSignup = (now ?? DateTime.now().toUtc()).difference(createdAt).inDays;
  return '${_signupBucket(daysSinceSignup)}_${_startingBalanceTier(startingBalance)}';
}
