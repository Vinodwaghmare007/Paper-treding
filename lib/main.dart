import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import 'data/background/market_weather_sync_task.dart';
import 'features/auth/auth_gate.dart';
import 'features/home/home_deep_link.dart';
import 'features/home/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Reads native config: android/app/google-services.json (Android),
  // ios/Runner/GoogleService-Info.plist (iOS). See project setup notes for
  // the one-time steps required before this app can reach a real project.
  await Firebase.initializeApp();
  await initializeMarketWeatherSync();
  runApp(const ProviderScope(child: CryptoPaperTraderApp()));
}

class CryptoPaperTraderApp extends ConsumerStatefulWidget {
  const CryptoPaperTraderApp({super.key});

  @override
  ConsumerState<CryptoPaperTraderApp> createState() => _CryptoPaperTraderAppState();
}

class _CryptoPaperTraderAppState extends ConsumerState<CryptoPaperTraderApp> {
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
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF26A69A),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF131722),
        useMaterial3: true,
      ),
      home: const AuthGate(signedIn: _buildHomeShell),
    );
  }

  static Widget _buildHomeShell(BuildContext context) => const HomeShell();
}
