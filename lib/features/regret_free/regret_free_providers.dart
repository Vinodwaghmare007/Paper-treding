import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/sources/regret_free_shown_tracker.dart';
import '../../domain/entities/order.dart';
import '../../domain/usecases/alternate_outcome_simulator.dart';
import '../portfolio/portfolio_providers.dart';
import '../ticker/ticker_providers.dart';

final alternateOutcomeSimulatorProvider =
    Provider<AlternateOutcomeSimulator>((ref) {
  return AlternateOutcomeSimulator(
    restService: ref.watch(binanceRestServiceProvider),
  );
});

final regretFreeShownTrackerProvider =
    Provider<RegretFreeShownTracker>((ref) => RegretFreeShownTracker());

/// The most recent completed SELL that's eligible for a reveal (its
/// [AlternateOutcomeSimulator.revealDelay] has elapsed) and hasn't been
/// shown yet on this device — or null if there's nothing pending.
///
/// Reuses [orderHistoryStreamProvider] rather than a new Firestore query;
/// "already shown" lives only in local prefs (see
/// [regretFreeShownTrackerProvider]), so this recomputes on every order
/// list update and every provider read, which is cheap for the small
/// per-user order history this app deals with.
final pendingRegretFreeOrderProvider = FutureProvider<Order?>((ref) async {
  final orders = ref.watch(orderHistoryStreamProvider).valueOrNull ?? const [];
  final simulator = ref.watch(alternateOutcomeSimulatorProvider);
  final tracker = ref.watch(regretFreeShownTrackerProvider);

  final sells = orders.where(simulator.isEligible).toList()
    ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

  for (final sell in sells) {
    if (!await tracker.hasShown(sell.id)) return sell;
  }
  return null;
});

/// Async state for the currently generated Regret-Free outcome — a plain
/// [Notifier] rather than a stream, mirroring [WhatIfNotifier]: generation
/// only happens once a pending order is found and the card asks for it.
class RegretFreeNotifier extends AsyncNotifier<RegretFreeOutcome?> {
  @override
  Future<RegretFreeOutcome?> build() async => null;

  Future<void> generate(Order sellOrder) async {
    state = const AsyncLoading<RegretFreeOutcome?>().copyWithPrevious(state);
    state = await AsyncValue.guard(
      () => ref.read(alternateOutcomeSimulatorProvider).simulate(sellOrder),
    );
  }

  Future<void> dismiss(Order sellOrder) async {
    await ref.read(regretFreeShownTrackerProvider).markShown(sellOrder.id);
    state = const AsyncData<RegretFreeOutcome?>(null);
  }
}

final regretFreeProvider =
    AsyncNotifierProvider<RegretFreeNotifier, RegretFreeOutcome?>(
  RegretFreeNotifier.new,
);
