import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/forecast.dart';
import '../../data/sources/forecast_api_source.dart';
import '../auth/auth_providers.dart';

final forecastApiSourceProvider = Provider<ForecastApiSource>((ref) {
  return ForecastApiSource();
});

/// "Show AI Forecast" toggle state — off by default.
final showAiForecastProvider = StateProvider<bool>((ref) => false);

const _forecastSymbol = 'BTCUSDT';
const _forecastInterval = '1m';
const _forecastSteps = 15;

/// Fetches a forecast when [showAiForecastProvider] is switched on, and
/// keeps it refreshed every 60s while it stays on — comfortably above the
/// backend's 30s-per-symbol rate limit, but still keeps a 15-minute-ahead
/// projection from going stale while the user leaves it enabled.
class ForecastController extends AsyncNotifier<PriceForecast?> {
  Timer? _refreshTimer;

  @override
  Future<PriceForecast?> build() async {
    final enabled = ref.watch(showAiForecastProvider);
    ref.onDispose(() => _refreshTimer?.cancel());
    _refreshTimer?.cancel();

    if (!enabled) return null;

    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) => refresh());
    final forecast = await _fetch();
    // Fired once per toggle-on (from build(), not from refresh()'s 60s
    // periodic re-fetches) — the signal this event should carry is "did
    // someone actually look at a forecast," not "how many times did an
    // already-open one silently refresh in the background."
    unawaited(ref.read(analyticsServiceProvider).logForecastViewed());
    return forecast;
  }

  Future<PriceForecast?> _fetch() {
    final source = ref.read(forecastApiSourceProvider);
    return source.fetchForecast(
      symbol: _forecastSymbol,
      interval: _forecastInterval,
      steps: _forecastSteps,
    );
  }

  Future<void> refresh() async {
    state = const AsyncLoading<PriceForecast?>().copyWithPrevious(state);
    state = await AsyncValue.guard(_fetch);
  }
}

final forecastControllerProvider =
    AsyncNotifierProvider<ForecastController, PriceForecast?>(
  ForecastController.new,
);
