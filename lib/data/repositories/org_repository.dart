import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/organization.dart';
import '../firestore/firestore_paths.dart';

/// Reads for the B2B academy admin dashboard. Every write under
/// `organizations/{orgId}` happens only inside a Cloud Function (see
/// functions/src/growth/orgs.ts and computeOrgAggregateStats.ts) — this
/// repository is read-only by design, matching firestore.rules'
/// `allow write: if false` on every doc it touches.
class OrgRepository {
  OrgRepository(FirebaseFirestore firestore) : _paths = FirestorePaths(firestore);

  final FirestorePaths _paths;

  /// Every org this uid administers. Almost always zero or one result —
  /// an admin belonging to multiple academies is a real but rare case the
  /// query still handles correctly.
  Stream<List<Organization>> watchAdminOrgs(String uid) {
    return _paths
        .organizations()
        .where('admin_user_ids', arrayContains: uid)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => Organization.fromMap(doc.id, doc.data()))
            .toList(growable: false));
  }

  Stream<List<OrgMember>> watchMembers(String orgId) {
    return _paths.orgMembers(orgId).orderBy('joined_at', descending: true).snapshots().map(
          (snap) => snap.docs
              .map((doc) => OrgMember.fromMap(doc.id, doc.data()))
              .toList(growable: false),
        );
  }

  /// Null until computeOrgAggregateStats.ts's first daily run after the
  /// org has any members — an org with no run yet simply shows no
  /// cohort-average card rather than a fabricated zero.
  Stream<OrgAggregateStats?> watchAggregateStats(String orgId) {
    return _paths.orgAggregateStats(orgId).snapshots().map((snap) {
      final data = snap.data();
      if (data == null) return null;
      return OrgAggregateStats.fromMap(data);
    });
  }
}
