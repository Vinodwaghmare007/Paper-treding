import 'package:flutter_test/flutter_test.dart';

import 'package:crypto_paper_trader/data/sources/currency_converter.dart';
import 'package:crypto_paper_trader/features/settings/currency_providers.dart';

void main() {
  final sampleRate = ExchangeRate(usdToInr: 84, fetchedAt: DateTime.now(), isStale: false);

  group('convertFromUsd', () {
    test('returns the raw amount unconverted for USD', () {
      expect(convertFromUsd(100, AppCurrency.usd, null), 100);
    });

    test('converts using the given rate for INR', () {
      expect(convertFromUsd(100, AppCurrency.inr, sampleRate), 8400);
    });

    test('falls back to the raw USD amount when no rate has loaded yet', () {
      expect(convertFromUsd(100, AppCurrency.inr, null), 100);
    });
  });

  group('formatCurrency', () {
    test('formats USD with Western thousands grouping', () {
      expect(formatCurrency(1234567.891, AppCurrency.usd, null), '\$1,234,567.89');
    });

    test('formats INR with Indian lakh/crore grouping', () {
      // 1234.5 USD * 84 = 103,698 INR -> Indian grouping: 1,03,698.00
      expect(formatCurrency(1234.5, AppCurrency.inr, sampleRate), '₹1,03,698.00');
    });

    test('handles small amounts under 1000 without a stray comma', () {
      expect(formatCurrency(42.5, AppCurrency.usd, null), '\$42.50');
    });

    test("formats a negative amount with the sign before the currency symbol's digits", () {
      expect(formatCurrency(-1234.5, AppCurrency.usd, null), '\$-1,234.50');
    });
  });
}
