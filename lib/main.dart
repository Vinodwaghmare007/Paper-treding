import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/auth/auth_gate.dart';
import 'features/home/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Reads native config: android/app/google-services.json (Android),
  // ios/Runner/GoogleService-Info.plist (iOS). See project setup notes for
  // the one-time steps required before this app can reach a real project.
  await Firebase.initializeApp();
  runApp(const ProviderScope(child: CryptoPaperTraderApp()));
}

class CryptoPaperTraderApp extends StatelessWidget {
  const CryptoPaperTraderApp({super.key});

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
