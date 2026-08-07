import 'dart:math';

import '../../data/entities/curated_period.dart';
import '../../data/sources/binance_rest_service.dart';

class WhatIfGenerationException implements Exception {
  WhatIfGenerationException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// "If you'd put $[hypotheticalAmount] into [symbol] on [historicalDate],
/// it would be worth $[currentValue] today." Purely illustrative — no real
/// money, no trade recorded, nothing written to the user's account.
class WhatIfResult {
  const WhatIfResult({
    required this.symbol,
    required this.historicalDate,
    required this.historicalPrice,
    required this.currentPrice,
    required this.hypotheticalAmount,
  });

  final String symbol;
  final DateTime historicalDate;
  final double historicalPrice;
  final double currentPrice;
  final double hypotheticalAmount;

  double get currentValue => hypotheticalAmount * (currentPrice / historicalPrice);
  double get profitLoss => currentValue - hypotheticalAmount;
  double get growthMultiple => currentPrice / historicalPrice;
}

/// Picks a random historical date+symbol and computes what a fixed
/// hypothetical amount invested then would be worth today.
///
/// "Random historical date" draws from [curatedPeriods] (Phase 4's
/// hand-picked Market Replay windows) rather than an arbitrary point across
/// Binance's full history — every period in that list is already a known-
/// good, story-worthy window ("the FTX crash week"), which makes for a
/// more interesting share card than a uniformly random day that might land
/// on nothing notable. The currency symbol used for [WhatIfResult] display
/// is left to the caller; this class only computes numbers.
class WhatIfGeneratorUseCase {
  WhatIfGeneratorUseCase({
    required BinanceRestService restService,
    Random? random,
  })  : _rest = restService,
        _random = random ?? Random();

  final BinanceRestService _rest;
  final Random _random;

  Future<WhatIfResult> generate({
    double hypotheticalAmount = 1000,
    List<CuratedPeriod>? periodPool,
  }) async {
    final pool = periodPool ?? curatedPeriods;
    if (pool.isEmpty) {
      throw WhatIfGenerationException('No historical periods available.');
    }
    final period = pool[_random.nextInt(pool.length)];

    final rangeDays = period.end.difference(period.start).inDays;
    final offsetDays = rangeDays > 0 ? _random.nextInt(rangeDays) : 0;
    final historicalDate = period.start.add(Duration(days: offsetDays));

    final historicalCandles = await _rest.fetchKlines(
      symbol: period.symbol,
      interval: '1d',
      startTimeMs: historicalDate.millisecondsSinceEpoch,
      limit: 1,
    );
    if (historicalCandles.isEmpty) {
      throw WhatIfGenerationException(
        'No historical price data for ${period.symbol} on $historicalDate.',
      );
    }

    final currentCandles = await _rest.fetchKlines(
      symbol: period.symbol,
      interval: '1m',
      limit: 1,
    );
    if (currentCandles.isEmpty) {
      throw WhatIfGenerationException('No current price data for ${period.symbol}.');
    }

    return WhatIfResult(
      symbol: period.symbol,
      historicalDate: historicalDate,
      historicalPrice: historicalCandles.first.close,
      currentPrice: currentCandles.last.close,
      hypotheticalAmount: hypotheticalAmount,
    );
  }
}
