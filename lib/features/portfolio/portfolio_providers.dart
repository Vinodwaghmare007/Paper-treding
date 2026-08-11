import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/sources/binance_combined_stream_service.dart';
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

/// Every held coin that ISN'T the one currently open on the chart — that
/// one already gets a free, more frequent price from [klineTickProvider]'s
/// live WebSocket tick. Reactive (not polled): recomputes whenever the
/// portfolio or the active chart symbol changes.
final heldSymbolsProvider = Provider<Set<String>>((ref) {
  final positions = ref.watch(portfolioStreamProvider).valueOrNull ?? const [];
  final activeSymbol = ref.watch(selectedCoinProvider);
  return {
    for (final p in positions)
      if (p.coinSymbol != activeSymbol) p.coinSymbol,
  };
});

/// Owns the combined-stream WebSocket lifecycle for [heldSymbolsProvider] —
/// rebuilt (old socket torn down, new one opened with the new symbol set)
/// whenever a position is opened/closed or the active chart coin changes.
/// Null with no connection at all when there's nothing to price yet (no
/// holdings besides the active chart coin).
final heldCoinPriceServiceProvider = Provider<BinanceCombinedStreamService?>((ref) {
  final symbols = ref.watch(heldSymbolsProvider);
  if (symbols.isEmpty) return null;
  final service = BinanceCombinedStreamService(symbols: symbols);
  service.start();
  ref.onDispose(service.dispose);
  return service;
});

/// Live last price for every held coin that isn't the active chart symbol —
/// see heldSymbolsProvider. One Binance WebSocket connection covers every
/// distinct held symbol via the combined-stream endpoint (see
/// binance_combined_stream_service.dart), replacing what used to be a 15s
/// REST poll with sub-second updates at the same one-connection cost.
/// Starts empty and fills in as ticks arrive rather than blocking on the
/// first one, so the portfolio screen never waits on this.
final heldCoinPricesProvider = StreamProvider<Map<String, double>>((ref) {
  final service = ref.watch(heldCoinPriceServiceProvider);
  if (service == null) return Stream.value(const {});
  return service.prices;
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
