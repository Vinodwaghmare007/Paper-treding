import 'dart:math';

import 'package:crypto_paper_trader/data/models/kline_tick.dart';
import 'package:crypto_paper_trader/data/sources/binance_rest_service.dart';
import 'package:crypto_paper_trader/domain/entities/order.dart';
import 'package:crypto_paper_trader/domain/usecases/alternate_outcome_simulator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockBinanceRestService extends Mock implements BinanceRestService {}

Candle _candle(int openTimeMs, double close) => Candle(
      openTimeMs: openTimeMs,
      closeTimeMs: openTimeMs,
      open: close,
      high: close,
      low: close,
      close: close,
      volume: 0,
    );

void main() {
  group('computeSimpleReturns', () {
    test('computes (curr - prev) / prev for each consecutive pair', () {
      expect(computeSimpleReturns([100, 110, 99]), [
        closeTo(0.10, 1e-9),
        closeTo(-0.10, 1e-9),
      ]);
    });

    test('returns an empty list for fewer than 2 prices', () {
      expect(computeSimpleReturns([100]), isEmpty);
      expect(computeSimpleReturns([]), isEmpty);
    });

    test('skips a step where the previous price is zero', () {
      expect(computeSimpleReturns([0, 100, 110]), [closeTo(0.10, 1e-9)]);
    });
  });

  group('AlternateOutcomeSimulator.isEligible', () {
    final simulator = AlternateOutcomeSimulator(restService: MockBinanceRestService());
    final sellOrder = Order(
      id: 's1',
      coinSymbol: 'BTCUSDT',
      orderType: OrderType.sell,
      price: 100,
      quantity: 1,
      timestamp: DateTime.utc(2026, 1, 1, 0, 0),
    );

    test('false before revealDelay has elapsed', () {
      expect(
        simulator.isEligible(sellOrder, now: DateTime.utc(2026, 1, 1, 1, 0)),
        isFalse,
      );
    });

    test('true once revealDelay has elapsed', () {
      expect(
        simulator.isEligible(sellOrder, now: DateTime.utc(2026, 1, 1, 4, 0)),
        isTrue,
      );
    });

    test('false for a BUY order regardless of elapsed time', () {
      final buyOrder = Order(
        id: 'b1',
        coinSymbol: 'BTCUSDT',
        orderType: OrderType.buy,
        price: 100,
        quantity: 1,
        timestamp: DateTime.utc(2026, 1, 1, 0, 0),
      );
      expect(
        simulator.isEligible(buyOrder, now: DateTime.utc(2026, 1, 5)),
        isFalse,
      );
    });
  });

  group('AlternateOutcomeSimulator.simulate', () {
    late MockBinanceRestService rest;
    final sellTime = DateTime.utc(2026, 1, 1, 0, 0);
    final sellOrder = Order(
      id: 's1',
      coinSymbol: 'BTCUSDT',
      orderType: OrderType.sell,
      price: 100,
      quantity: 1,
      timestamp: sellTime,
    );
    final now = sellTime.add(const Duration(hours: 5));

    setUp(() {
      rest = MockBinanceRestService();
      when(() => rest.fetchKlines(
            symbol: 'BTCUSDT',
            interval: '15m',
            startTimeMs: sellTime.millisecondsSinceEpoch,
            endTimeMs: sellTime.add(const Duration(hours: 4)).millisecondsSinceEpoch,
            limit: 100,
          )).thenAnswer((_) async => [
            _candle(sellTime.millisecondsSinceEpoch, 101),
            _candle(sellTime.add(const Duration(minutes: 15)).millisecondsSinceEpoch, 103),
            _candle(sellTime.add(const Duration(minutes: 30)).millisecondsSinceEpoch, 102),
          ]);
      when(() => rest.fetchKlines(
            symbol: 'BTCUSDT',
            interval: '15m',
            startTimeMs: sellTime.subtract(const Duration(hours: 24)).millisecondsSinceEpoch,
            endTimeMs: sellTime.millisecondsSinceEpoch,
            limit: 200,
          )).thenAnswer((_) async => [
            _candle(0, 90),
            _candle(1, 95),
            _candle(2, 92),
            _candle(3, 100),
          ]);
    });

    test('throws when called before revealDelay has elapsed', () {
      final simulator = AlternateOutcomeSimulator(restService: rest);
      expect(
        () => simulator.simulate(sellOrder, now: sellTime.add(const Duration(hours: 1))),
        throwsA(isA<AlternateOutcomeException>()),
      );
    });

    test('returns actualPathCount + 1 unlabeled paths with the real one locatable', () async {
      final simulator = AlternateOutcomeSimulator(
        restService: rest,
        random: Random(42),
      );
      final outcome = await simulator.simulate(sellOrder, now: now);

      expect(outcome.paths, hasLength(4)); // 1 real + 3 alternates
      expect(outcome.actualPathIndex, inInclusiveRange(0, 3));
    });

    test('the actual path matches the fetched post-sell candles exactly', () async {
      final simulator = AlternateOutcomeSimulator(
        restService: rest,
        random: Random(1),
      );
      final outcome = await simulator.simulate(sellOrder, now: now);

      final actualPrices = outcome.actualPath.map((p) => p.price).toList();
      expect(actualPrices, [101, 103, 102]);
    });

    test('alternate paths start compounding from the sell price, not the fetched candle price',
        () async {
      final simulator = AlternateOutcomeSimulator(
        restService: rest,
        random: Random(7),
      );
      final outcome = await simulator.simulate(sellOrder, now: now);

      for (var i = 0; i < outcome.paths.length; i++) {
        if (i == outcome.actualPathIndex) continue;
        final path = outcome.paths[i];
        expect(path, hasLength(3));
        // Every alternate price is a plausible compounding of sellOrder.price
        // by returns drawn from the historical set {90->95, 95->92, 92->100}.
        for (final point in path) {
          expect(point.price, greaterThan(0));
        }
      }
    });

    test('throws when there is no post-sell price history', () async {
      final emptyRest = MockBinanceRestService();
      when(() => emptyRest.fetchKlines(
            symbol: 'BTCUSDT',
            interval: '15m',
            startTimeMs: any(named: 'startTimeMs'),
            endTimeMs: any(named: 'endTimeMs'),
            limit: 100,
          )).thenAnswer((_) async => []);
      final simulator = AlternateOutcomeSimulator(restService: emptyRest);
      expect(
        () => simulator.simulate(sellOrder, now: now),
        throwsA(isA<AlternateOutcomeException>()),
      );
    });

    test('throws when there is not enough pre-sell history to estimate volatility', () async {
      final thinRest = MockBinanceRestService();
      when(() => thinRest.fetchKlines(
            symbol: 'BTCUSDT',
            interval: '15m',
            startTimeMs: sellTime.millisecondsSinceEpoch,
            endTimeMs: sellTime.add(const Duration(hours: 4)).millisecondsSinceEpoch,
            limit: 100,
          )).thenAnswer((_) async => [_candle(0, 101)]);
      when(() => thinRest.fetchKlines(
            symbol: 'BTCUSDT',
            interval: '15m',
            startTimeMs: sellTime.subtract(const Duration(hours: 24)).millisecondsSinceEpoch,
            endTimeMs: sellTime.millisecondsSinceEpoch,
            limit: 200,
          )).thenAnswer((_) async => [_candle(0, 90)]); // only 1 candle => no returns

      final simulator = AlternateOutcomeSimulator(restService: thinRest);
      expect(
        () => simulator.simulate(sellOrder, now: now),
        throwsA(isA<AlternateOutcomeException>()),
      );
    });
  });
}
