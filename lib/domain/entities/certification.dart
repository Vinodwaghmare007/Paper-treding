/// A micro-certification earned by hitting a milestone (see
/// `functions/src/lib/milestones.ts` for the catalog and
/// `functions/src/lib/certifications.ts` for how it's awarded). Always
/// server-written — there is no client path that creates one of these.
class Certification {
  const Certification({
    required this.milestoneType,
    required this.earnedAt,
    required this.verificationCode,
  });

  /// e.g. "50_disciplined_trades", "backtester_master" — matches
  /// `functions/src/lib/milestones.ts`'s `type` values.
  final String milestoneType;
  final DateTime earnedAt;

  /// Unique, server-generated code. Publicly checkable at
  /// `{verifyBaseUrl}?code={verificationCode}` against the PII-free mirror
  /// in the `public_certifications` collection — see
  /// `certificate_screen.dart`.
  final String verificationCode;

  factory Certification.fromMap(Map<String, dynamic> map) {
    return Certification(
      milestoneType: map['milestone_type'] as String,
      earnedAt: (map['earned_at'] as dynamic).toDate() as DateTime,
      verificationCode: map['verification_code'] as String,
    );
  }
}

/// Human-readable title/description for a milestone type — purely
/// presentational, kept alongside the entity rather than duplicated across
/// every widget that displays a certification.
extension CertificationDisplay on String {
  String get milestoneTitle => switch (this) {
        '50_disciplined_trades' => '50 Disciplined Trades',
        'backtester_master' => 'Backtester Master',
        _ => this,
      };

  String get milestoneDescription => switch (this) {
        '50_disciplined_trades' =>
          'Completed 50 simulated round-trip trades on Crypto Paper Trader.',
        'backtester_master' =>
          'Ran 10 strategy backtests on Crypto Paper Trader.',
        _ => 'Milestone reached on Crypto Paper Trader.',
      };
}
