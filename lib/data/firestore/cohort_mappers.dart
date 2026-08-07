import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/cohort_median.dart';

/// Converts between [CohortMedian] and its Firestore document shape. Kept
/// out of `domain/` so the entity stays Firebase-free.
extension CohortMedianFirestoreMapping on CohortMedian {
  static CohortMedian fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) {
      throw StateError('public_cohort_medians/${doc.id} does not exist');
    }
    final ts = data['updated_at'];
    return CohortMedian(
      cohortKey: doc.id,
      medianPortfolioValue: (data['median_portfolio_value'] as num).toDouble(),
      memberCount: (data['member_count'] as num?)?.toInt() ?? 0,
      updatedAt: ts is Timestamp
          ? ts.toDate().toUtc()
          : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}
