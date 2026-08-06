import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/usecases/trade_frequency_monitor.dart';
import '../portfolio/portfolio_providers.dart';

/// Trade count in the trailing 60 minutes. Ticks every 30s so the count
/// visibly drops as old trades age out of the window even with no new
/// trades arriving — order history only pushes a new Firestore snapshot on
/// a *new* trade, which wouldn't otherwise reflect the window moving.
class TradeFrequencyNotifier extends Notifier<int> {
  Timer? _ticker;

  @override
  int build() {
    final orders = ref.watch(orderHistoryStreamProvider).valueOrNull ?? const [];
    ref.onDispose(() => _ticker?.cancel());
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      state = countTradesInTrailingWindow(orders, now: DateTime.now().toUtc());
    });
    return countTradesInTrailingWindow(orders, now: DateTime.now().toUtc());
  }
}

final tradeFrequencyProvider =
    NotifierProvider<TradeFrequencyNotifier, int>(TradeFrequencyNotifier.new);

final isHighFrequencyTradingProvider = Provider<bool>((ref) {
  return ref.watch(tradeFrequencyProvider) > highFrequencyTradeThreshold;
});
