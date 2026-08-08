import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/trade_rationale.dart';
import '../../domain/entities/trader_profile.dart';
import '../auth/auth_providers.dart';
import 'trader_profile_providers.dart';

/// A trader's opt-in public performance profile — works for both viewing
/// your own profile and a stranger's, since both go through the exact
/// same server-computed [TraderProfile] read. Everything shown here is
/// derived from real trade data; nothing is a user-entered opinion or
/// prediction (see the Trade Rationale notes below, which are
/// retrospective-only — enforced server-side, not just by this screen).
class TraderProfileScreen extends ConsumerWidget {
  const TraderProfileScreen({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myUid = ref.watch(currentUidProvider);
    final isOwnProfile = uid == myUid;
    final profileAsync = ref.watch(traderProfileProvider(uid));

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E222D),
        title: const Text('Trader Profile'),
      ),
      body: profileAsync.when(
        data: (profile) {
          if (profile == null || !profile.isPublic) {
            return _NotVisible(isOwnProfile: isOwnProfile);
          }
          return _ProfileBody(profile: profile, isOwnProfile: isOwnProfile);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _NotVisible(isOwnProfile: isOwnProfile),
      ),
    );
  }
}

class _NotVisible extends StatelessWidget {
  const _NotVisible({required this.isOwnProfile});
  final bool isOwnProfile;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Text(
          isOwnProfile
              ? "Your profile isn't public yet — turn it on in Profile Settings to get a shareable page."
              : "This trader's profile isn't public.",
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white54),
        ),
      ),
    );
  }
}

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({required this.profile, required this.isOwnProfile});

  final TraderProfile profile;
  final bool isOwnProfile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rationalesAsync = ref.watch(traderRationalesProvider(profile.userId));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          profile.displayName,
          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
        ),
        if (profile.memberSince != null) ...[
          const SizedBox(height: 2),
          Text(
            'Member since ${_dateLabel(profile.memberSince!)}',
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
        const SizedBox(height: 16),
        // Explicit, always-visible — not a tooltip — per the compliance
        // requirement: this is simulated performance, not investment advice.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF1E222D),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white24),
          ),
          child: const Text(
            'Simulated trading performance — educational only, not investment advice.',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
        const SizedBox(height: 16),
        _StatsGrid(profile: profile),
        const SizedBox(height: 16),
        if (!isOwnProfile) _FollowButton(targetUid: profile.userId),
        const SizedBox(height: 24),
        const Text(
          'Trade Rationale',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        const Text(
          'Retrospective notes on closed trades only — never a forward-looking call.',
          style: TextStyle(color: Colors.white38, fontSize: 11),
        ),
        const SizedBox(height: 8),
        rationalesAsync.when(
          data: (notes) => notes.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('No notes yet.', style: TextStyle(color: Colors.white38)),
                )
              : Column(children: [for (final note in notes) _RationaleTile(note: note)]),
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (e, _) => const SizedBox.shrink(),
        ),
      ],
    );
  }

  String _dateLabel(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.profile});
  final TraderProfile profile;

  @override
  Widget build(BuildContext context) {
    final stats = [
      ('Discipline', profile.disciplineScore.toStringAsFixed(0)),
      ('Win Rate', '${profile.winRatePct.toStringAsFixed(0)}%'),
      ('Accuracy', '${profile.accuracyPct.toStringAsFixed(0)}%'),
      ('Trades', '${profile.totalTrades}'),
      ('Followers', '${profile.followerCount}'),
      ('Following', '${profile.followingCount}'),
    ];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.6,
      children: [
        for (final (label, value) in stats)
          Card(
            color: const Color(0xFF1E222D),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(value,
                      style: const TextStyle(
                          color: Color(0xFF6FD3C7), fontSize: 20, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _FollowButton extends ConsumerWidget {
  const _FollowButton({required this.targetUid});
  final String targetUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myUid = ref.watch(currentUidProvider);
    if (myUid == null) return const SizedBox.shrink();

    final isFollowingAsync = ref.watch(isFollowingProvider(targetUid));
    final isFollowing = isFollowingAsync.valueOrNull ?? false;
    final repo = ref.watch(traderProfileRepositoryProvider);

    return SizedBox(
      width: double.infinity,
      child: isFollowing
          ? OutlinedButton(
              onPressed: () => repo.unfollow(myUid, targetUid),
              child: const Text('Unfollow'),
            )
          : FilledButton(
              onPressed: () => repo.follow(myUid, targetUid),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF26A69A)),
              child: const Text('Follow'),
            ),
    );
  }
}

class _RationaleTile extends StatelessWidget {
  const _RationaleTile({required this.note});
  final TradeRationale note;

  @override
  Widget build(BuildContext context) {
    final ts = note.createdAt.toLocal();
    final timeLabel =
        '${ts.year}-${ts.month.toString().padLeft(2, '0')}-${ts.day.toString().padLeft(2, '0')}';
    return Card(
      color: const Color(0xFF1E222D),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${note.coinSymbol} · closed trade',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
            const SizedBox(height: 4),
            Text(note.text, style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 4),
            Text('Posted $timeLabel', style: const TextStyle(color: Colors.white38, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}
