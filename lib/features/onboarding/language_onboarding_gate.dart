import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_gate.dart';
import '../settings/locale_provider.dart';
import 'language_onboarding_screen.dart';

/// Root widget below MaterialApp: shows the first-run language picker
/// exactly once (before sign-in even loads), then [AuthGate] for every
/// subsequent launch. See locale_provider.dart's [hasChosenLanguageProvider]
/// for how "once" is tracked — an explicit choice here or in Settings,
/// not just the device-locale guess every launch resolves to anyway.
class LanguageOnboardingGate extends ConsumerStatefulWidget {
  const LanguageOnboardingGate({super.key, required this.signedIn});

  /// Forwarded straight through to [AuthGate] once past the language step.
  final WidgetBuilder signedIn;

  @override
  ConsumerState<LanguageOnboardingGate> createState() => _LanguageOnboardingGateState();
}

class _LanguageOnboardingGateState extends ConsumerState<LanguageOnboardingGate> {
  bool _justChoseLanguage = false;

  @override
  Widget build(BuildContext context) {
    if (_justChoseLanguage) return AuthGate(signedIn: widget.signedIn);

    final hasChosenAsync = ref.watch(hasChosenLanguageProvider);
    return hasChosenAsync.when(
      data: (hasChosen) => hasChosen
          ? AuthGate(signedIn: widget.signedIn)
          : LanguageOnboardingScreen(
              onContinue: () => setState(() => _justChoseLanguage = true),
            ),
      // Briefly blank rather than a spinner — this check is a single fast
      // SharedPreferences read, a spinner would just flash for one frame.
      loading: () => const SizedBox.shrink(),
      error: (_, __) => AuthGate(signedIn: widget.signedIn),
    );
  }
}
