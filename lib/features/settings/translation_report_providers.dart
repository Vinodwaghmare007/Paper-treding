import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/translation_report_repository.dart';
import '../auth/auth_providers.dart';

final translationReportRepositoryProvider = Provider<TranslationReportRepository>((ref) {
  return TranslationReportRepository(ref.watch(firebaseFirestoreProvider));
});
