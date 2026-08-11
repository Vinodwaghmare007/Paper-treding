import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/org_repository.dart';
import '../../domain/entities/organization.dart';
import '../../domain/usecases/create_org_invite_code.dart';
import '../auth/auth_providers.dart';

final orgRepositoryProvider = Provider<OrgRepository>((ref) {
  return OrgRepository(ref.watch(firebaseFirestoreProvider));
});

final createOrgInviteCodeUseCaseProvider =
    Provider<CreateOrgInviteCodeUseCase>((ref) => CreateOrgInviteCodeUseCase());

/// Every org the signed-in user administers. Empty (not an error) for the
/// overwhelming majority of users — individual consumer accounts — which
/// is exactly the signal MoreMenuButton uses to decide whether to show the
/// "Academy dashboard" entry at all.
final adminOrgsProvider = StreamProvider<List<Organization>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(orgRepositoryProvider).watchAdminOrgs(uid);
});

final orgMembersProvider = StreamProvider.family<List<OrgMember>, String>((ref, orgId) {
  return ref.watch(orgRepositoryProvider).watchMembers(orgId);
});

final orgAggregateStatsProvider =
    StreamProvider.family<OrgAggregateStats?, String>((ref, orgId) {
  return ref.watch(orgRepositoryProvider).watchAggregateStats(orgId);
});
