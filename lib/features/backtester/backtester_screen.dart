import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/entities/supported_coin.dart';
import '../../data/sources/binance_rest_service.dart';
import '../../domain/entities/backtest_condition.dart';
import '../../domain/entities/order.dart';
import '../../domain/usecases/backtest_runner.dart';
import '../../domain/usecases/risk_metrics_calculator.dart';
import '../../l10n/generated/app_localizations.dart';
import '../auth/auth_providers.dart';
import '../certifications/certification_providers.dart';
import '../ticker/ticker_providers.dart';
import 'equity_curve_chart.dart';

enum _IndicatorKind { rsiThreshold, rsiCrosses, macdCrosses, priceCrossesSma }

extension on _IndicatorKind {
  String label(AppLocalizations l10n) => switch (this) {
        _IndicatorKind.rsiThreshold => l10n.backtesterIndicatorRsiLevel,
        _IndicatorKind.rsiCrosses => l10n.backtesterIndicatorRsiCrosses,
        _IndicatorKind.macdCrosses => l10n.backtesterIndicatorMacdCrosses,
        _IndicatorKind.priceCrossesSma => l10n.backtesterIndicatorPriceCrossesSma,
      };
}

/// Mutable UI-side draft for one condition row. Converted to an immutable
/// [BacktestCondition] leaf only when the backtest actually runs — kept
/// separate from the domain model so the screen can freely mutate a row
/// (change indicator kind, period, etc.) without the domain tree needing
/// any mutable state at all.
class _ConditionDraft {
  _IndicatorKind kind = _IndicatorKind.rsiThreshold;
  int period = 14;
  ComparisonOperator comparisonOperator = ComparisonOperator.lessThan;
  CrossDirection direction = CrossDirection.up;
  double threshold = 30;

  BacktestCondition toCondition() => switch (kind) {
        _IndicatorKind.rsiThreshold => RsiThresholdCondition(
            period: period, comparisonOperator: comparisonOperator, threshold: threshold),
        _IndicatorKind.rsiCrosses =>
          RsiCrossesThresholdCondition(period: period, direction: direction, threshold: threshold),
        _IndicatorKind.macdCrosses => MacdCrossCondition(direction: direction),
        _IndicatorKind.priceCrossesSma => PriceCrossesSmaCondition(period: period, direction: direction),
      };
}

enum _RunPhase { idle, fetchingData, running, done, error }

class BacktesterScreen extends ConsumerStatefulWidget {
  const BacktesterScreen({super.key});

  @override
  ConsumerState<BacktesterScreen> createState() => _BacktesterScreenState();
}

class _BacktesterScreenState extends ConsumerState<BacktesterScreen> {
  final List<_ConditionDraft> _conditions = [_ConditionDraft()];
  bool _combineWithAnd = true;
  String _symbol = 'BTCUSDT';
  String _interval = '1m';
  DateTimeRange? _dateRange;
  double _startingBalance = 100000;
  double _positionSizePercent = 10;

