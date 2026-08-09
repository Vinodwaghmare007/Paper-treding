import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../news/news_feed_screen.dart';
import '../orders/order_history_screen.dart';
import '../portfolio/portfolio_screen.dart';
import '../ticker/ticker_screen.dart';
import 'home_deep_link.dart';
import 'simulated_footer.dart';

/// Signed-in app shell: bottom-nav between the 4 screens people open every
/// session — live chart, order history, News, and Portfolio. Everything
/// else (Backtester, Market Replay, Community chat, Daily Puzzle, What-If
/// Time Machine, Certifications, Leaderboard, Following feed) lives one tap
/// away behind the "More" menu (see MoreMenuButton) so the primary nav
/// stays scannable instead of listing 12 destinations. Each of the 4 tabs
/// owns its own app bar, with the More menu as its account/overflow action.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = chartTabIndex;

  static const _tabs = [
    TickerScreen(),
    OrderHistoryScreen(),
    NewsFeedScreen(),
    PortfolioScreen(),
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
          NavigationDestination(
              icon: Icon(Icons.receipt_long), label: 'Orders'),
          NavigationDestination(icon: Icon(Icons.article), label: 'News'),
          NavigationDestination(icon: Icon(Icons.pie_chart), label: 'Portfolio'),
        ],
      ),
    );
  }
}
