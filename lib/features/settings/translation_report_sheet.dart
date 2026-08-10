import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations.dart';
import '../auth/auth_providers.dart';
import 'locale_provider.dart';
import 'translation_report_providers.dart';

/// The i18n Part D "report bad translation" mechanism — a free-text form
/// (not a raw ARB-key picker, since a user reading a mistranslated string
/// has no idea what its internal key is called) that logs the current
/// locale + the user's description to Firestore `translation_reports` for
/// manual review, per docs/translation_glossary.md.
class TranslationReportSheet extends ConsumerStatefulWidget {
  const TranslationReportSheet({super.key});

  @override
  ConsumerState<TranslationReportSheet> createState() => _TranslationReportSheetState();
}

class _TranslationReportSheetState extends ConsumerState<TranslationReportSheet> {
  final _whereController = TextEditingController();
  final _suggestionController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _whereController.dispose();
    _suggestionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    if (_whereController.text.trim().isEmpty && _suggestionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.translationReportEmptyError)));
      return;
    }

    setState(() => _submitting = true);
    final uid = ref.read(currentUidProvider);
    final languageCode = ref.read(localeProvider).languageCode;
    try {
      await ref.read(translationReportRepositoryProvider).reportTranslationIssue(
            reportedBy: uid ?? 'unknown',
            languageCode: languageCode,
            arbKey: _whereController.text.trim(),
            suggestion: _suggestionController.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.translationReportSuccess)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.translationReportError)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.translationReportTitle,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.translationReportDescription,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _whereController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: l10n.translationReportWhereLabel,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _suggestionController,
            style: const TextStyle(color: Colors.white),
            maxLines: 3,
            decoration: InputDecoration(
              labelText: l10n.translationReportSuggestionLabel,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.translationReportSubmit),
          ),
        ],
      ),
    );
  }
}
