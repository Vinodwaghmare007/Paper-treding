import 'package:crypto_paper_trader/data/entities/curated_period.dart';
import 'package:crypto_paper_trader/data/models/kline_tick.dart';
import 'package:crypto_paper_trader/domain/usecases/market_replay_engine.dart';
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

final _testPeriod = CuratedPeriod(
  id: 'test',
  name: 'Test Period',
  description: 'test',
  symbol: 'BTCUSDT',
  interval: '1m',
  start: DateTime.utc(2024, 1, 1),
  end: DateTime.utc(2024, 1, 2),
);

void main() {
  const tickInterval = Duration(milliseconds: 20);

  List<Candle> makeCandles(int count) =>
      [for (var i = 0; i < count; i++) _candle(i, 100 + i.toDouble())];

  test('starts paused, seeded up to initialSeedCount, not yet emitting ticks', () {
    final engine = MarketReplayEngine(
      period: _testPeriod,
      candles: makeCandles(20),
      initialSeedCount: 5,
      baseTickInterval: tickInterval,
    );
    addTearDown(engine.dispose);

    expect(engine.isPlaying, isFalse);
    expect(engine.currentCandleIndex, 4); // initialSeedCount - 1
    expect(engine.seedCandles.length, 5);
    expect(engine.currentCandle!.close, 104); // index 4 -> close 100+4
  });

  test('play advances currentCandleIndex over time and emits ticks', () async {
    final engine = MarketReplayEngine(
      period: _testPeriod,
      candles: makeCandles(10),
      initialSeedCount: 1,
      baseTickInterval: tickInterval,
    );
    addTearDown(engine.dispose);

    final emitted = <KlineTick>[];
    final sub = engine.ticks.listen(emitted.add);
    addTearDown(sub.cancel);

    engine.play();
    expect(engine.isPlaying, isTrue);

    await Future<void>.delayed(tickInterval * 3.5);
    engine.pause();

    expect(engine.isPlaying, isFalse);
    expect(engine.currentCandleIndex, greaterThan(0));
    expect(emitted, isNotEmpty);
    expect(emitted.every((t) => t.isCandleClosed), isTrue);
    expect(emitted.every((t) => t.symbol == 'BTCUSDT'), isTrue);
  });

  test('a higher speed advances more candles in the same wall-clock time', () async {
    final slow = MarketReplayEngine(
      period: _testPeriod,
      candles: makeCandles(200),
      initialSeedCount: 1,
      baseTickInterval: tickInterval,
    );
    final fast = MarketReplayEngine(
      period: _testPeriod,
      candles: makeCandles(200),
      initialSeedCount: 1,
      baseTickInterval: tickInterval,
    )..setSpeed(ReplaySpeed.x20);
    addTearDown(slow.dispose);
    addTearDown(fast.dispose);

    slow.play();
    fast.play();
    await Future<void>.delayed(tickInterval * 5);
    slow.pause();
    fast.pause();

    expect(fast.currentCandleIndex, greaterThan(slow.currentCandleIndex));
  });

  test('reaching the last candle auto-pauses', () async {
    final engine = MarketReplayEngine(
      period: _testPeriod,
      candles: makeCandles(3),
      initialSeedCount: 1,
      baseTickInterval: tickInterval,
    );
    addTearDown(engine.dispose);

    engine.play();
    await Future<void>.delayed(tickInterval * 10);

    expect(engine.isPlaying, isFalse);
    expect(engine.currentCandleIndex, 2); // last index
  });

  test('play is a no-op once already at the last candle', () {
    final engine = MarketReplayEngine(
      period: _testPeriod,
      candles: makeCandles(3),
      initialSeedCount: 3,
      baseTickInterval: tickInterval,
    );
    addTearDown(engine.dispose);

    expect(engine.currentCandleIndex, 2);
    engine.play();
    expect(engine.isPlaying, isFalse);
  });
}
