import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/entities/curated_period.dart';
import '../../data/sources/historical_data_cache.dart';
import '../../domain/usecases/market_replay_engine.dart';
import '../chart/price_source.dart';
import '../chart/trading_chart_view.dart';
import '../ticker/ticker_providers.dart';
import '../trade/trade_sheet.dart';

final _historicalDataCacheProvider = Provider<HistoricalDataCache>((ref) {
  final cache = HistoricalDataCache();
  ref.onDispose(cache.close);
  return cache;
});

/// "Time Travel": paper-trade inside a curated historical period at
/// variable speed, through the exact same chart/Buy/Sell UI as live
/// trading. The only thing that differs is which [PriceSource] is in
/// scope — [_ReplayPlayerView] overrides [priceSourceProvider] with a
/// [ReplayPriceSource] wrapping the [MarketReplayEngine] below it, so
/// [TradeSheet] and [TradingChartView] run completely unmodified.
class MarketReplayScreen extends ConsumerStatefulWidget {
  const MarketReplayScreen({super.key});

  @override
  ConsumerState<MarketReplayScreen> createState() => _MarketReplayScreenState();
}

enum _ScreenPhase { selecting, downloading, playing, error }

class _MarketReplayScreenState extends ConsumerState<MarketReplayScreen> {
  _ScreenPhase _phase = _ScreenPhase.selecting;
  CuratedPeriod? _selectedPeriod;
  int _downloadedCount = 0;
  String? _errorMessage;
  MarketReplayEngine? _engine;

  @override
  void dispose() {
    _engine?.dispose();
    super.dispose();
  }

  Future<void> _selectPeriod(CuratedPeriod period) async {
    final cache = ref.read(_historicalDataCacheProvider);
    setState(() {
      _selectedPeriod = period;
      _errorMessage = null;
    });

    try {
      if (!await cache.isPeriodCached(period.id)) {
        setState(() {
          _phase = _ScreenPhase.downloading;
          _downloadedCount = 0;
        });
        await cache.downloadPeriod(
          period,
          restService: ref.read(binanceRestServiceProvider),
          onProgress: (count) {
            if (mounted) setState(() => _downloadedCount = count);
          },
        );
      }

      final candles = await cache.loadPeriod(period.id);
      if (candles.length < 2) {
        setState(() {
          _phase = _ScreenPhase.error;
          _errorMessage = 'No historical data available for ${period.name}.';
        });
        return;
      }

      final engine = MarketReplayEngine(period: period, candles: candles);
      if (!mounted) {
        await engine.dispose();
        return;
      }
      setState(() {
        _engine = engine;
        _phase = _ScreenPhase.playing;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _ScreenPhase.error;
        _errorMessage = 'Could not prepare ${period.name}: $e';
      });
    }
  }

  void _backToSelection() {
    _engine?.dispose();
    setState(() {
      _engine = null;
      _selectedPeriod = null;
      _phase = _ScreenPhase.selecting;
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (_phase) {
      case _ScreenPhase.selecting:
        return _PeriodSelectionScreen(onSelect: _selectPeriod);
      case _ScreenPhase.downloading:
        return _DownloadProgressScreen(
          period: _selectedPeriod!,
          downloadedCount: _downloadedCount,
        );
      case _ScreenPhase.error:
        return _ErrorScreen(message: _errorMessage ?? 'Something went wrong.', onRetry: _backToSelection);
      case _ScreenPhase.playing:
        return ProviderScope(
          overrides: [
            priceSourceProvider.overrideWith((ref) => ReplayPriceSource(_engine!)),
          ],
          child: _ReplayPlayerView(engine: _engine!, onExit: _backToSelection),
        );
    }
  }
}

class _PeriodSelectionScreen extends StatelessWidget {
  const _PeriodSelectionScreen({required this.onSelect});

  final ValueChanged<CuratedPeriod> onSelect;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E222D),
        title: const Text('Market Replay'),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: curatedPeriods.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final period = curatedPeriods[index];
          return Card(
            color: const Color(0xFF1E222D),
            child: ListTile(
              onTap: () => onSelect(period),
              leading: const Icon(Icons.history, color: Color(0xFFFFC107)),
              title: Text(period.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              subtitle: Text(period.description, style: const TextStyle(color: Colors.white54, fontSize: 12)),
              trailing: const Icon(Icons.chevron_right, color: Colors.white38),
            ),
          );
        },
      ),
    );
  }
}

