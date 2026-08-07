import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/cohort_median.dart';
import '../firestore/cohort_mappers.dart';
import '../firestore/firestore_paths.dart';

/// Read side of the Portfolio Twin feature — public and signed-in-readable
/// (see the `public_cohort_medians` match block in firestore.rules), never
/// written by the client.
class CohortRepository {
  CohortRepository(FirebaseFirestore firestore)
      : _paths = FirestorePaths(firestore);

  final FirestorePaths _paths;

  /// Null if computeCohortMedians.ts hasn't published this cohort — either
  /// it hasn't run yet, or the cohort is currently below MIN_COHORT_SIZE
  /// and was deliberately left unpublished (see that file).
  Stream<CohortMedian?> watchCohortMedian(String cohortKey) {
    return _paths.publicCohortMedian(cohortKey).snapshots().map(
          (doc) => doc.exists ? CohortMedianFirestoreMapping.fromDoc(doc) : null,
        );
  }
}
