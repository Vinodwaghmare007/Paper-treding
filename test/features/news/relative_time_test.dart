import 'package:crypto_paper_trader/features/news/relative_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 11, 12, 0, 0);

  group('computeRelativeTime', () {
    test('under a minute is "just now"', () {
      final result = computeRelativeTime(now.subtract(const Duration(seconds: 30)), now);
      expect(result.unit, RelativeTimeUnit.justNow);
    });

    test('exactly now is "just now"', () {
      final result = computeRelativeTime(now, now);
      expect(result.unit, RelativeTimeUnit.justNow);
    });

    test('under an hour buckets to minutes', () {
      final result = computeRelativeTime(now.subtract(const Duration(minutes: 45)), now);
      expect(result.unit, RelativeTimeUnit.minutes);
      expect(result.magnitude, 45);
    });

    test('exactly 1 minute buckets to minutes, not "just now"', () {
      final result = computeRelativeTime(now.subtract(const Duration(minutes: 1)), now);
      expect(result.unit, RelativeTimeUnit.minutes);
      expect(result.magnitude, 1);
    });

    test('under a day buckets to hours', () {
      final result = computeRelativeTime(now.subtract(const Duration(hours: 5)), now);
      expect(result.unit, RelativeTimeUnit.hours);
      expect(result.magnitude, 5);
    });

    test('exactly 1 hour buckets to hours, not minutes', () {
      final result = computeRelativeTime(now.subtract(const Duration(hours: 1)), now);
      expect(result.unit, RelativeTimeUnit.hours);
      expect(result.magnitude, 1);
    });

    test('a day or more buckets to days', () {
      final result = computeRelativeTime(now.subtract(const Duration(days: 3)), now);
      expect(result.unit, RelativeTimeUnit.days);
      expect(result.magnitude, 3);
    });

    test('exactly 24 hours buckets to days, not hours', () {
      final result = computeRelativeTime(now.subtract(const Duration(hours: 24)), now);
      expect(result.unit, RelativeTimeUnit.days);
      expect(result.magnitude, 1);
    });
  });
}
