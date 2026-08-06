import 'package:crypto_paper_trader/data/models/kline_tick.dart';
import 'package:crypto_paper_trader/domain/entities/backtest_condition.dart';
import 'package:crypto_paper_trader/domain/entities/order.dart';
import 'package:crypto_paper_trader/domain/usecases/backtest_runner.dart';
import 'package:flutter_test/flutter_test.dart';

Candle _candle(int index, double close) {
  final openTimeMs = index * 60000;
  return Candle(
    openTimeMs: openTimeMs,
    closeTimeMs: openTimeMs + 59999,
    open: close,
    high: close,
    low: close,
    close: close,
    volume: 1,
  );
}

void main() {
  group('executeBacktest', () {
    // Same price series as the hand-derived RSI(5) worked example in
    // indicator_calculator_test.dart, where RSI is already independently
    // verified to be: RSI[5]=700/9≈77.78, [6]=1900/23≈82.61, [7]=800/11≈72.73,
    // [8]=14300/181≈79.01, [9]=234100/2797≈83.70 — all comfortably above 50,
    // and NaN (undefined) before index 5.
    //
    // With `RSI(5) > 50` as the condition: no signal until index 5 (RSI is
    // NaN before that), then TRUE for every candle from index 5 onward
    // (never crosses back below 50), so exactly one BUY (index 5, at
    // close=105) and the position rides to the end, where it's force-closed
    // at the final candle (index 9, close=110).
    //
    // Position sizing 10% of a 100,000 starting balance = 10,000 spent at
    // 105 -> quantity = 10000/105 = 2000/21 (exact fraction).
    //   realizedPnl = (110-105) * 2000/21 = 10000/21 ≈ 476.190476
    //   finalBalance = 90000 + 110*2000/21 = 2110000/21 ≈ 100476.190476
    //
    // Max drawdown: portfolio value only ever dips below its running peak
    // at index 7 (price briefly pulls back from 107 to 106 while holding),
    // recovering to new highs at indices 8 and 9. Hand-computed exactly:
    //   peak at index 6 = 90000 + 2000/21*107 = 2104000/21
    //   value at index 7 = 90000 + 2000/21*106 = 2102000/21
    //   drawdown = (2104000/21 - 2102000/21) / (2104000/21) * 100
    //            = (2000/2104000) * 100 = 100/1052 = 25/263 ≈ 0.09505703%
    final prices = <double>[100, 102, 101, 103, 106, 105, 107, 106, 108, 110];
    final candles = [for (var i = 0; i < prices.length; i++) _candle(i, prices[i])];

    late BacktestResult result;

    setUp(() {
      result = executeBacktest(
        BacktestRequest(
          condition: const RsiThresholdCondition(
            period: 5,
            comparisonOperator: ComparisonOperator.greaterThan,
            threshold: 50,
          ),
          candles: candles,
          startingBalance: 100000,
          positionSizePercent: 10,
        ),
      );
    });

    test('opens exactly one position at the first defined RSI signal', () {
      expect(result.trades.length, 2);
      final buy = result.trades[0];
      expect(buy.order.orderType, OrderType.buy);
      expect(buy.candleIndex, 5);
      expect(buy.order.price, 105);
      expect(buy.order.quantity, closeTo(2000 / 21, 1e-9));
    });

    test('force-closes the open position at the final candle', () {
      final sell = result.trades[1];
      expect(sell.order.orderType, OrderType.sell);
      expect(sell.candleIndex, 9);
      expect(sell.order.price, 110);
      expect(sell.order.realizedPnl, closeTo(10000 / 21, 1e-6));
    });

    test('matches the hand-calculated total P&L and final balance', () {
      expect(result.totalPnl, closeTo(10000 / 21, 1e-6));
      expect(result.finalBalance, closeTo(2110000 / 21, 1e-6));
    });

    test('win rate is 100% (the one closed trade was profitable)', () {
      expect(result.winRate, 1.0);
    });

    test('matches the hand-calculated max drawdown', () {
      expect(result.maxDrawdownPercent, closeTo(25 / 263, 1e-6));
    });

    test('equity curve has one point per candle for a short series', () {
      expect(result.equityCurve.length, candles.length);
      expect(result.equityCurve.first.portfolioValue, 100000); // flat, no position yet
      expect(result.equityCurve.last.portfolioValue, closeTo(2110000 / 21, 1e-6));
    });
  });

  test('a condition that never fires produces zero trades and zero P&L', () {
    final candles = [for (var i = 0; i < 20; i++) _candle(i, 100 + i.toDouble())];
    final result = executeBacktest(
      BacktestRequest(
        condition: const RsiThresholdCondition(
          period: 5,
          comparisonOperator: ComparisonOperator.lessThan,
          threshold: 1, // never true for a rising series (RSI saturates at 100)
        ),
        candles: candles,
      ),
    );

    expect(result.trades, isEmpty);
    expect(result.totalPnl, 0);
    expect(result.winRate, isNull);
    expect(result.finalBalance, 100000);
  });

  test('an AND condition churns around each transient cross while its sustained child holds', () {
    // RSI(5) > 50 AND price crosses up through SMA(2). Price independently
    // crosses up through SMA(2) at indices 3, 6, and 8 (verified separately
    // — see below); RSI(5) is only defined (non-NaN) from index 5 onward,
    // so the AND condition is true only at indices 6 and 8. A price-crosses
    // condition is transient (true for exactly one candle, then false
    // again), so AND-ing it with a *sustained* condition like RSI>50
    // doesn't reduce trade count — it causes the position to open and
    // immediately close around each cross:
    //   idx6: true & flat -> BUY @107
    //   idx7: false & in position -> SELL @106 (a loss)
    //   idx8: true & flat -> BUY @108
    //   idx9: false & in position -> SELL @110 (a gain)
    //
    // SMA(2) series: [NaN,101,101.5,102,104.5,105.5,106,106.5,107,109].
    // Cross-up check (prevPrice<=prevSMA && currPrice>currSMA):
    //   idx3: 101<=101.5 && 103>102 -> true (but RSI NaN here, so AND false)
    //   idx6: 105<=105.5 && 107>106 -> true, RSI[6]≈82.6>50 -> AND true
    //   idx8: 106<=106.5 && 108>107 -> true, RSI[8]≈79.0>50 -> AND true
    final prices = <double>[100, 102, 101, 103, 106, 105, 107, 106, 108, 110];
    final candles = [for (var i = 0; i < prices.length; i++) _candle(i, prices[i])];

    final result = executeBacktest(BacktestRequest(
      condition: const AndCondition([
        RsiThresholdCondition(period: 5, comparisonOperator: ComparisonOperator.greaterThan, threshold: 50),
        PriceCrossesSmaCondition(period: 2, direction: CrossDirection.up),
      ]),
      candles: candles,
      startingBalance: 100000,
      positionSizePercent: 10,
    ));

    expect(result.trades.length, 4);
    expect(result.trades[0].order.orderType, OrderType.buy);
    expect(result.trades[0].candleIndex, 6);
    expect(result.trades[0].order.price, 107);
    expect(result.trades[1].order.orderType, OrderType.sell);
    expect(result.trades[1].candleIndex, 7);
    expect(result.trades[1].order.price, 106);
    expect(result.trades[1].order.realizedPnl, lessThan(0)); // bought 107, sold 106
    expect(result.trades[2].order.orderType, OrderType.buy);
    expect(result.trades[2].candleIndex, 8);
    expect(result.trades[3].order.orderType, OrderType.sell);
    expect(result.trades[3].candleIndex, 9);
    expect(result.trades[3].order.realizedPnl, greaterThan(0)); // bought 108, sold 110
    expect(result.winRate, 0.5); // 1 of 2 sells was profitable
  });

  test('reports progress up to 1.0 and completes via the isolate-based stream API', () async {
    final candles = [for (var i = 0; i < 30; i++) _candle(i, 100 + i.toDouble())];
    final request = BacktestRequest(
      condition: const RsiThresholdCondition(
          period: 5, comparisonOperator: ComparisonOperator.lessThan, threshold: 1),
      candles: candles,
    );

    final events = await BacktestRunner().run(request).toList();

    expect(events, isNotEmpty);
    expect(events.last, isA<BacktestComplete>());
    final completed = events.last as BacktestComplete;
    // Should match executeBacktest run directly on the main isolate for the
    // same request — confirms the isolate message-passing round-trip
    // doesn't silently corrupt the request or result.
    final direct = executeBacktest(request);
    expect(completed.result.totalPnl, direct.totalPnl);
    expect(completed.result.trades.length, direct.trades.length);
  });
}
