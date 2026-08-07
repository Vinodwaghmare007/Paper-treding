import 'package:crypto_paper_trader/domain/usecases/cohort_key.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('cohortKeyFor', () {
    final now = DateTime.utc(2026, 8, 7);

    test('returns null when createdAt is unknown', () {
      expect(
        cohortKeyFor(createdAt: null, startingBalance: 100000, now: now),
        isNull,
      );
    });

    test('formats a whole-number starting balance without a trailing .0 '
        '(matching JS\'s String(100000))', () {
      final key = cohortKeyFor(
        createdAt: now.subtract(const Duration(days: 1)),
        startingBalance: 100000,
        now: now,
      );
      expect(key, '0to6days_100000');
    });

    // Mirrors functions/src/cohorts/computeCohortMedians.ts's
    // SIGNUP_BUCKETS boundaries exactly — these are the values a client/
    // server drift would most likely slip on.
    test('buckets at the 0-6 / 7-29 / 30-89 / 90+ day boundaries', () {
      const cases = {
        0: '0to6days',
        6: '0to6days',
        7: '7to29days',
        29: '7to29days',
        30: '30to89days',
        89: '30to89days',
        90: '90plusDays',
        400: '90plusDays',
      };
      for (final entry in cases.entries) {
        final key = cohortKeyFor(
          createdAt: now.subtract(Duration(days: entry.key)),
          startingBalance: 100000,
          now: now,
        );
        expect(key, '${entry.value}_100000', reason: 'daysSinceSignup=${entry.key}');
      }
    });
  });
}
