import 'package:crypto_paper_trader/data/entities/curated_period.dart';
import 'package:crypto_paper_trader/data/models/kline_tick.dart';
import 'package:crypto_paper_trader/data/sources/binance_rest_service.dart';
import 'package:crypto_paper_trader/domain/usecases/whatif_generator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockBinanceRestService extends Mock implements BinanceRestService {}

Candle _candle(double close) => Candle(
      openTimeMs: 0,
      closeTimeMs: 0,
      open: close,
      high: close,
      low: close,
      close: close,
      volume: 0,
    );

void main() {
  group('WhatIfGeneratorUseCase.generate', () {
    // A single-day period makes the "random" historical date deterministic
    // (rangeDays == 0), and a single-entry pool makes the period choice
    // deterministic too — this test isn't exercising the randomness, just
    // the price-lookup and valuation math.
    final period = CuratedPeriod(
      id: 'test_period',
      name: 'Test Period',
      description: 'test',
      symbol: 'BTCUSDT',
      interval: '1d',
      start: DateTime.utc(2021, 1, 1),
      end: DateTime.utc(2021, 1, 2),
    );

    late MockBinanceRestService rest;

    setUp(() {
      rest = MockBinanceRestService();
    });

    test('computes current value as amount scaled by price growth', () async {
      when(() => rest.fetchKlines(
            symbol: 'BTCUSDT',
            interval: '1d',
            startTimeMs: any(named: 'startTimeMs'),
            limit: 1,
          )).thenAnswer((_) async => [_candle(100)]);
      when(() => rest.fetchKlines(symbol: 'BTCUSDT', interval: '1m', limit: 1))
          .thenAnswer((_) async => [_candle(250)]);

      final useCase = WhatIfGeneratorUseCase(restService: rest);
      final result = await useCase.generate(
        hypotheticalAmount: 1000,
        periodPool: [period],
      );

      expect(result.symbol, 'BTCUSDT');
      expect(result.historicalPrice, 100);
      expect(result.currentPrice, 250);
      expect(result.currentValue, 2500);
      expect(result.profitLoss, 1500);
      expect(result.growthMultiple, 2.5);
    });

    test('throws WhatIfGenerationException when no historical candle is found', () async {
      when(() => rest.fetchKlines(
            symbol: 'BTCUSDT',
            interval: '1d',
            startTimeMs: any(named: 'startTimeMs'),
            limit: 1,
          )).thenAnswer((_) async => []);

      final useCase = WhatIfGeneratorUseCase(restService: rest);
      expect(
        () => useCase.generate(periodPool: [period]),
        throwsA(isA<WhatIfGenerationException>()),
      );
    });

    test('throws WhatIfGenerationException for an empty period pool', () async {
      final useCase = WhatIfGeneratorUseCase(restService: rest);
      expect(
        () => useCase.generate(periodPool: const []),
        throwsA(isA<WhatIfGenerationException>()),
      );
    });
  });
}
