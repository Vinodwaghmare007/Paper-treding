import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../portfolio/portfolio_providers.dart';

/// Live revenge-blocker lock state: whether buying is currently locked, and
/// how many seconds remain — recomputed every second by [TradeLockNotifier]
/// so the UI counts down in real time, not just on the rare Firestore
/// snapshot that actually changes `buy_locked_until`.
class TradeLockState {
  const TradeLockState({
    required this.isLocked,
    required this.remainingSeconds,
    required this.lockedUntil,
  });

  static const unlocked =
      TradeLockState(isLocked: false, remainingSeconds: 0, lockedUntil: null);

  final bool isLocked;
  final int remainingSeconds;
  final DateTime? lockedUntil;
}

/// Watches `users/{userId}.buy_locked_until` (via [accountStreamProvider])
/// and ticks [TradeLockState.remainingSeconds] down once per second while a
/// lock is active.
class TradeLockNotifier extends Notifier<TradeLockState> {
  Timer? _ticker;

  @override
  TradeLockState build() {
    final lockedUntil = ref.watch(accountStreamProvider).valueOrNull?.buyLockedUntil;
    ref.onDispose(() => _ticker?.cancel());
    _ticker?.cancel();

    if (lockedUntil == null) return TradeLockState.unlocked;

    final initial = _stateFor(lockedUntil);
    if (initial.isLocked) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        state = _stateFor(lockedUntil);
        if (!state.isLocked) _ticker?.cancel();
      });
    }
    return initial;
  }

  // Reads package:clock's `clock.now()` rather than plain `DateTime.now()`
  // so tests can fake-advance past a lock deterministically (via
  // `withClock`/flutter_test's FakeAsync, which `package:clock` integrates
  // with) instead of needing a real wall-clock wait — see
  // test/features/trade/revenge_blocker_test.dart.
  TradeLockState _stateFor(DateTime lockedUntil) {
    final remaining = lockedUntil.difference(clock.now().toUtc()).inSeconds;
    if (remaining <= 0) return TradeLockState.unlocked;
    return TradeLockState(
      isLocked: true,
      remainingSeconds: remaining,
      lockedUntil: lockedUntil,
    );
  }
}

final tradeLockProvider =
    NotifierProvider<TradeLockNotifier, TradeLockState>(TradeLockNotifier.new);
