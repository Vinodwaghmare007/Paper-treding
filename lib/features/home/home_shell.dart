import 'package:flutter/material.dart';

import '../backtester/backtester_screen.dart';
import '../orders/order_history_screen.dart';
import '../portfolio/portfolio_screen.dart';
import '../replay/market_replay_screen.dart';
import '../ticker/ticker_screen.dart';

/// Signed-in app shell: bottom-nav between the live chart, portfolio, order
/// history, strategy backtester, and Market Replay. Each tab owns its own
/// app bar (with a sign-out action).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _tabs = [
    TickerScreen(),
    PortfolioScreen(),
    OrderHistoryScreen(),
    BacktesterScreen(),
    MarketReplayScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
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
        ],
      ),
    );
  }
}
