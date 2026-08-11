import 'package:crypto_paper_trader/domain/usecases/illustrative_tax_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IllustrativeTaxCalculator', () {
    test('30% tax applies only to a positive gain', () {
      final result = IllustrativeTaxCalculator.calculate(
        hypotheticalProfit: 100000,
        hypotheticalTradeValue: 500000,
      );
      expect(result.taxOnGains, closeTo(30000, 0.001));
    });

    test('a loss owes zero tax on gains, not a negative tax', () {
      final result = IllustrativeTaxCalculator.calculate(
        hypotheticalProfit: -50000,
        hypotheticalTradeValue: 500000,
      );
      expect(result.taxOnGains, 0);
    });

    test('1% TDS is withheld on trade value regardless of profit or loss', () {
      final profitCase = IllustrativeTaxCalculator.calculate(
        hypotheticalProfit: 100000,
        hypotheticalTradeValue: 200000,
      );
      final lossCase = IllustrativeTaxCalculator.calculate(
        hypotheticalProfit: -100000,
        hypotheticalTradeValue: 200000,
      );
      expect(profitCase.tds, closeTo(2000, 0.001));
      expect(lossCase.tds, closeTo(2000, 0.001));
    });

    test('totalCost and netAfterCosts sum correctly', () {
      final result = IllustrativeTaxCalculator.calculate(
        hypotheticalProfit: 100000,
        hypotheticalTradeValue: 500000,
      );
      expect(result.totalCost, closeTo(35000, 0.001)); // 30000 tax + 5000 TDS
      expect(result.netAfterCosts, closeTo(65000, 0.001));
    });

    test('zero inputs produce zero costs', () {
      final result = IllustrativeTaxCalculator.calculate(
        hypotheticalProfit: 0,
        hypotheticalTradeValue: 0,
      );
      expect(result.taxOnGains, 0);
      expect(result.tds, 0);
    });
  });
}
