import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';
import 'package:workmanager/workmanager.dart';

import '../sources/market_weather_source.dart';

/// The Android home-screen widget's provider class name — must match
/// android/app/src/main/kotlin/.../MarketWeatherWidgetProvider.kt exactly.
const marketWeatherWidgetProviderName = 'MarketWeatherWidgetProvider';

const _syncTaskName = 'marketWeatherSync';
const _periodicTaskUniqueName = 'marketWeatherSync.periodic';
const _oneOffTaskUniqueName = 'marketWeatherSync.initial';

/// How often the widget refreshes in the background — matches
/// computeMarketWeather.ts's own 4-hour schedule 1:1, so the widget is
/// never showing a stale tier for longer than the server-side value could
/// possibly have been stale anyway. This is also comfortably above
/// Android WorkManager's 15-minute periodic-task floor, and the point is
/// explicitly *not* to poll more often than the data actually changes.
const marketWeatherSyncInterval = Duration(hours: 4);

/// Registers the periodic background sync — call once from `main()`. Also
/// kicks off a single immediate one-off sync so a fresh install doesn't
/// leave the widget blank for up to 4 hours waiting on the first periodic
/// run.
Future<void> initializeMarketWeatherSync() async {
  await Workmanager().initialize(callbackDispatcher);
  await Workmanager().registerOneOffTask(
    _oneOffTaskUniqueName,
    _syncTaskName,
    existingWorkPolicy: ExistingWorkPolicy.keep,
    constraints: Constraints(networkType: NetworkType.connected),
  );
  await Workmanager().registerPeriodicTask(
    _periodicTaskUniqueName,
    _syncTaskName,
    frequency: marketWeatherSyncInterval,
    existingWorkPolicy: ExistingWorkPolicy.keep,
    constraints: Constraints(networkType: NetworkType.connected),
  );
}

/// Runs in a separate headless Dart isolate spawned by Android WorkManager
/// — see the class doc on [MarketWeatherSource] for why it talks to
/// Firestore over plain REST rather than the SDK. Registered via
/// `Workmanager().initialize` in [initializeMarketWeatherSync]; must stay a
/// top-level (or static) function per the `workmanager` package's
/// requirements for background isolate entry points.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    final source = MarketWeatherSource();
    try {
      final weather = await source.fetchCurrent();
      await HomeWidget.saveWidgetData('weather_tier', weather.tier);
      await HomeWidget.saveWidgetData('weather_icon_key', weather.iconKey);
      await HomeWidget.saveWidgetData(
        'weather_updated_label',
        _relativeLabel(weather.updatedAt),
      );
      await HomeWidget.updateWidget(androidName: marketWeatherWidgetProviderName);
      return true;
    } catch (_) {
      // Leaves the widget showing its last-known-good value rather than
      // clearing it — a transient network failure shouldn't blank out a
      // still-basically-correct 4-hour-old reading. WorkManager will retry
      // on its own schedule regardless of the return value here.
      return false;
    } finally {
      source.dispose();
    }
  });
}

String _relativeLabel(DateTime updatedAt) {
  final age = DateTime.now().toUtc().difference(updatedAt);
  if (age.inMinutes < 60) return 'Updated ${age.inMinutes}m ago';
  if (age.inHours < 24) return 'Updated ${age.inHours}h ago';
  return 'Updated ${age.inDays}d ago';
}

/// The widget's deep link (see MarketWeatherWidgetProvider.kt) — used both
/// for `HomeWidget.initiallyLaunchedFromHomeWidget()` (cold start) and the
/// `HomeWidget.widgetClicked` stream (warm tap) in main.dart.
bool isChartDeepLink(Uri? uri) => uri?.host == 'chart';
