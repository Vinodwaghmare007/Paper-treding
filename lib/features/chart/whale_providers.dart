import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/sources/whale_alert_source.dart';
import '../../domain/usecases/whale_activity_tracker.dart';

final whaleAlertSourceProvider = Provider<WhaleAlertSource>((ref) {
  final source = WhaleAlertSource();
  ref.onDispose(source.dispose);
  return source;
});

/// Large-Bitcoin-transaction count for the trailing hour — see
/// [WhaleActivityTracker]. Polls every 60s while watched (same cadence as
/// [ForecastController]'s refresh), keeping one [WhaleActivityTracker]
/// instance alive across polls so its dedup/window logic actually
/// accumulates rather than resetting every fetch.
class WhaleActivityController extends AsyncNotifier<int> {
  Timer? _pollTimer;
  final WhaleActivityTracker _tracker = WhaleActivityTracker();

  @override
  Future<int> build() async {
    ref.onDispose(() => _pollTimer?.cancel());
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 60), (_) => refresh());
    return _fetch();
  }

  Future<int> _fetch() async {
    final source = ref.read(whaleAlertSourceProvider);
    final candidates = await source.fetchRecentMempoolTransactions();
    return _tracker.ingest(candidates);
  }

  Future<void> refresh() async {
    state = const AsyncLoading<int>().copyWithPrevious(state);
    state = await AsyncValue.guard(_fetch);
  }
}

final whaleActivityProvider = AsyncNotifierProvider<WhaleActivityController, int>(
  WhaleActivityController.new,
);
