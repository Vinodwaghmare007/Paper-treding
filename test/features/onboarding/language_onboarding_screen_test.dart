import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crypto_paper_trader/features/onboarding/language_onboarding_screen.dart';
import 'package:crypto_paper_trader/features/settings/locale_provider.dart';
import 'package:crypto_paper_trader/l10n/generated/app_localizations.dart';

/// i18n Part F: the first-run language picker is the one screen every user
/// sees in EVERY locale before they've picked one (it's what lets them
/// pick), so it's the single highest-value screen to overflow-test across
/// all 6 languages — including Tamil/Telugu/Kannada, whose longer strings
/// and taller glyphs are the actual risk this test exists to catch. Run at
/// a small phone width (Android's common 320dp low end) since that's where
/// wrapping/overflow shows up first.
void main() {
  for (final locale in supportedAppLocales) {
    testWidgets('LanguageOnboardingScreen renders without overflow in ${locale.languageCode}',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: locale,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: supportedAppLocales,
            home: LanguageOnboardingScreen(onContinue: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Every language name (each shown in its own script) must actually be
      // on screen — a missing AppLocalizations lookup would throw before
      // this point, but this also catches a row silently rendering blank.
      for (final code in supportedAppLocales.map((l) => l.languageCode)) {
        expect(find.text(localeDisplayNames[code]!), findsOneWidget);
      }
    });
  }
}
