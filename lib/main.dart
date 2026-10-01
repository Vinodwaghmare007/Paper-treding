import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:home_widget/home_widget.dart';

import 'data/background/market_weather_sync_task.dart';
import 'features/ads/ad_config.dart';
import 'features/ads/interstitial_ad_manager.dart';
import 'features/home/home_deep_link.dart';
import 'features/home/home_shell.dart';
import 'features/onboarding/language_onboarding_gate.dart';
import 'features/settings/locale_provider.dart';
import 'l10n/generated/app_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Reads native config: android/app/google-services.json (Android),
  // ios/Runner/GoogleService-Info.plist (iOS). See project setup notes for
  // the one-time steps required before this app can reach a real project.
  await Firebase.initializeApp();
  await _initializeCrashlytics();
  await initializeMarketWeatherSync();
  _initializeAds();
  runApp(const ProviderScope(child: CryptoPaperTraderApp()));
}

/// Starts the Google Mobile Ads SDK without blocking first frame, then
/// preloads the first interstitial so it's ready by the first navigation.
void _initializeAds() {
  if (!AdConfig.supported) return;
  unawaited(MobileAds.instance.initialize().then((_) {
    InterstitialAdManager.instance.preload();
  }));
}

/// Routes both Flutter framework errors and uncaught async errors to
/// Crashlytics. Disabled in debug builds (`kDebugMode`) so local
/// development crashes don't pollute production crash-free-user metrics —
/// this cannot be verified end-to-end in this sandbox (no live Firebase
/// project or device here to confirm a report actually lands in the
/// Crashlytics console), so treat "does a real crash on a real device
/// show up in the console" as its own manual QA step after deploy.
Future<void> _initializeCrashlytics() async {
  await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(!kDebugMode);
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };
}

class CryptoPaperTraderApp extends ConsumerStatefulWidget {
  const CryptoPaperTraderApp({super.key});

  @override
  ConsumerState<CryptoPaperTraderApp> createState() => _CryptoPaperTraderAppState();
}

class _CryptoPaperTraderAppState extends ConsumerState<CryptoPaperTraderApp> {
  final _interstitialAdObserver = InterstitialAdNavigatorObserver();
  StreamSubscription<Uri?>? _widgetClickSubscription;

  @override
  void initState() {
    super.initState();
    _widgetClickSubscription = HomeWidget.widgetClicked.listen(_handleDeepLink);
    HomeWidget.initiallyLaunchedFromHomeWidget().then(_handleDeepLink);
  }

  void _handleDeepLink(Uri? uri) {
    if (isChartDeepLink(uri)) {
      ref.read(pendingDeepLinkTabProvider.notifier).state = chartTabIndex;
    }
  }

  @override
  void dispose() {
    _widgetClickSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Crypto Paper Trader',
      debugShowCheckedModeBanner: false,
      navigatorObservers: [_interstitialAdObserver],
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF26A69A),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF131722),
        useMaterial3: true,
      ),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: supportedAppLocales,
      locale: ref.watch(localeProvider),
      home: const LanguageOnboardingGate(signedIn: _buildHomeShell),
    );
  }

  static Widget _buildHomeShell(BuildContext context) => const HomeShell();
}