  _RunPhase _phase = _RunPhase.idle;
  int _fetchedCandleCount = 0;
  double _backtestProgress = 0;
  BacktestResult? _result;
  String? _errorMessage;

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2018),
      lastDate: now,
      initialDateRange: _dateRange ??
          DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now),
    );
    if (picked != null) setState(() => _dateRange = picked);
  }

  Future<void> _runBacktest() async {
    final l10n = AppLocalizations.of(context)!;
    final range = _dateRange;
    if (range == null) {
      setState(() {
        _phase = _RunPhase.error;
        _errorMessage = l10n.backtesterNoDateRangeError;
      });
      return;
    }
    if (_conditions.isEmpty) {
      setState(() {
        _phase = _RunPhase.error;
        _errorMessage = l10n.backtesterNoConditionError;
      });
      return;
    }

    setState(() {
      _phase = _RunPhase.fetchingData;
      _fetchedCandleCount = 0;
      _errorMessage = null;
      _result = null;
    });

    final restService = ref.read(binanceRestServiceProvider);
    try {
      final candles = await restService.fetchKlinesRange(
        symbol: _symbol,
        interval: _interval,
        start: range.start,
        end: range.end,
        onProgress: (count) {
          if (mounted) setState(() => _fetchedCandleCount = count);
        },
      );

      if (candles.length < 30) {
        setState(() {
          _phase = _RunPhase.error;
          _errorMessage = l10n.backtesterInsufficientCandles(candles.length);
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _phase = _RunPhase.running;
        _backtestProgress = 0;
      });

      final children = _conditions.map((c) => c.toCondition()).toList();
      final condition = children.length == 1
          ? children.single
          : (_combineWithAnd ? AndCondition(children) : OrCondition(children));

      final request = BacktestRequest(
        condition: condition,
        candles: candles,
        startingBalance: _startingBalance,
        positionSizePercent: _positionSizePercent,
      );

      await for (final progress in BacktestRunner().run(request)) {
        if (!mounted) return;
        switch (progress) {
          case BacktestRunning(:final fraction):
            setState(() => _backtestProgress = fraction);
          case BacktestComplete(:final result):
            setState(() {
              _phase = _RunPhase.done;
              _result = result;
            });
            unawaited(ref
                .read(analyticsServiceProvider)
                .logBacktestRun(closedTrades: result.sellCount));
            unawaited(
                ref.read(certificationRepositoryProvider).recordBacktestCompletion());
          case BacktestFailed(:final message):
            setState(() {
              _phase = _RunPhase.error;
              _errorMessage = message;
            });
        }
      }
    } on BinanceRestException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _RunPhase.error;
        _errorMessage = l10n.backtesterFetchError(e.message);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isRunning = _phase == _RunPhase.fetchingData || _phase == _RunPhase.running;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E222D),
        title: Text(l10n.backtesterTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionCard(
            title: l10n.backtesterDataSectionTitle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _symbol,
                        dropdownColor: const Color(0xFF1E222D),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(labelText: l10n.coinFieldLabel, isDense: true),
                        items: [
                          for (final coin in supportedCoins)
                            DropdownMenuItem(value: coin.symbol, child: Text(coin.baseAsset)),
                        ],
                        onChanged: isRunning ? null : (v) => setState(() => _symbol = v ?? _symbol),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _interval,
                        dropdownColor: const Color(0xFF1E222D),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(labelText: l10n.backtesterIntervalLabel, isDense: true),
                        items: const ['1m', '5m', '15m', '1h', '4h', '1d']
                            .map((i) => DropdownMenuItem(value: i, child: Text(i)))
                            .toList(),
                        onChanged: isRunning ? null : (v) => setState(() => _interval = v ?? _interval),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: isRunning ? null : _pickDateRange,
                  icon: const Icon(Icons.date_range),
                  label: Text(
                    _dateRange == null
                        ? l10n.backtesterPickDateRange
                        : '${_fmtDate(_dateRange!.start)} — ${_fmtDate(_dateRange!.end)}',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: l10n.backtesterPositionSizingTitle,
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: _startingBalance.toStringAsFixed(0),
                    enabled: !isRunning,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(labelText: l10n.backtesterStartingBalanceLabel, isDense: true),
                    onChanged: (v) => _startingBalance = double.tryParse(v) ?? _startingBalance,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    initialValue: _positionSizePercent.toStringAsFixed(0),
                    enabled: !isRunning,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(labelText: l10n.backtesterPositionSizeLabel, isDense: true),
                    onChanged: (v) => _positionSizePercent = double.tryParse(v) ?? _positionSizePercent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: l10n.backtesterConditionSectionTitle,
            subtitle: l10n.backtesterConditionSectionSubtitle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_conditions.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(value: true, label: Text(l10n.backtesterAndLabel)),
                        ButtonSegment(value: false, label: Text(l10n.backtesterOrLabel)),
                      ],
                      selected: {_combineWithAnd},
                      onSelectionChanged: isRunning
                          ? null
                          : (s) => setState(() => _combineWithAnd = s.first),
                    ),
                  ),
                for (var i = 0; i < _conditions.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _ConditionRow(
                      draft: _conditions[i],
                      enabled: !isRunning,
                      onChanged: () => setState(() {}),
                      onRemove: _conditions.length > 1
                          ? () => setState(() => _conditions.removeAt(i))
                          : null,
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: isRunning
                        ? null
                        : () => setState(() => _conditions.add(_ConditionDraft())),
                    icon: const Icon(Icons.add),
                    label: Text(l10n.backtesterAddCondition),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: isRunning ? null : _runBacktest,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: Text(isRunning ? l10n.backtesterRunningButton : l10n.backtesterRunButton),
          ),
          if (_phase == _RunPhase.fetchingData) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
            const SizedBox(height: 6),
            Text(l10n.backtesterFetchingData(_fetchedCandleCount),
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ],
          if (_phase == _RunPhase.running) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: _backtestProgress),
            const SizedBox(height: 6),
            Text(l10n.backtesterRunningProgress((_backtestProgress * 100).toStringAsFixed(0)),
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ],
          if (_phase == _RunPhase.error && _errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(_errorMessage!, style: const TextStyle(color: Color(0xFFEF5350))),
          ],
          if (_phase == _RunPhase.done && _result != null) ...[
            const SizedBox(height: 24),
            _ResultsSection(result: _result!, startingBalance: _startingBalance),
          ],
        ],
      ),
    );
  }
}

