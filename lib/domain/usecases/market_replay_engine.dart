import 'dart:async';

import '../../data/entities/curated_period.dart';
import '../../data/models/kline_tick.dart';

enum ReplaySpeed { x1, x5, x20 }

extension ReplaySpeedMultiplier on ReplaySpeed {
  int get multiplier => switch (this) {
        ReplaySpeed.x1 => 1,
        ReplaySpeed.x5 => 5,
        ReplaySpeed.x20 => 20,
      };

  String get label => switch (this) {
        ReplaySpeed.x1 => '1x',
        ReplaySpeed.x5 => '5x',
        ReplaySpeed.x20 => '20x',
      };
}

class ReplayState {
  const ReplayState({
    required this.currentCandleIndex,
    required this.totalCandles,
    required this.isPlaying,
    required this.speed,
    required this.currentCandle,
  });

  final int currentCandleIndex;
  final int totalCandles;
  final bool isPlaying;
  final ReplaySpeed speed;
  final Candle? currentCandle;

  bool get isFinished => totalCandles > 0 && currentCandleIndex >= totalCandles - 1;
  double get progressFraction =>
      totalCandles <= 1 ? 0 : currentCandleIndex / (totalCandles - 1);
}

/// A controllable "virtual clock" over a cached historical period: play,
/// pause, adjustable speed, and a [currentCandleIndex] that advances one
/// candle at a time.
///
/// Emits a [Stream<KlineTick>] in exactly the shape live data uses — same
/// [KlineTick] type, `isCandleClosed: true` for every emission since replay
/// only ever deals in already-closed historical candles — so
/// [TradingChartView] and, via [ReplayPriceSource], the trade sheet don't
/// need to know they're looking at history instead of the live feed.
class MarketReplayEngine {
  MarketReplayEngine({
    required this.period,
    required List<Candle> candles,
    int initialSeedCount = 50,
    Duration baseTickInterval = _defaultBaseTickInterval,
  })  : _candles = candles,
        _baseTickInterval = baseTickInterval,
        _index = (initialSeedCount - 1).clamp(0, (candles.length - 1).clamp(0, candles.length));

  final CuratedPeriod period;
  final List<Candle> _candles;

  final _tickController = StreamController<KlineTick>.broadcast();
  final _stateController = StreamController<ReplayState>.broadcast();

  int _index;
  bool _playing = false;
  ReplaySpeed _speed = ReplaySpeed.x1;
  Timer? _timer;
  bool _disposed = false;

  /// One real second per candle at 1x — fast enough to skim months of
  /// hourly/daily candles without feeling like a slideshow, slow enough at
  /// 1x to actually watch individual candles form. Injectable so tests
  /// don't have to wait out real 1-second ticks.
  static const _defaultBaseTickInterval = Duration(milliseconds: 1000);
  final Duration _baseTickInterval;

  /// The candles the chart should seed with before replay starts emitting
  /// new ones — everything up to and including the current starting index.
  List<Candle> get seedCandles => _candles.sublist(0, (_index + 1).clamp(0, _candles.length));

  Stream<KlineTick> get ticks => _tickController.stream;
  Stream<ReplayState> get stateChanges => _stateController.stream;

  int get currentCandleIndex => _index;
  int get totalCandles => _candles.length;
  bool get isPlaying => _playing;
  ReplaySpeed get speed => _speed;
  Candle? get currentCandle => _candles.isEmpty ? null : _candles[_index];

  void play() {
    if (_playing || _disposed || _index >= _candles.length - 1) return;
    _playing = true;
    _scheduleNextTick();
    _emitState();
  }

  void pause() {
    if (!_playing) return;
    _playing = false;
    _timer?.cancel();
    _timer = null;
    _emitState();
  }

  void setSpeed(ReplaySpeed speed) {
    if (_speed == speed) return;
    _speed = speed;
    if (_playing) {
      _timer?.cancel();
      _scheduleNextTick();
    }
    _emitState();
  }

  void _scheduleNextTick() {
    final micros = _baseTickInterval.inMicroseconds ~/ _speed.multiplier;
    _timer = Timer(Duration(microseconds: micros), _advance);
  }

  void _advance() {
    if (_disposed || !_playing) return;
    if (_index >= _candles.length - 1) {
      pause();
      return;
    }
    _index++;
    _emitCurrentAsTick();
    _emitState();
    if (_index < _candles.length - 1) {
      _scheduleNextTick();
    } else {
      pause();
    }
  }

  void _emitCurrentAsTick() {
    if (_candles.isEmpty || _tickController.isClosed) return;
    final candle = _candles[_index];
    _tickController.add(KlineTick(
      eventTimeMs: candle.closeTimeMs,
      symbol: period.symbol,
      interval: period.interval,
      candle: candle,
      isCandleClosed: true,
    ));
  }

  void _emitState() {
    if (_stateController.isClosed) return;
    _stateController.add(ReplayState(
      currentCandleIndex: _index,
      totalCandles: _candles.length,
      isPlaying: _playing,
      speed: _speed,
      currentCandle: currentCandle,
    ));
  }

  Future<void> dispose() async {
    _disposed = true;
    _timer?.cancel();
    await _tickController.close();
    await _stateController.close();
  }
}