class _DownloadProgressScreen extends StatelessWidget {
  const _DownloadProgressScreen({required this.period, required this.downloadedCount});

  final CuratedPeriod period;
  final int downloadedCount;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: const Color(0xFF1E222D), title: Text(period.name)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              Text(
                'Downloading ${period.name}…',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                '$downloadedCount candles fetched',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 4),
              const Text(
                'One-time download — cached locally after this.',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: const Color(0xFF1E222D), title: const Text('Market Replay')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('Back to periods')),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReplayPlayerView extends ConsumerStatefulWidget {
  const _ReplayPlayerView({required this.engine, required this.onExit});

  final MarketReplayEngine engine;
  final VoidCallback onExit;

  @override
  ConsumerState<_ReplayPlayerView> createState() => _ReplayPlayerViewState();
}

class _ReplayPlayerViewState extends ConsumerState<_ReplayPlayerView> {
  late ReplayState _state;

  @override
  void initState() {
    super.initState();
    _state = ReplayState(
      currentCandleIndex: widget.engine.currentCandleIndex,
      totalCandles: widget.engine.totalCandles,
      isPlaying: widget.engine.isPlaying,
      speed: widget.engine.speed,
      currentCandle: widget.engine.currentCandle,
    );
    widget.engine.stateChanges.listen((state) {
      if (mounted) setState(() => _state = state);
    });
  }

  @override
  Widget build(BuildContext context) {
    final period = widget.engine.period;
    final currentPrice = _state.currentCandle?.close ?? 0;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E222D),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Exit replay',
          onPressed: widget.onExit,
        ),
        title: const Text('Market Replay'),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: const Color(0xFFFFC107).withValues(alpha: 0.15),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.history, color: Color(0xFFFFC107), size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'REPLAY MODE — ${period.name}',
                    style: const TextStyle(
                      color: Color(0xFFFFC107),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            color: const Color(0xFF1E222D),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text(
              currentPrice.toStringAsFixed(2),
              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: TradingChartView(
              fetchSeedCandles: () async => widget.engine.seedCandles,
              ticks: widget.engine.ticks,
              interval: period.interval,
            ),
          ),
          _PlaybackControls(engine: widget.engine, state: _state),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showTradeSheet(
          context,
          coinSymbol: period.symbol,
          currentPrice: currentPrice,
        ),
        icon: const Icon(Icons.swap_vert),
        label: const Text('Trade'),
      ),
    );
  }
}

class _PlaybackControls extends StatelessWidget {
  const _PlaybackControls({required this.engine, required this.state});

  final MarketReplayEngine engine;
  final ReplayState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1E222D),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(value: state.progressFraction),
          const SizedBox(height: 4),
          Text(
            '${state.currentCandleIndex + 1} / ${state.totalCandles} candles'
            '${state.isFinished ? ' — end of period' : ''}',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                iconSize: 36,
                color: const Color(0xFF26A69A),
                icon: Icon(state.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
                tooltip: state.isPlaying ? 'Pause' : 'Play',
                onPressed: state.isPlaying ? engine.pause : engine.play,
              ),
              SegmentedButton<ReplaySpeed>(
                segments: ReplaySpeed.values
                    .map((s) => ButtonSegment(value: s, label: Text(s.label)))
                    .toList(),
                selected: {state.speed},
                onSelectionChanged: (s) => engine.setSpeed(s.first),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
