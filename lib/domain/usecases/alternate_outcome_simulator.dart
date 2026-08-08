import 'dart:math';

import '../../data/models/kline_tick.dart';
import '../../data/sources/binance_rest_service.dart';
import '../entities/order.dart';

class AlternateOutcomeException implements Exception {
  AlternateOutcomeException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// One point on a price path — real or synthetic.
class PricePoint {
  const PricePoint({required this.timestamp, required this.price});
  final DateTime timestamp;
  final double price;
}

/// The real post-sell path plus a handful of synthetic alternates, bundled
/// together in a fixed but unlabeled order. [actualPathIndex] is the only
/// thing that tells the caller which entry in [paths] is real — the UI is
/// expected to keep that hidden until the user asks to reveal it (see
/// RegretFreeCard), which is the entire point of the feature.
class RegretFreeOutcome {
  const RegretFreeOutcome({
    required this.sellOrder,
    required this.paths,
    required this.actualPathIndex,
    required this.disclaimer,
  });

  final Order sellOrder;
  final List<List<PricePoint>> paths;
  final int actualPathIndex;
  final String disclaimer;

  List<PricePoint> get actualPath => paths[actualPathIndex];
}

/// Simple period-over-period returns of a close-price series — the same
/// computation as `computeReturns` in `functions/src/lib/binance.ts`
/// (used there for Phase 5's Market Weather volatility read), reused here
/// rather than reintroducing it: `(close[i] - close[i-1]) / close[i-1]`.
List<double> computeSimpleReturns(List<double> closes) {
  final returns = <double>[];
  for (var i = 1; i < closes.length; i++) {
    final prev = closes[i - 1];
    final curr = closes[i];
    if (prev != 0) returns.add((curr - prev) / prev);
  }
  return returns;
}

/// "Here's what actually happened after you sold, and here's what could
/// plausibly have happened instead" — a comfort feature, not a forecast.
///
/// The real path can't exist until the hours after the sell have actually
/// elapsed, so [isEligible] gates on [revealDelay] having passed since
/// [Order.timestamp]; there is no way to show this immediately after a
/// live sell. The alternates are synthetic price paths built by bootstrap
/// resampling — repeatedly drawing (with replacement) from the sell
/// symbol's own recent historical returns and compounding them forward
/// from the sell price. This is deliberately the same statistical
/// ingredient Phase 3's ARIMA forecast is built on (period-over-period
/// returns / volatility of the price series, see `computeSimpleReturns`
/// above and its `binance.ts` counterpart) rather than a new model:
/// ARIMA fits a parametric model to that same return series and derives
/// confidence bands from it, whereas this resamples the empirical
/// distribution directly — non-parametric, but drawing on the identical
/// underlying signal rather than inventing a second one.
class AlternateOutcomeSimulator {
  AlternateOutcomeSimulator({
    required BinanceRestService restService,
    Random? random,
    this.revealDelay = const Duration(hours: 4),
    this.lookback = const Duration(hours: 24),
    this.alternatePathCount = 3,
    this.pathInterval = '15m',
  })  : _rest = restService,
        _random = random ?? Random();

  final BinanceRestService _rest;
  final Random _random;

  /// How long after a SELL the real outcome becomes available to show.
  final Duration revealDelay;

  /// Historical window (ending at the sell) used to estimate volatility
  /// for the synthetic alternates. Always available immediately, since it
  /// only looks backward from the sell.
  final Duration lookback;

  final int alternatePathCount;

  /// Kline interval for both the real path and the synthetic ones — 15m
  /// over a 4h [revealDelay] gives a readable ~16-point curve without a
  /// huge fetch.
  final String pathInterval;

  /// True once [sellOrder]'s real outcome exists to fetch (i.e.
  /// [revealDelay] has actually elapsed) and there's anything to show.
  bool isEligible(Order sellOrder, {DateTime? now}) {
    if (sellOrder.orderType != OrderType.sell) return false;
    final reference = now ?? DateTime.now();
    return reference.difference(sellOrder.timestamp) >= revealDelay;
  }

  Future<RegretFreeOutcome> simulate(Order sellOrder, {DateTime? now}) async {
    if (!isEligible(sellOrder, now: now)) {
      throw AlternateOutcomeException(
        'Real outcome for this sell is not available yet — '
        'reveal happens $revealDelay after the sell.',
      );
    }

    final sellTime = sellOrder.timestamp;
    final actualCandles = await _rest.fetchKlines(
      symbol: sellOrder.coinSymbol,
      interval: pathInterval,
      startTimeMs: sellTime.millisecondsSinceEpoch,
      endTimeMs: sellTime.add(revealDelay).millisecondsSinceEpoch,
      limit: 100,
    );
    if (actualCandles.isEmpty) {
      throw AlternateOutcomeException(
        'No post-sell price history for ${sellOrder.coinSymbol}.',
      );
    }

    final lookbackCandles = await _rest.fetchKlines(
      symbol: sellOrder.coinSymbol,
      interval: pathInterval,
      startTimeMs: sellTime.subtract(lookback).millisecondsSinceEpoch,
      endTimeMs: sellTime.millisecondsSinceEpoch,
      limit: 200,
    );
    final returns = computeSimpleReturns(
      lookbackCandles.map((c) => c.close).toList(growable: false),
    );
    if (returns.isEmpty) {
      throw AlternateOutcomeException(
        'Not enough pre-sell history for ${sellOrder.coinSymbol} '
        'to estimate volatility.',
      );
    }

    final actualPath = _toPricePoints(actualCandles);
    final stepCount = actualPath.length;

    final alternatePaths = List.generate(
      alternatePathCount,
      (_) => _bootstrapPath(
        startPrice: sellOrder.price,
        startTime: sellTime,
        stepCount: stepCount,
        stepDuration: revealDelay ~/ stepCount,
        returns: returns,
      ),
    );

    final allPaths = [actualPath, ...alternatePaths]..shuffle(_random);
    final actualPathIndex = allPaths.indexOf(actualPath);

    return RegretFreeOutcome(
      sellOrder: sellOrder,
      paths: allPaths,
      actualPathIndex: actualPathIndex,
      disclaimer:
          'Price could have gone several ways from here — one of these '
          'paths is what actually happened, the rest are simulated '
          "possibilities built from this coin's own recent volatility. "
          "Not a prediction of what would have happened if you'd held.",
    );
  }

  List<PricePoint> _toPricePoints(List<Candle> candles) => [
        for (final candle in candles)
          PricePoint(
            timestamp: DateTime.fromMillisecondsSinceEpoch(
              candle.openTimeMs,
              isUtc: true,
            ),
            price: candle.close,
          ),
      ];

  List<PricePoint> _bootstrapPath({
    required double startPrice,
    required DateTime startTime,
    required int stepCount,
    required Duration stepDuration,
    required List<double> returns,
  }) {
    final path = <PricePoint>[];
    var price = startPrice;
    for (var i = 1; i <= stepCount; i++) {
      final sampledReturn = returns[_random.nextInt(returns.length)];
      price = price * (1 + sampledReturn);
      path.add(PricePoint(
        timestamp: startTime.add(stepDuration * i),
        price: price,
      ));
    }
    return path;
  }
}
