import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'locale_provider.dart';

/// The list of language options, each row shown in ITS OWN script (see
/// `localeDisplayNames`) — reused by both the first-run onboarding picker
/// (language_onboarding_screen.dart) and the Settings screen's language
/// section, so there's exactly one place that lists the 6 supported
/// languages.
class LanguagePickerList extends ConsumerWidget {
  const LanguagePickerList({super.key, this.onSelected});

  /// Called after the locale is persisted — the onboarding screen uses
  /// this to advance to sign-in; Settings leaves it null since selecting
  /// a row there just applies immediately with no navigation.
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(localeProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final locale in supportedAppLocales)
          _LanguageTile(
            locale: locale,
            selected: locale.languageCode == current.languageCode,
            onTap: () async {
              await ref.read(localeProvider.notifier).setLocale(locale);
              onSelected?.call();
            },
          ),
      ],
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({required this.locale, required this.selected, required this.onTap});

  final Locale locale;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      title: Text(
        localeDisplayNames[locale.languageCode] ?? locale.languageCode,
        style: TextStyle(
          color: selected ? const Color(0xFF6FD3C7) : Colors.white,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
          fontSize: 16,
        ),
      ),
      trailing: selected ? const Icon(Icons.check, color: Color(0xFF6FD3C7)) : null,
    );
  }
}
