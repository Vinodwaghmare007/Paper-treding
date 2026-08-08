import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backtester/backtester_screen.dart';
import '../certifications/certificate_screen.dart';
import '../chat/community_chat_screen.dart';
import '../news/news_feed_screen.dart';
import '../orders/order_history_screen.dart';
import '../portfolio/portfolio_screen.dart';
import '../puzzle/daily_puzzle_screen.dart';
import '../replay/market_replay_screen.dart';
import '../ticker/ticker_screen.dart';
import '../whatif/whatif_screen.dart';
import 'home_deep_link.dart';
import 'simulated_footer.dart';

/// Signed-in app shell: bottom-nav between the live chart, portfolio, order
/// history, strategy backtester, Market Replay, Community chat, News, the
/// Daily Puzzle, the What-If Time Machine, and Certifications. Each tab
/// owns its own app bar (with a sign-out action).
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = chartTabIndex;

  static const _tabs = [
    TickerScreen(),
    PortfolioScreen(),
    OrderHistoryScreen(),
    BacktesterScreen(),
    MarketReplayScreen(),
    CommunityChatScreen(),
    NewsFeedScreen(),
    DailyPuzzleScreen(),
    WhatIfScreen(),
    CertificateScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    ref.listen<int?>(pendingDeepLinkTabProvider, (_, tab) {
      if (tab == null) return;
      setState(() => _index = tab);
      ref.read(pendingDeepLinkTabProvider.notifier).state = null;
    });

    return Scaffold(
      body: Column(
        children: [
          Expanded(child: IndexedStack(index: _index, children: _tabs)),
          const SimulatedFooter(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        backgroundColor: const Color(0xFF1E222D),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.candlestick_chart), label: 'Chart'),
          NavigationDestination(icon: Icon(Icons.pie_chart), label: 'Portfolio'),
          NavigationDestination(
              icon: Icon(Icons.receipt_long), label: 'Orders'),
          NavigationDestination(
              icon: Icon(Icons.query_stats), label: 'Backtest'),
          NavigationDestination(icon: Icon(Icons.history), label: 'Replay'),
          NavigationDestination(icon: Icon(Icons.forum), label: 'Chat'),
          NavigationDestination(icon: Icon(Icons.article), label: 'News'),
          NavigationDestination(icon: Icon(Icons.extension), label: 'Puzzle'),
          NavigationDestination(
              icon: Icon(Icons.history_toggle_off), label: 'What-If'),
          NavigationDestination(
              icon: Icon(Icons.workspace_premium), label: 'Certs'),
        ],
      ),
    );
  }
}
