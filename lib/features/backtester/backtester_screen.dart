import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/sources/binance_rest_service.dart';
import '../../domain/entities/backtest_condition.dart';
import '../../domain/entities/order.dart';
import '../../domain/usecases/backtest_runner.dart';
import '../ticker/ticker_providers.dart';
import 'equity_curve_chart.dart';

enum _IndicatorKind { rsiThreshold, rsiCrosses, macdCrosses, priceCrossesSma }

extension on _IndicatorKind {
  String get label => switch (this) {
        _IndicatorKind.rsiThreshold => 'RSI level',
        _IndicatorKind.rsiCrosses => 'RSI crosses',
        _IndicatorKind.macdCrosses => 'MACD crosses signal',
        _IndicatorKind.priceCrossesSma => 'Price crosses SMA',
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
    final range = _dateRange;
    if (range == null) {
      setState(() {
        _phase = _RunPhase.error;
        _errorMessage = 'Pick a date range first.';
      });
      return;
    }
    if (_conditions.isEmpty) {
      setState(() {
        _phase = _RunPhase.error;
        _errorMessage = 'Add at least one condition.';
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
        symbol: 'BTCUSDT',
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
          _errorMessage =
              'Only ${candles.length} candles in that range — pick a wider range or a shorter interval.';
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
        _errorMessage = 'Could not fetch historical data: ${e.message}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRunning = _phase == _RunPhase.fetchingData || _phase == _RunPhase.running;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E222D),
        title: const Text('Strategy Backtester'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionCard(
            title: 'Data',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Text('BTCUSDT', style: TextStyle(color: Colors.white70)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _interval,
                        dropdownColor: const Color(0xFF1E222D),
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(labelText: 'Interval', isDense: true),
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
                        ? 'Pick date range'
                        : '${_fmtDate(_dateRange!.start)} — ${_fmtDate(_dateRange!.end)}',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Position sizing',
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: _startingBalance.toStringAsFixed(0),
                    enabled: !isRunning,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(labelText: 'Starting balance', isDense: true),
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
                    decoration: const InputDecoration(labelText: '% of balance / trade', isDense: true),
                    onChanged: (v) => _positionSizePercent = double.tryParse(v) ?? _positionSizePercent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Entry / exit condition',
            subtitle: 'Long while true, flat while false.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_conditions.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: true, label: Text('AND')),
                        ButtonSegment(value: false, label: Text('OR')),
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
                    label: const Text('Add condition'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: isRunning ? null : _runBacktest,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: Text(isRunning ? 'Running…' : 'Run Backtest'),
          ),
          if (_phase == _RunPhase.fetchingData) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
            const SizedBox(height: 6),
            Text('Fetching historical data… $_fetchedCandleCount candles',
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ],
          if (_phase == _RunPhase.running) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: _backtestProgress),
            const SizedBox(height: 6),
            Text('Running backtest… ${(_backtestProgress * 100).toStringAsFixed(0)}%',
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
                      .map((k) => DropdownMenuItem(value: k, child: Text(k.label)))
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
                  onPressed: enabled ? onRemove : null,
                ),
            ],
          ),
          Row(
            children: [
              if (draft.kind != _IndicatorKind.macdCrosses) ...[
                Expanded(
                  child: _NumberField(
                    label: 'Period',
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
                    decoration: const InputDecoration(isDense: true, labelText: 'vs'),
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
                    label: 'Threshold',
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
                    label: 'Threshold',
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
    return DropdownButtonFormField<CrossDirection>(
      value: draft.direction,
      dropdownColor: const Color(0xFF1E222D),
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: const InputDecoration(isDense: true, labelText: 'Direction'),
      items: const [
        DropdownMenuItem(value: CrossDirection.up, child: Text('Crosses UP')),
        DropdownMenuItem(value: CrossDirection.down, child: Text('Crosses DOWN')),
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
    final pnlColor = result.totalPnl >= 0 ? const Color(0xFF26A69A) : const Color(0xFFEF5350);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Results', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatTile(
                label: 'Total P&L',
                value: '${result.totalPnl >= 0 ? '+' : ''}${result.totalPnl.toStringAsFixed(2)}',
                color: pnlColor,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatTile(
                label: 'Win rate',
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
                label: 'Max drawdown',
                value: '${result.maxDrawdownPercent.toStringAsFixed(2)}%',
                color: const Color(0xFFEF5350),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatTile(
                label: 'Closed trades',
                value: '${result.sellCount}',
              ),
            ),
          ],
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
        const Text('Trades', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
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
