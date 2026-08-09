import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/auth_repository.dart';
import '../auth/auth_providers.dart';
import '../backtester/backtester_screen.dart';
import '../certifications/certificate_screen.dart';
import '../chat/community_chat_screen.dart';
import '../markets/markets_screen.dart';
import '../puzzle/daily_puzzle_screen.dart';
import '../replay/market_replay_screen.dart';
import '../social/following_feed_screen.dart';
import '../social/leaderboard_screen.dart';
import '../social/profile_settings_screen.dart';
import '../social/trader_profile_screen.dart';
import '../whatif/whatif_screen.dart';

/// Single overflow entry point shown on the 4 primary tabs
/// (Chart/Orders/News/Portfolio) for everything else. Account actions sit
/// at the top of the sheet — "profile lives in the menu, near the top" is
/// the mental model most users already carry in from Gmail/Instagram-style
/// apps — followed by the secondary feature screens, grouped by how
/// they're actually used rather than by build order: deliberate
/// practice/analysis sessions first, social/progress check-ins after.
/// Keeping the bottom nav down to 4 destinations (Material's own guidance
/// tops out around 5) trades discoverability of the other 8 screens for a
/// primary nav a thumb can scan and act on without reading every label.
class MoreMenuButton extends ConsumerWidget {
  const MoreMenuButton({super.key});

  Future<void> _confirmAndDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E222D),
        title: const Text('Delete account?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This permanently deletes your account, simulated trade history, '
          'and chat messages. This cannot be undone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFEF5350)),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(authRepositoryProvider).deleteAccount();
    } on AuthFailure catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _openScreen(BuildContext context, Widget screen) {
    Navigator.of(context).pop();
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      icon: const Icon(Icons.menu),
      tooltip: 'More',
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        backgroundColor: const Color(0xFF1E222D),
        isScrollControlled: true,
        builder: (sheetContext) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.account_circle_outlined),
                title: const Text('My trader profile'),
                onTap: () {
                  final uid = ref.read(currentUidProvider);
                  if (uid == null) return;
                  _openScreen(sheetContext, TraderProfileScreen(uid: uid));
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('Public profile settings'),
                onTap: () => _openScreen(sheetContext, const ProfileSettingsScreen()),
              ),
              const Divider(color: Colors.white24),
              ListTile(
                leading: const Icon(Icons.currency_exchange),
                title: const Text('Markets'),
                subtitle: const Text('Browse and follow coins', style: TextStyle(fontSize: 11)),
                onTap: () => _openScreen(sheetContext, const MarketsScreen()),
              ),
              const Divider(color: Colors.white24),
              const _SectionHeader('Practice & Analysis'),
              ListTile(
                leading: const Icon(Icons.extension),
                title: const Text('Daily Puzzle'),
                onTap: () => _openScreen(sheetContext, const DailyPuzzleScreen()),
              ),
              ListTile(
                leading: const Icon(Icons.history),
                title: const Text('Market Replay'),
                onTap: () => _openScreen(sheetContext, const MarketReplayScreen()),
              ),
              ListTile(
                leading: const Icon(Icons.query_stats),
                title: const Text('Backtester'),
                onTap: () => _openScreen(sheetContext, const BacktesterScreen()),
              ),
              ListTile(
                leading: const Icon(Icons.history_toggle_off),
                title: const Text('What-If Time Machine'),
                onTap: () => _openScreen(sheetContext, const WhatIfScreen()),
              ),
              const Divider(color: Colors.white24),
              const _SectionHeader('Community & Progress'),
              ListTile(
                leading: const Icon(Icons.forum),
                title: const Text('Community Chat'),
                onTap: () => _openScreen(sheetContext, const CommunityChatScreen()),
              ),
              ListTile(
                leading: const Icon(Icons.leaderboard),
                title: const Text('Leaderboard'),
                onTap: () => _openScreen(sheetContext, const LeaderboardScreen()),
              ),
              ListTile(
                leading: const Icon(Icons.people_outline),
                title: const Text('Following'),
                onTap: () => _openScreen(sheetContext, const FollowingFeedScreen()),
              ),
              ListTile(
                leading: const Icon(Icons.workspace_premium),
                title: const Text('Certifications'),
                onTap: () => _openScreen(sheetContext, const CertificateScreen()),
              ),
              const Divider(color: Colors.white24),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Sign out'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  ref.read(authRepositoryProvider).signOut();
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Color(0xFFEF5350)),
                title: const Text('Delete account', style: TextStyle(color: Color(0xFFEF5350))),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _confirmAndDelete(context, ref);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: Colors.white38,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