String _fmtDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, this.subtitle, required this.child});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E222D),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(subtitle!, style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _ConditionRow extends StatelessWidget {
  const _ConditionRow({
    required this.draft,
    required this.enabled,
    required this.onChanged,
    required this.onRemove,
  });

  final _ConditionDraft draft;
  final bool enabled;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF131722),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<_IndicatorKind>(
                  value: draft.kind,
                  dropdownColor: const Color(0xFF1E222D),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: const InputDecoration(isDense: true, border: InputBorder.none),
                  items: _IndicatorKind.values
                      .map((k) => DropdownMenuItem(value: k, child: Text(k.label(l10n))))
                      .toList(),
                  onChanged: enabled
                      ? (k) {
                          if (k != null) draft.kind = k;
                          onChanged();
                        }
                      : null,
                ),
              ),
              if (onRemove != null)
                IconButton(
                  icon: const Icon(Icons.close, size: 18, color: Colors.white38),
                  tooltip: l10n.backtesterRemoveConditionTooltip,
                  onPressed: enabled ? onRemove : null,
                ),
            ],
          ),
          Row(
            children: [
              if (draft.kind != _IndicatorKind.macdCrosses) ...[
                Expanded(
                  child: _NumberField(
                    label: l10n.backtesterPeriodLabel,
                    value: draft.period.toDouble(),
                    enabled: enabled,
                    onChanged: (v) {
                      draft.period = v.round().clamp(2, 200);
                      onChanged();
                    },
                  ),
                ),
                const SizedBox(width: 8),
              ],
              if (draft.kind == _IndicatorKind.rsiThreshold) ...[
                Expanded(
                  child: DropdownButtonFormField<ComparisonOperator>(
                    value: draft.comparisonOperator,
                    dropdownColor: const Color(0xFF1E222D),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(isDense: true, labelText: l10n.backtesterVsLabel),
                    items: const [
                      DropdownMenuItem(value: ComparisonOperator.lessThan, child: Text('<')),
                      DropdownMenuItem(value: ComparisonOperator.greaterThan, child: Text('>')),
                    ],
                    onChanged: enabled
                        ? (v) {
                            if (v != null) draft.comparisonOperator = v;
                            onChanged();
                          }
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _NumberField(
                    label: l10n.backtesterThresholdLabel,
                    value: draft.threshold,
                    enabled: enabled,
                    onChanged: (v) {
                      draft.threshold = v;
                      onChanged();
                    },
                  ),
                ),
              ],
              if (draft.kind == _IndicatorKind.rsiCrosses) ...[
                Expanded(child: _DirectionDropdown(draft: draft, enabled: enabled, onChanged: onChanged)),
                const SizedBox(width: 8),
                Expanded(
                  child: _NumberField(
                    label: l10n.backtesterThresholdLabel,
                    value: draft.threshold,
                    enabled: enabled,
                    onChanged: (v) {
                      draft.threshold = v;
                      onChanged();
                    },
                  ),
                ),
              ],
              if (draft.kind == _IndicatorKind.macdCrosses)
                Expanded(child: _DirectionDropdown(draft: draft, enabled: enabled, onChanged: onChanged)),
              if (draft.kind == _IndicatorKind.priceCrossesSma)
                Expanded(child: _DirectionDropdown(draft: draft, enabled: enabled, onChanged: onChanged)),
            ],
          ),
        ],
      ),
    );
  }
}

