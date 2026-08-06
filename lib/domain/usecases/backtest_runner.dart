import 'dart:async';
import 'dart:isolate';

import '../../data/models/kline_tick.dart';
import '../entities/backtest_condition.dart';
import '../entities/order.dart';
import '../entities/portfolio_position.dart';
import '../entities/user_account.dart';
import 'indicator_calculator.dart';
import 'trade_exceptions.dart';
import 'trade_math.dart';

const _backtestUid = 'backtest';
const _backtestSymbol = 'BACKTEST';

/// What to run: a condition tree evaluated candle-by-candle against
/// [candles], sized as a fixed [positionSizePercent] of the *current*
/// virtual balance per trade.
///
/// Entry/exit rule: the same condition tree drives both — go long when it's
/// true and the strategy is flat, close the position when it turns false
/// again. This keeps v1 to one condition tree (matching the simplified,
/// non-node-editor UI) rather than requiring separate entry and exit trees.
class BacktestRequest {
  const BacktestRequest({
    required this.condition,
    required this.candles,
    this.startingBalance = 100000,
    this.positionSizePercent = 10,
  });

  final BacktestCondition condition;
  final List<Candle> candles;
  final double startingBalance;
  final double positionSizePercent;
}

class SimulatedTrade {
  const SimulatedTrade({required this.order, required this.candleIndex});
  final Order order;
  final int candleIndex;
}

class EquityPoint {
  const EquityPoint({required this.timestamp, required this.portfolioValue});
  final DateTime timestamp;
  final double portfolioValue;
}

class BacktestResult {
  const BacktestResult({
    required this.trades,
    required this.totalPnl,
    required this.winRate,
    required this.maxDrawdownPercent,
    required this.equityCurve,
    required this.finalBalance,
  });

  final List<SimulatedTrade> trades;
  final double totalPnl;

  /// Fraction (0..1) of SELL trades with positive realized P&L. Null if no
  /// trades closed at all (nothing to score a win rate on).
  final double? winRate;
  final double maxDrawdownPercent;
  final List<EquityPoint> equityCurve;
  final double finalBalance;

  int get sellCount => trades.where((t) => t.order.orderType == OrderType.sell).length;
}

sealed class BacktestProgress {
  const BacktestProgress();
}

class BacktestRunning extends BacktestProgress {
  const BacktestRunning(this.fraction);
  final double fraction;
}

class BacktestComplete extends BacktestProgress {
  const BacktestComplete(this.result);
  final BacktestResult result;
}

class BacktestFailed extends BacktestProgress {
  const BacktestFailed(this.message);
  final String message;
}

/// Runs [BacktestRequest]s on a background isolate — walking months of 1m
/// candles through indicator calculation and a trade-by-trade simulation is
/// too much CPU work to do on the UI isolate without dropping frames.
class BacktestRunner {
  Stream<BacktestProgress> run(BacktestRequest request) {
    late final StreamController<BacktestProgress> controller;
    ReceivePort? receivePort;
    Isolate? isolate;

    Future<void> start() async {
      receivePort = ReceivePort();
      try {
        isolate = await Isolate.spawn(
          _backtestIsolateEntryPoint,
          _IsolateRequest(request, receivePort!.sendPort),
          onError: receivePort!.sendPort,
          onExit: receivePort!.sendPort,
        );
      } catch (e) {
        controller.add(BacktestFailed('Could not start backtest isolate: $e'));
        await controller.close();
        return;
      }

      await for (final message in receivePort!) {
        if (message is double) {
          controller.add(BacktestRunning(message));
        } else if (message is BacktestResult) {
          controller.add(BacktestComplete(message));
          break;
        } else if (message is String) {
          controller.add(BacktestFailed(message));
          break;
        } else if (message == null) {
          // Isolate exited (onExit) without an explicit result/error — only
          // reachable if it was killed externally.
          controller.add(const BacktestFailed('Backtest isolate exited unexpectedly.'));
          break;
        } else if (message is List) {
          // onError delivers [errorMessage, stackTrace].
          controller.add(BacktestFailed('Backtest failed: ${message.first}'));
          break;
        }
      }
    }

    controller = StreamController<BacktestProgress>(
      onListen: () {
        start().whenComplete(() {
          receivePort?.close();
          isolate?.kill(priority: Isolate.immediate);
          if (!controller.isClosed) controller.close();
        });
      },
    );
    return controller.stream;
  }
}

class _IsolateRequest {
  const _IsolateRequest(this.request, this.sendPort);
  final BacktestRequest request;
  final SendPort sendPort;
}

/// Isolate entry point — must be a top-level function. Runs the simulation
/// synchronously on the new isolate and reports progress/result/errors back
/// over [_IsolateRequest.sendPort].
void _backtestIsolateEntryPoint(_IsolateRequest message) {
  try {
    final result = executeBacktest(
      message.request,
      onProgress: (fraction) => message.sendPort.send(fraction),
    );
    message.sendPort.send(result);
  } catch (e) {
    message.sendPort.send('Backtest failed: $e');
  }
}

