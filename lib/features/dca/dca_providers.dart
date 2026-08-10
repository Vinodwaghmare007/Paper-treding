import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/usecases/dca_simulator.dart';
import '../ticker/ticker_providers.dart';

/// Draft form state for the DCA simulator — a plain mutable class rather
/// than several separate providers, since these 4 fields only ever change
/// together right before a "Run" tap, not independently reactive to
/// anything else.
class DcaInputs {
  const DcaInputs({
    required this.symbol,
    required this.recurringAmount,
    required this.frequency,
    required this.startDate,
    required this.endDate,
  });

  final String symbol;
  final double recurringAmount;
  final DcaFrequency frequency;
  final DateTime startDate;
  final DateTime endDate;

  DcaInputs copyWith({
    String? symbol,
    double? recurringAmount,
    DcaFrequency? frequency,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return DcaInputs(
      symbol: symbol ?? this.symbol,
      recurringAmount: recurringAmount ?? this.recurringAmount,
      frequency: frequency ?? this.frequency,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
    );
  }
}

final dcaInputsProvider = StateProvider.autoDispose<DcaInputs>((ref) {
  final now = DateTime.now().toUtc();
  return DcaInputs(
    symbol: 'BTCUSDT',
    recurringAmount: 500,
    frequency: DcaFrequency.weekly,
    // 1 year back by default — a meaningful DCA story without forcing a
    // slow multi-page 5-year fetch just to see the screen for the first
    // time; the date range is fully user-editable up to the app's 5-year
    // historical window.
    startDate: DateTime.utc(now.year - 1, now.month, now.day),
    endDate: now,
  );
});

/// Runs the simulation against the SAME historical data source
/// (`BinanceRestService.fetchKlinesRange`) as the 5-year chart — no
/// separate dataset. Re-fetches only when `run()` is called, not on every
/// input keystroke, since a multi-year daily-candle fetch is real network
/// work.
class DcaResultController extends AutoDisposeAsyncNotifier<DcaResult?> {
  @override
  Future<DcaResult?> build() async => null;

  Future<void> run() async {
    final inputs = ref.read(dcaInputsProvider);
    state = const AsyncLoading<DcaResult?>().copyWithPrevious(state);
    state = await AsyncValue.guard(() async {
      final rest = ref.read(binanceRestServiceProvider);
      final candles = await rest.fetchKlinesRange(
        symbol: inputs.symbol,
        interval: '1d',
        start: inputs.startDate,
        end: inputs.endDate,
      );
      return simulateDca(
        candles: candles,
        recurringAmount: inputs.recurringAmount,
        frequency: inputs.frequency,
        startDate: inputs.startDate,
        endDate: inputs.endDate,
      );
    });
  }
}

final dcaResultProvider =
    AutoDisposeAsyncNotifierProvider<DcaResultController, DcaResult?>(DcaResultController.new);
