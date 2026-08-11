import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/organization.dart';
import '../../l10n/generated/app_localizations.dart';
import 'org_providers.dart';

/// Visible only to `admin_user_ids` of at least one organization — see
/// MoreMenuButton, which only shows the nav entry into this screen when
/// [adminOrgsProvider] returns a non-empty list. Everything here is
/// read-only Firestore data plus one Cloud Function call
/// (createOrgInviteCode); there is no client-side write path into
/// `organizations/*` at all (see firestore.rules).
class OrgAdminDashboard extends ConsumerWidget {
  const OrgAdminDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final orgsAsync = ref.watch(adminOrgsProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E222D),
        title: Text(l10n.orgDashboardTitle),
      ),
      body: orgsAsync.when(
        data: (orgs) {
          if (orgs.isEmpty) {
            // MoreMenuButton hides the nav entry in this case — reachable
            // only via a stale deep link/back-stack entry after an admin
            // is removed from every org they used to administer.
            return const SizedBox.shrink();
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: orgs.length,
            itemBuilder: (context, index) => _OrgCard(org: orgs[index]),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('$e', style: const TextStyle(color: Color(0xFFEF5350))),
        ),
      ),
    );
  }
}

class _OrgCard extends ConsumerWidget {
  const _OrgCard({required this.org});
  final Organization org;

  Future<void> _generateCode(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final code = await ref.read(createOrgInviteCodeUseCaseProvider).call(orgId: org.id);
      await Clipboard.setData(ClipboardData(text: code));
      messenger.showSnackBar(SnackBar(content: Text(l10n.orgDashboardCodeGenerated(code))));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.orgDashboardGenerateCodeError('$e'))),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final membersAsync = ref.watch(orgMembersProvider(org.id));
    final aggregateAsync = ref.watch(orgAggregateStatsProvider(org.id));

    return Card(
      color: const Color(0xFF1E222D),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(org.name, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              l10n.orgDashboardLicenseLabel(org.licenseType),
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.orgDashboardSeatsLabel('${org.seatsUsed}', '${org.seatLimit}'),
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            if (org.isFull)
              Text(
                l10n.orgDashboardSeatsFullNotice,
                style: const TextStyle(color: Color(0xFFEF5350), fontSize: 12),
              )
            else
              OutlinedButton.icon(
                onPressed: () => _generateCode(context, ref),
                icon: const Icon(Icons.qr_code, size: 18),
                label: Text(l10n.orgDashboardGenerateCodeButton),
              ),
            const Divider(height: 32, color: Colors.white24),
            _AggregateStatsCard(aggregateAsync: aggregateAsync, l10n: l10n),
            const SizedBox(height: 16),
            Text(l10n.orgDashboardMembersTitle, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            membersAsync.when(
              data: (members) {
                if (members.isEmpty) {
                  return Text(
                    l10n.orgDashboardMembersEmpty,
                    style: const TextStyle(color: Colors.white54),
                  );
                }
                final dateFormat = DateFormat.yMMMd(Localizations.localeOf(context).toString());
                return Column(
                  children: members
                      .map(
                        (m) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const CircleAvatar(
                            backgroundColor: Color(0x226FD3C7),
                            child: Icon(Icons.person, color: Color(0xFF6FD3C7), size: 18),
                          ),
                          title: Text(m.displayName, style: const TextStyle(color: Colors.white)),
                          subtitle: Text(
                            l10n.orgDashboardJoinedOn(
                              m.joinedAt == null ? '—' : dateFormat.format(m.joinedAt!),
                            ),
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        ),
                      )
                      .toList(growable: false),
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              ),
              error: (e, _) => Text('$e', style: const TextStyle(color: Color(0xFFEF5350))),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.orgDashboardPrivacyNote,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _AggregateStatsCard extends StatelessWidget {
  const _AggregateStatsCard({required this.aggregateAsync, required this.l10n});

  final AsyncValue<OrgAggregateStats?> aggregateAsync;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return aggregateAsync.when(
      data: (stats) {
        if (stats == null || stats.memberCount == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.orgDashboardAggregateTitle, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                l10n.orgDashboardAggregateNotYetComputed,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.orgDashboardAggregateTitle, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              l10n.orgDashboardAggregateAvgDiscipline(stats.avgDisciplineScore.toStringAsFixed(1)),
              style: const TextStyle(color: Color(0xFF6FD3C7)),
            ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (e, _) => const SizedBox.shrink(),
    );
  }
}
