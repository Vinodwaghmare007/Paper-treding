import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/leaderboard_entry.dart';
import 'trader_profile_providers.dart';
import 'trader_profile_screen.dart';

/// Top-100 leaderboards computed by functions/src/traderProfile/
/// computeLeaderboard.ts every 6 hours — this screen only ever reads the
/// single small public_leaderboard/{window} doc, never queries traders
/// directly.
class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E222D),
          title: const Text('Leaderboard'),
          bottom: const TabBar(
            tabs: [Tab(text: 'Weekly'), Tab(text: 'All-Time')],
          ),
        ),
        body: const TabBarView(
          children: [
            _LeaderboardList(window: LeaderboardWindow.weekly),
            _LeaderboardList(window: LeaderboardWindow.allTime),
          ],
        ),
      ),
    );
  }
}

class _LeaderboardList extends ConsumerWidget {
  const _LeaderboardList({required this.window});
  final LeaderboardWindow window;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(leaderboardProvider(window));

    return Column(
      children: [
        Container(
          width: double.infinity,
          color: const Color(0xFF1E222D),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: const Text(
            'Ranked by simulated discipline + win rate — educational only, '
            'not investment advice.',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ),
        Expanded(
          child: entriesAsync.when(
            data: (entries) {
              if (entries.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      window == LeaderboardWindow.weekly
                          ? 'No active traders on the weekly leaderboard yet.'
                          : 'No traders on the leaderboard yet.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white54),
                    ),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: entries.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) => _LeaderboardTile(
                  rank: index + 1,
                  entry: entries[index],
                ),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Text('Could not load the leaderboard: $e',
                  style: const TextStyle(color: Color(0xFFEF5350))),
            ),
          ),
        ),
      ],
    );
  }
}

class _LeaderboardTile extends StatelessWidget {
  const _LeaderboardTile({required this.rank, required this.entry});

  final int rank;
  final LeaderboardEntry entry;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF1E222D),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0xFF6FD3C7).withValues(alpha: 0.15),
          child: Text('$rank', style: const TextStyle(color: Color(0xFF6FD3C7))),
        ),
        title: Text(entry.displayName, style: const TextStyle(color: Colors.white)),
        subtitle: Text(
          'Discipline ${entry.disciplineScore.toStringAsFixed(0)}  ·  '
          'Win rate ${entry.winRatePct.toStringAsFixed(0)}%',
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TraderProfileScreen(uid: entry.userId),
          ),
        ),
      ),
    );
  }
}
