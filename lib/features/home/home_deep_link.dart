import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The chart tab's index in [HomeShell]'s `_tabs` list — the Market
/// Weather widget's only deep-link target today (see
/// market_weather_sync_task.dart's `isChartDeepLink`). A plain constant
/// rather than something HomeShell derives from its own list, so this file
/// doesn't have to import home_shell.dart just to agree on a number.
const chartTabIndex = 0;

/// Set (to [chartTabIndex]) when the Market Weather widget's deep link
/// should jump the signed-in shell to a specific tab — from a cold start
/// via `HomeWidget.initiallyLaunchedFromHomeWidget()` or a warm tap via
/// `HomeWidget.widgetClicked`, both wired in main.dart. [HomeShell] watches
/// this and clears it back to null once handled, so it only ever fires the
/// jump once per tap.
final pendingDeepLinkTabProvider = StateProvider<int?>((ref) => null);
