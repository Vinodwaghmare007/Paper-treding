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

/// Live valuations for every held position, priced against the live
/// BTCUSDT ticker where the symbol matches (this app currently only trades
/// BTCUSDT), falling back to the stored average buy price — and therefore
/// zero unrealized P&L — for any other symbol so the UI never stalls
/// waiting on a feed it doesn't have.
final positionValuationsProvider = Provider<List<PositionValuation>>((ref) {
  final positions = ref.watch(portfolioStreamProvider).valueOrNull ?? const [];
  final liveTick = ref.watch(klineTickProvider).valueOrNull;

  return [
    for (final position in positions)
      PositionValuation(
        position: position,
        currentPrice: (liveTick != null && position.coinSymbol == liveTick.symbol)
            ? liveTick.candle.close
            : position.avgBuyPrice,
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
