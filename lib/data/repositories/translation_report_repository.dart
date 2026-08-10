import 'package:cloud_firestore/cloud_firestore.dart';

import '../firestore/firestore_paths.dart';

/// Write-only sink for the Settings screen's "Report a translation issue"
/// form (i18n Part D) — write-only from here, same shape as
/// ChatRepository.reportMessage, since acting on these is a manual review
/// step (see docs/translation_glossary.md), not something the client reads
/// back.
class TranslationReportRepository {
  TranslationReportRepository(FirebaseFirestore firestore) : _paths = FirestorePaths(firestore);

  final FirestorePaths _paths;

  Future<void> reportTranslationIssue({
    required String reportedBy,
    required String languageCode,
    required String arbKey,
    required String suggestion,
  }) {
    return _paths.newTranslationReportRef().set({
      'reported_by': reportedBy,
      'language_code': languageCode,
      'arb_key': arbKey,
      'suggestion': suggestion,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }
}
