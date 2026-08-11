/// A B2B academy license at `organizations/{orgId}` — provisioned manually
/// via the Admin SDK (see firestore_paths.dart's doc comment), never
/// client-created. Only ever read by the org's own admins.
class Organization {
  const Organization({
    required this.id,
    required this.name,
    required this.licenseType,
    required this.seatLimit,
    required this.seatsUsed,
    required this.adminUserIds,
    this.expiresAt,
  });

  final String id;
  final String name;

  /// `'trial'` or `'paid'` — surfaced as-is rather than parsed into an enum
  /// so a third tier added later (Admin SDK side only) doesn't need a
  /// client release to display correctly.
  final String licenseType;
  final int seatLimit;
  final int seatsUsed;
  final List<String> adminUserIds;
  final DateTime? expiresAt;

  int get seatsAvailable => (seatLimit - seatsUsed).clamp(0, seatLimit);
  bool get isFull => seatsUsed >= seatLimit;

  factory Organization.fromMap(String id, Map<String, dynamic> map) {
    final expiresTs = map['expires_at'];
    return Organization(
      id: id,
      name: map['name'] as String? ?? 'Organization',
      licenseType: map['license_type'] as String? ?? 'trial',
      seatLimit: (map['seat_limit'] as num?)?.toInt() ?? 0,
      seatsUsed: (map['seats_used'] as num?)?.toInt() ?? 0,
      adminUserIds: (map['admin_user_ids'] as List<dynamic>?)?.cast<String>() ?? const [],
      expiresAt: (expiresTs as dynamic)?.toDate() as DateTime?,
    );
  }
}

/// One row of `organizations/{orgId}/members/{uid}` — deliberately just
/// these two fields (see functions/src/growth/orgs.ts's
/// redeemOrgInviteCodeForUser, the only writer). The admin dashboard can
/// never see more than this by construction: no trade history, no
/// portfolio, no order data ever lands in this subcollection.
class OrgMember {
  const OrgMember({
    required this.uid,
    required this.displayName,
    required this.joinedAt,
  });

  final String uid;
  final String displayName;
  final DateTime? joinedAt;

  factory OrgMember.fromMap(String uid, Map<String, dynamic> map) {
    final joinedTs = map['joined_at'];
    return OrgMember(
      uid: uid,
      displayName: map['display_name'] as String? ?? 'Student',
      joinedAt: (joinedTs as dynamic)?.toDate() as DateTime?,
    );
  }
}

/// `organizations/{orgId}/aggregate_stats/data` — anonymous, Cloud-
/// Function-computed cohort stats (mirrors public_cohort_medians). Never
/// derived from any single student's data on the client; the admin never
/// reads an individual profile_stats doc to produce this.
class OrgAggregateStats {
  const OrgAggregateStats({
    required this.memberCount,
    required this.avgDisciplineScore,
    this.computedAt,
  });

  final int memberCount;
  final double avgDisciplineScore;
  final DateTime? computedAt;

  factory OrgAggregateStats.fromMap(Map<String, dynamic> map) {
    final computedTs = map['computed_at'];
    return OrgAggregateStats(
      memberCount: (map['member_count'] as num?)?.toInt() ?? 0,
      avgDisciplineScore: (map['avg_discipline_score'] as num?)?.toDouble() ?? 0,
      computedAt: (computedTs as dynamic)?.toDate() as DateTime?,
    );
  }
}