class _DirectionDropdown extends StatelessWidget {
  const _DirectionDropdown({required this.draft, required this.enabled, required this.onChanged});

  final _ConditionDraft draft;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return DropdownButtonFormField<CrossDirection>(
      value: draft.direction,
      dropdownColor: const Color(0xFF1E222D),
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(isDense: true, labelText: l10n.backtesterDirectionLabel),
      items: [
        DropdownMenuItem(value: CrossDirection.up, child: Text(l10n.backtesterCrossesUp)),
        DropdownMenuItem(value: CrossDirection.down, child: Text(l10n.backtesterCrossesDown)),
      ],
      onChanged: enabled
          ? (v) {
              if (v != null) draft.direction = v;
              onChanged();
            }
          : null,
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: ValueKey('$label-${value.toStringAsFixed(0)}'),
      initialValue: value % 1 == 0 ? value.toStringAsFixed(0) : value.toString(),
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(labelText: label, isDense: true),
      onChanged: (v) {
        final parsed = double.tryParse(v);
        if (parsed != null) onChanged(parsed);
      },
    );
  }
}

class _ResultsSection extends StatelessWidget {
  const _ResultsSection({required this.result, required this.startingBalance});

  final BacktestResult result;
  final double startingBalance;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final pnlColor = result.totalPnl >= 0 ? const Color(0xFF26A69A) : const Color(0xFFEF5350);
    final riskMetrics = computeRiskMetrics(result.equityCurve);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.backtesterResultsTitle,
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          l10n.backtesterResultsDisclaimer,
          // white70 rather than white38: this is safety-relevant copy, and
          // needs to clear WCAG AA contrast against this dark background.
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatTile(
                label: l10n.backtesterTotalPnl,
                value: '${result.totalPnl >= 0 ? '+' : ''}${result.totalPnl.toStringAsFixed(2)}',
                color: pnlColor,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatTile(
                label: l10n.backtesterWinRate,
                value: result.winRate == null ? '—' : '${(result.winRate! * 100).toStringAsFixed(1)}%',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _StatTile(
                label: l10n.backtesterMaxDrawdown,
                value: '${result.maxDrawdownPercent.toStringAsFixed(2)}%',
                color: const Color(0xFFEF5350),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatTile(
                label: l10n.backtesterClosedTrades,
                value: '${result.sellCount}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _StatTile(
                label: l10n.backtesterSharpeRatio,
                value: riskMetrics.sharpeRatio == null
                    ? '—'
                    : riskMetrics.sharpeRatio!.toStringAsFixed(2),
                color: riskMetrics.sharpeRatio == null
                    ? null
                    : (riskMetrics.sharpeRatio! >= 0
                        ? const Color(0xFF26A69A)
                        : const Color(0xFFEF5350)),
              ),
            ),
            const SizedBox(width: 8),
            const Expanded(child: SizedBox.shrink()),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          l10n.backtesterSharpeExplanation,
          style: const TextStyle(color: Colors.white38, fontSize: 10),
        ),
        const SizedBox(height: 16),
        Container(
          height: 200,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E222D),
            borderRadius: BorderRadius.circular(12),
          ),
          child: EquityCurveChart(points: result.equityCurve, startingBalance: startingBalance),
        ),
        const SizedBox(height: 16),
        Text(l10n.backtesterTradesSectionTitle,
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        ...result.trades.map((t) => _TradeTile(trade: t)),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E222D),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(color: color ?? Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _TradeTile extends StatelessWidget {
  const _TradeTile({required this.trade});

  final SimulatedTrade trade;

  @override
  Widget build(BuildContext context) {
    final order = trade.order;
    final isBuy = order.orderType == OrderType.buy;
    final sideColor = isBuy ? const Color(0xFF26A69A) : const Color(0xFFEF5350);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(order.orderType.code, style: TextStyle(color: sideColor, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'qty ${order.quantity.toStringAsFixed(4)} @ ${order.price.toStringAsFixed(2)}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          if (order.realizedPnl != null)
            Text(
              '${order.realizedPnl! >= 0 ? '+' : ''}${order.realizedPnl!.toStringAsFixed(2)}',
              style: TextStyle(
                color: order.realizedPnl! >= 0 ? const Color(0xFF26A69A) : const Color(0xFFEF5350),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}
