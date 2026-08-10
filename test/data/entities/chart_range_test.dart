import 'package:flutter_test/flutter_test.dart';

import 'package:crypto_paper_trader/data/entities/chart_range.dart';

void main() {
  group('ChartRange', () {
    test('has 6 ranges with unique labels', () {
      expect(ChartRange.values, hasLength(6));
      expect(ChartRange.values.map((r) => r.label).toSet(), hasLength(6));
    });

    test('every range fits in a single Binance REST call (limit <= 1000)', () {
      for (final range in ChartRange.values) {
        expect(range.candleLimit, lessThanOrEqualTo(1000),
            reason: '${range.label} requests ${range.candleLimit} candles');
      }
    });

    test('defaults to 1D as the closest match to the old fixed-range behaviour', () {
      expect(ChartRange.day1.label, '1D');
      expect(ChartRange.day1.klineInterval, '5m');
    });
  });
}
