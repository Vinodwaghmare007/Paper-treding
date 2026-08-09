import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/sources/first_trade_tracker.dart';
import '../../domain/entities/cohort_median.dart';
import '../../domain/entities/order.dart';
import '../../domain/entities/portfolio_position.dart';
import '../../domain/entities/user_account.dart';
import '../../domain/usecases/cohort_key.dart';
import '../../domain/usecases/execute_trade.dart';
import '../../data/repositories/cohort_repository.dart';
import '../../data/repositories/trading_repository.dart';
import '../auth/auth_providers.dart';
import '../ticker/ticker_providers.dart';

final tradingRepositoryProvider = Provider<TradingRepository>((ref) {
  return TradingRepository(ref.watch(firebaseFirestoreProvider));
});

final cohortRepositoryProvider = Provider<CohortRepository>((ref) {
  return CohortRepository(ref.watch(firebaseFirestoreProvider));
});

final firstTradeTrackerProvider = Provider<FirstTradeTracker>((ref) => FirstTradeTracker());

/// Requires a signed-in user — only meant to be watched beneath [AuthGate].
String _uidOrThrow(Ref ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) {
    throw StateError('accountStreamProvider read outside of AuthGate');
  }
  return uid;
}

final accountStreamProvider = StreamProvider<UserAccount>((ref) {
  final uid = _uidOrThrow(ref);
  return ref.watch(tradingRepositoryProvider).watchAccount(uid);
});

final portfolioStreamProvider = StreamProvider<List<PortfolioPosition>>((ref) {
  final uid = _uidOrThrow(ref);
  return ref.watch(tradingRepositoryProvider).watchPortfolio(uid);
});

final orderHistoryStreamProvider = StreamProvider<List<Order>>((ref) {
  final uid = _uidOrThrow(ref);
  return ref.watch(tradingRepositoryProvider).watchOrders(uid);
});

/// Batch-polled last price (every 15s) for every held coin that ISN'T the
/// one currently open on the chart — that one already gets a free, more
/// frequent price from [klineTickProvider]'s live WebSocket tick. Cheap
/// even for a large portfolio: one Binance REST call covers every distinct
/// symbol. Starts empty and fills in after the first poll rather than
/// blocking on it, so the portfolio screen never waits on this.
final heldCoinPricesProvider = StreamProvider<Map<String, double>>((ref) async* {
  final rest = ref.watch(binanceRestServiceProvider);
  var lastPrices = const <String, double>{};
  yield lastPrices;

  await for (final _ in Stream<int>.periodic(const Duration(seconds: 15), (i) => i)) {
    final positions = ref.read(portfolioStreamProvider).valueOrNull ?? const [];
    final activeSymbol = ref.read(selectedCoinProvider);
    final symbols = {
      for (final p in positions)
        if (p.coinSymbol != activeSymbol) p.coinSymbol,
    }.toList(growable: false);
    if (symbols.isEmpty) {
      lastPrices = const {};
    } else {
      final fetched = await rest.fetchPrices(symbols: symbols);
      // A failed poll (empty map) keeps the previous prices rather than
      // blanking everything back to the avgBuyPrice fallback for one cycle.
      if (fetched.isNotEmpty) lastPrices = fetched;
    }
    yield lastPrices;
  }
});

final executeTradeUseCaseProvider = Provider<ExecuteTradeUseCase>((ref) {
  final uid = _uidOrThrow(ref);
  return ref.watch(tradingRepositoryProvider).tradeEngineFor(uid);
});

/// Live valuation of one portfolio position at the current market price.
class PositionValuation {
  const PositionValuation({
    required this.position,
    required this.currentPrice,
  });

  final PortfolioPosition position;
  final double currentPrice;

  double get marketValue => position.marketValue(currentPrice);
  double get unrealizedPnl => position.unrealizedPnl(currentPrice);
  double get unrealizedPnlPercent => position.avgBuyPrice == 0
      ? 0
      : (currentPrice - position.avgBuyPrice) / position.avgBuyPrice * 100;
}

/// Live valuations for every held position: the coin currently open on the
/// chart gets its price from the live WebSocket tick (sub-second), every
/// other held coin gets its price from [heldCoinPricesProvider]'s 15s
/// REST poll, and only a coin with neither (freshly held, first poll not
/// back yet) falls back to the stored average buy price — and therefore
/// zero unrealized P&L — so the UI never stalls waiting on a feed it
/// doesn't have data for yet.
final positionValuationsProvider = Provider<List<PositionValuation>>((ref) {
  final positions = ref.watch(portfolioStreamProvider).valueOrNull ?? const [];
  final liveTick = ref.watch(klineTickProvider).valueOrNull;
  final polledPrices = ref.watch(heldCoinPricesProvider).valueOrNull ?? const {};

  return [
    for (final position in positions)
      PositionValuation(
        position: position,
        currentPrice: (liveTick != null && position.coinSymbol == liveTick.symbol)
            ? liveTick.candle.close
            : polledPrices[position.coinSymbol] ?? position.avgBuyPrice,
      ),
  ];
});

/// virtual_balance + the live market value of every holding.
final totalAccountValueProvider = Provider<double>((ref) {
  final account = ref.watch(accountStreamProvider).valueOrNull;
  final valuations = ref.watch(positionValuationsProvider);
  final holdingsValue =
      valuations.fold<double>(0, (sum, v) => sum + v.marketValue);
  return (account?.virtualBalance ?? 0) + holdingsValue;
});

/// Null if the account has no `createdAt` yet (matches [cohortKeyFor] —
/// pre-cohort-feature accounts and the cohort itself both get skipped the
/// same way the server does).
final myCohortKeyProvider = Provider<String?>((ref) {
  final account = ref.watch(accountStreamProvider).valueOrNull;
  if (account == null) return null;
  return cohortKeyFor(
    createdAt: account.createdAt,
    startingBalance: account.startingBalance,
  );
});

final cohortMedianProvider = StreamProvider<CohortMedian?>((ref) {
  final cohortKey = ref.watch(myCohortKeyProvider);
  if (cohortKey == null) return Stream.value(null);
  return ref.watch(cohortRepositoryProvider).watchCohortMedian(cohortKey);
});
