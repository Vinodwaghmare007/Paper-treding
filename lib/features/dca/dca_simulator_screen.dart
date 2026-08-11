import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/entities/supported_coin.dart';
import '../../domain/usecases/dca_simulator.dart';
import '../../l10n/generated/app_localizations.dart';
import '../coins/coin_catalog_providers.dart';
import '../settings/currency_providers.dart';
import '../settings/price_text.dart';
import 'dca_providers.dart';
import 'dca_share_card.dart';

/// "If I'd invested ₹500/week in BTC since 2021, I'd have ₹X today" —
/// extends the What-If Time Machine (Phase 5) with a *recurring* purchase
/// schedule instead of a single lump sum, on the exact same 5-year
/// historical data the live chart uses (dca_providers.dart's
/// DcaResultController). Uses fl_chart rather than the TradingView WebView
/// bridge — a simple two-line comparison doesn't need candlesticks.
class DcaSimulatorScreen extends ConsumerStatefulWidget {
  const DcaSimulatorScreen({super.key});

  @override
  ConsumerState<DcaSimulatorScreen> createState() => _DcaSimulatorScreenState();
}

class _DcaSimulatorScreenState extends ConsumerState<DcaSimulatorScreen> {
  final _amountController = TextEditingController(text: '500');
  final _screenshotController = ScreenshotController();
  bool _sharing = false;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _pickDateRange() async {
    final inputs = ref.read(dcaInputsProvider);
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      // The app's historical data (and Market Replay's curated periods)
      // doesn't reach further back than this — see the 5-year chart range.
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: DateTimeRange(start: inputs.startDate, end: inputs.endDate),
    );
    if (picked != null) {
      ref.read(dcaInputsProvider.notifier).state = inputs.copyWith(
        startDate: DateTime.utc(picked.start.year, picked.start.month, picked.start.day),
        endDate: DateTime.utc(picked.end.year, picked.end.month, picked.end.day),
      );
    }
  }

  Future<void> _run() async {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) return;
    ref.read(dcaInputsProvider.notifier).state =
        ref.read(dcaInputsProvider).copyWith(recurringAmount: amount);
    await ref.read(dcaResultProvider.notifier).run();
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final bytes = await _screenshotController.capture(pixelRatio: 2);
      if (bytes == null) return;
      await Share.shareXFiles(
        [XFile.fromData(bytes, mimeType: 'image/png', name: 'dca_simulator.png')],
        text: 'What if I had dollar-cost-averaged into crypto? Try the DCA '
            'Simulator on Crypto Paper Trader (paper trading only — no real '
            'money).',
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final inputs = ref.watch(dcaInputsProvider);
    final resultAsync = ref.watch(dcaResultProvider);
    final coin = coinForSymbol(inputs.symbol);
    final currency = ref.watch(currencyPreferenceProvider);
    final rate = ref.watch(usdToInrRateProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E222D),
        title: Text(l10n.dcaTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _InputsCard(amountController: _amountController, onPickDateRange: _pickDateRange),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: resultAsync.isLoading ? null : _run,
            child: resultAsync.isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(l10n.dcaRunButton),
          ),
          const SizedBox(height: 20),
          resultAsync.when(
            data: (result) {
              if (result == null) return const SizedBox.shrink();
              return _ResultsSection(
                coin: coin,
                result: result,
                frequency: inputs.frequency,
                screenshotController: _screenshotController,
                currency: currency,
                rate: rate,
                sharing: _sharing,
                onShare: _share,
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.dcaSimulationError(e.toString()),
                style: const TextStyle(color: Color(0xFFEF5350)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InputsCard extends ConsumerWidget {
  const _InputsCard({required this.amountController, required this.onPickDateRange});

  final TextEditingController amountController;
  final VoidCallback onPickDateRange;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final inputs = ref.watch(dcaInputsProvider);
    final coins = ref.watch(supportedCoinsProvider).valueOrNull ?? supportedCoins;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E222D),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            value: inputs.symbol,
            dropdownColor: const Color(0xFF1E222D),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(labelText: l10n.coinFieldLabel, isDense: true),
            items: [
              for (final coin in coins)
                DropdownMenuItem(value: coin.symbol, child: Text('${coin.baseAsset} · ${coin.displayName}')),
            ],
            onChanged: (v) {
              if (v != null) {
                ref.read(dcaInputsProvider.notifier).state = inputs.copyWith(symbol: v);
              }
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: l10n.dcaRecurringAmountLabel,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<DcaFrequency>(
            segments: [
              for (final f in DcaFrequency.values) ButtonSegment(value: f, label: Text(f.label)),
            ],
            selected: {inputs.frequency},
            onSelectionChanged: (selection) => ref.read(dcaInputsProvider.notifier).state =
                inputs.copyWith(frequency: selection.first),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onPickDateRange,
            icon: const Icon(Icons.date_range),
            label: Text('${_fmt(inputs.startDate)} — ${_fmt(inputs.endDate)}'),
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class _ResultsSection extends StatelessWidget {
  const _ResultsSection({
    required this.coin,
    required this.result,
    required this.frequency,
    required this.screenshotController,
    required this.currency,
    required this.rate,
    required this.sharing,
    required this.onShare,
  });

  final SupportedCoin coin;
  final DcaResult result;
  final DcaFrequency frequency;
  final ScreenshotController screenshotController;
  final AppCurrency currency;
  final ExchangeRate? rate;
  final bool sharing;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final profit = result.returnPercent >= 0;
    final color = profit ? const Color(0xFF26A69A) : const Color(0xFFEF5350);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _StatTile(label: l10n.dcaTotalInvested, child: PriceText(result.totalInvested)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatTile(
                label: l10n.dcaCurrentValue,
                child: PriceText(result.currentValue, style: TextStyle(color: color)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _StatTile(
          label: l10n.dcaReturnLabel,
          child: Text(
            '${profit ? '+' : ''}${result.returnPercent.toStringAsFixed(2)}%  '
            '(${result.totalUnits.toStringAsFixed(6)} ${coin.baseAsset})',
            style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          height: 220,
          padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
          decoration: BoxDecoration(
            color: const Color(0xFF1E222D),
            borderRadius: BorderRadius.circular(12),
          ),
          child: _DcaLineChart(result: result),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _LegendDot(color: const Color(0xFF6FD3C7), label: l10n.dcaLegendInvested),
            const SizedBox(width: 16),
            _LegendDot(color: const Color(0xFF26A69A), label: l10n.dcaLegendValue),
          ],
        ),
        const SizedBox(height: 20),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Screenshot(
              controller: screenshotController,
              child: DcaShareCard(
                coin: coin,
                result: result,
                frequency: frequency,
                currency: currency,
                rate: rate,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: sharing ? null : onShare,
          icon: const Icon(Icons.share),
          label: Text(sharing ? l10n.dcaSharePreparing : l10n.dcaShareButton),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
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
          DefaultTextStyle.merge(
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      ],
    );
  }
}

class _DcaLineChart extends StatelessWidget {
  const _DcaLineChart({required this.result});
  final DcaResult result;

  @override
  Widget build(BuildContext context) {
    final investedSpots = [
      for (var i = 0; i < result.series.length; i++)
        FlSpot(i.toDouble(), result.series[i].investedCumulative),
    ];
    final valueSpots = [
      for (var i = 0; i < result.series.length; i++)
        FlSpot(i.toDouble(), result.series[i].valueCumulative),
    ];
    final allValues = [
      ...result.series.map((p) => p.investedCumulative),
      ...result.series.map((p) => p.valueCumulative),
    ];
    final minY = allValues.isEmpty ? 0.0 : allValues.reduce((a, b) => a < b ? a : b);
    final maxY = allValues.isEmpty ? 1.0 : allValues.reduce((a, b) => a > b ? a : b);

    return LineChart(
      LineChartData(
        minY: minY,
        maxY: maxY == minY ? maxY + 1 : maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => const FlLine(color: Colors.white12, strokeWidth: 1),
        ),
        titlesData: const FlTitlesData(
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: _leftLabel),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: investedSpots,
            isCurved: false,
            color: const Color(0xFF6FD3C7),
            barWidth: 2,
            dotData: const FlDotData(show: false),
          ),
          LineChartBarData(
            spots: valueSpots,
            isCurved: false,
            color: const Color(0xFF26A69A),
            barWidth: 2,
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );
  }

  static Widget _leftLabel(double value, TitleMeta meta) {
    return Text(
      value >= 1000 ? '${(value / 1000).toStringAsFixed(1)}k' : value.toStringAsFixed(0),
      style: const TextStyle(color: Colors.white38, fontSize: 10),
    );
  }
}
