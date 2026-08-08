import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/activity_event.dart';
import '../../domain/entities/certification.dart' show CertificationDisplay;
import 'trader_profile_providers.dart';
import 'trader_profile_screen.dart';

/// Feed of followed traders' recent activity — deliberately limited to
/// three factual, server-verified event shapes (see
/// functions/src/traderProfile/publicActivity.ts): a closed trade, a
/// posted Trade Rationale, or an earned certification. There is
/// intentionally no free-text post composer anywhere in this screen or
/// its data path — adding one would reopen the exact regulatory risk
/// (disguised forward-looking coin calls) this whole feature was
/// designed around. If a future request asks for one, that's a decision
/// to flag, not just implement.
class FollowingFeedScreen extends ConsumerWidget {
  const FollowingFeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(followingFeedProvider);
    final followedIds = ref.watch(followedUserIdsProvider).valueOrNull ?? const [];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E222D),
        title: const Text('Following'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(followingFeedProvider.future),
        child: followedIds.isEmpty
            ? ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        "You're not following anyone yet — find traders on the "
                        'Leaderboard tab.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white54),
                      ),
                    ),
                  ),
                ],
              )
            : feedAsync.when(
                data: (events) {
                  if (events.isEmpty) {
                    return ListView(
                      children: const [
                        Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                            child: Text('No recent activity from traders you follow.',
                                style: TextStyle(color: Colors.white54)),
                          ),
                        ),
                      ],
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: events.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => _ActivityTile(event: events[index]),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text('Could not load the feed: $e',
                            style: const TextStyle(color: Color(0xFFEF5350))),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.event});
  final ActivityEvent event;

  @override
  Widget build(BuildContext context) {
    final (icon, color, text) = switch (event) {
      TradeActivityEvent(:final coinSymbol, :final outcome) => (
          outcome == 'profit'
              ? Icons.trending_up
              : outcome == 'loss'
                  ? Icons.trending_down
                  : Icons.trending_flat,
          outcome == 'profit'
              ? const Color(0xFF26A69A)
              : outcome == 'loss'
                  ? const Color(0xFFEF5350)
                  : Colors.white54,
          'closed a $coinSymbol trade ($outcome)',
        ),
      RationaleActivityEvent(:final coinSymbol) => (
          Icons.notes,
          const Color(0xFF6FD3C7),
          'posted a Trade Rationale on ${coinSymbol ?? 'a trade'}',
        ),
      CertificationActivityEvent(:final milestoneType) => (
          Icons.workspace_premium,
          const Color(0xFFFFC107),
          'earned "${milestoneType.milestoneTitle}"',
        ),
    };
    final ts = event.createdAt.toLocal();
    final timeLabel =
        '${ts.year}-${ts.month.toString().padLeft(2, '0')}-${ts.day.toString().padLeft(2, '0')}';

    return Card(
      color: const Color(0xFF1E222D),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: RichText(
          text: TextSpan(
            style: const TextStyle(color: Colors.white, fontSize: 14),
            children: [
              TextSpan(
                text: event.displayName,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              TextSpan(text: ' $text'),
            ],
          ),
        ),
        subtitle: Text(timeLabel, style: const TextStyle(color: Colors.white38, fontSize: 11)),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TraderProfileScreen(uid: event.userId),
          ),
        ),
      ),
    );
  }
}