/// The actual simulation, factored out from the isolate plumbing so it can
/// also be unit-tested directly on the main isolate (no Isolate.spawn
/// needed just to check the math).
BacktestResult executeBacktest(
  BacktestRequest request, {
  void Function(double fraction)? onProgress,
}) {
  final candles = request.candles;
  final closePrices = List<double>.generate(candles.length, (i) => candles[i].close);

  final requirements = <IndicatorRequirement>{};
  request.condition.collectRequirements(requirements);
  final bundle = IndicatorBundle(
    closePrices: closePrices,
    series: _buildIndicatorSeries(closePrices, requirements),
  );

  var account = UserAccount(
    uid: _backtestUid,
    virtualBalance: request.startingBalance,
    consecutiveLosses: 0,
  );
  PortfolioPosition? position;
  final trades = <SimulatedTrade>[];
  final equityCurve = <EquityPoint>[];

  final reportEvery = (candles.length / 100).ceil().clamp(1, candles.length);
  final sampleEvery = (candles.length / 1000).ceil().clamp(1, candles.length);
  var peakValue = account.virtualBalance;
  var maxDrawdownPercent = 0.0;
  var orderCounter = 0;

  for (var i = 0; i < candles.length; i++) {
    final candle = candles[i];
    final signal = request.condition.evaluate(bundle, i);

    if (signal && position == null) {
      final spend = account.virtualBalance * request.positionSizePercent / 100;
      final quantity = spend / candle.close;
      if (quantity > 0) {
        try {
          final outcome = TradeMath.applyBuy(
            account: account,
            existingPosition: null,
            coinSymbol: _backtestSymbol,
            price: candle.close,
            quantity: quantity,
            now: DateTime.fromMillisecondsSinceEpoch(candle.openTimeMs, isUtc: true),
            orderId: 'bt-${orderCounter++}',
          );
          account = outcome.updatedAccount;
          position = outcome.updatedPosition;
          trades.add(SimulatedTrade(order: outcome.order, candleIndex: i));
        } on TradeRejected {
          // Insufficient balance for this sizing at this price — skip the
          // signal rather than crash the whole run.
        }
      }
    } else if (!signal && position != null) {
      final outcome = TradeMath.applySell(
        account: account,
        existingPosition: position,
        coinSymbol: _backtestSymbol,
        price: candle.close,
        quantity: position.totalQuantity,
        now: DateTime.fromMillisecondsSinceEpoch(candle.openTimeMs, isUtc: true),
        orderId: 'bt-${orderCounter++}',
      );
      account = outcome.updatedAccount;
      position = outcome.updatedPosition;
      trades.add(SimulatedTrade(order: outcome.order, candleIndex: i));
    }

    final portfolioValue =
        account.virtualBalance + (position?.marketValue(candle.close) ?? 0);
    if (portfolioValue > peakValue) peakValue = portfolioValue;
    if (peakValue > 0) {
      final drawdown = (peakValue - portfolioValue) / peakValue * 100;
      if (drawdown > maxDrawdownPercent) maxDrawdownPercent = drawdown;
    }

    if (i % sampleEvery == 0 || i == candles.length - 1) {
      equityCurve.add(EquityPoint(
        timestamp: DateTime.fromMillisecondsSinceEpoch(candle.openTimeMs, isUtc: true),
        portfolioValue: portfolioValue,
      ));
    }
    if (i % reportEvery == 0) onProgress?.call(i / candles.length);
  }

  // Force-close a still-open position at the last candle so the reported
  // result is always a fully realized outcome, never an ambiguous "still
  // holding" state.
  if (position != null && candles.isNotEmpty) {
    final lastCandle = candles.last;
    final outcome = TradeMath.applySell(
      account: account,
      existingPosition: position,
      coinSymbol: _backtestSymbol,
      price: lastCandle.close,
      quantity: position.totalQuantity,
      now: DateTime.fromMillisecondsSinceEpoch(lastCandle.openTimeMs, isUtc: true),
      orderId: 'bt-${orderCounter++}',
    );
    account = outcome.updatedAccount;
    trades.add(SimulatedTrade(order: outcome.order, candleIndex: candles.length - 1));
  }

  onProgress?.call(1.0);

  final sellTrades = trades.where((t) => t.order.orderType == OrderType.sell).toList();
  final winningSells = sellTrades.where((t) => (t.order.realizedPnl ?? 0) > 0).length;

  return BacktestResult(
    trades: trades,
    totalPnl: account.virtualBalance - request.startingBalance,
    winRate: sellTrades.isEmpty ? null : winningSells / sellTrades.length,
    maxDrawdownPercent: maxDrawdownPercent,
    equityCurve: equityCurve,
    finalBalance: account.virtualBalance,
  );
}

Map<IndicatorRequirement, List<double>> _buildIndicatorSeries(
  List<double> closePrices,
  Set<IndicatorRequirement> requirements,
) {
  final series = <IndicatorRequirement, List<double>>{};
  final handledMacdConfigs = <String>{};

  for (final requirement in requirements) {
    switch (requirement) {
      case RsiRequirement(:final period):
        series[requirement] = calculateRSI(closePrices, period);
      case SmaRequirement(:final period):
        series[requirement] = calculateSMA(closePrices, period);
      case MacdLineRequirement(:final fastPeriod, :final slowPeriod, :final signalPeriod):
      case MacdSignalRequirement(:final fastPeriod, :final slowPeriod, :final signalPeriod):
        final configKey = '$fastPeriod-$slowPeriod-$signalPeriod';
        if (handledMacdConfigs.add(configKey)) {
          final macd = calculateMACD(
            closePrices,
            fastPeriod: fastPeriod,
            slowPeriod: slowPeriod,
            signalPeriod: signalPeriod,
          );
          series[MacdLineRequirement(
              fastPeriod: fastPeriod, slowPeriod: slowPeriod, signalPeriod: signalPeriod)] = macd.macdLine;
          series[MacdSignalRequirement(
              fastPeriod: fastPeriod, slowPeriod: slowPeriod, signalPeriod: signalPeriod)] = macd.signalLine;
        }
    }
  }
  return series;
}
