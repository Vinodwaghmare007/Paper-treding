import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../settings/language_picker.dart';

/// First-run language picker — shown once, before sign-in. Surfacing the
/// choice here (not just buried in Settings) is what actually drives
/// adoption of this feature: most users never go looking for a settings
/// toggle they don't know exists.
class LanguageOnboardingScreen extends StatelessWidget {
  const LanguageOnboardingScreen({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 48),
              const Icon(Icons.language, size: 48, color: Color(0xFF26A69A)),
              const SizedBox(height: 16),
              Text(
                l10n.chooseLanguageTitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.chooseLanguageSubtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: SingleChildScrollView(
                  child: LanguagePickerList(),
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onContinue,
                  child: Text(l10n.continueButton),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
