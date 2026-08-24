import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/conditional_order.dart';
import '../../domain/entities/portfolio_position.dart';
import '../../l10n/generated/app_localizations.dart';
import '../auth/auth_providers.dart';
import '../settings/currency_providers.dart';
import '../settings/price_text.dart';
import 'conditional_order_providers.dart';

/// Opens the Stop-Loss / Take-Profit sheet for an existing LONG holding.
/// v1 scope: shorts aren't supported here — see TradeMath's doc comment
/// and checkConditionalOrders.ts, which only ever closes a long.
Future<void> showStopLossTakeProfitSheet(
  BuildContext context, {
  required PortfolioPosition holding,
  required double currentPrice,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1E222D),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => SetStopLossTakeProfitSheet(holding: holding, currentPrice: currentPrice),
  );
}

class SetStopLossTakeProfitSheet extends ConsumerStatefulWidget {
  const SetStopLossTakeProfitSheet({
    super.key,
    required this.holding,
    required this.currentPrice,
  });

  final PortfolioPosition holding;
  final double currentPrice;

  @override
  ConsumerState<SetStopLossTakeProfitSheet> createState() =>
      _SetStopLossTakeProfitSheetState();
}

class _SetStopLossTakeProfitSheetState extends ConsumerState<SetStopLossTakeProfitSheet> {
  ConditionalOrderKind _kind = ConditionalOrderKind.stopLoss;
  late final _priceController = TextEditingController();
  late final _quantityController =
      TextEditingController(text: widget.holding.totalQuantity.toString());
  bool _submitting = false;
  String? _errorText;

  @override
  void dispose() {
    _priceController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  double get _triggerPrice => double.tryParse(_priceController.text) ?? 0;
  double get _quantity => double.tryParse(_quantityController.text) ?? 0;

  Future<void> _submit(List<ConditionalOrder> existingForSymbol) async {
    final l10n = AppLocalizations.of(context)!;
    final triggerPrice = _triggerPrice;
    final quantity = _quantity;

    if (triggerPrice <= 0) {
      setState(() => _errorText = l10n.conditionalOrderEnterPrice);
      return;
    }
    if (_kind == ConditionalOrderKind.stopLoss && triggerPrice >= widget.currentPrice) {
      setState(() => _errorText = l10n.conditionalOrderStopLossBelowMarket);
      return;
    }
    if (_kind == ConditionalOrderKind.takeProfit && triggerPrice <= widget.currentPrice) {
      setState(() => _errorText = l10n.conditionalOrderTakeProfitAboveMarket);
      return;
    }
    if (quantity <= 0 || quantity > widget.holding.totalQuantity) {
      setState(() => _errorText = l10n.conditionalOrderInvalidQuantity);
      return;
    }

    setState(() {
      _submitting = true;
      _errorText = null;
    });

    try {
      final uid = ref.read(currentUidProvider)!;
      await ref.read(conditionalOrderRepositoryProvider).setConditionalOrder(
            uid,
            existingForSymbol: existingForSymbol,
            coinSymbol: widget.holding.coinSymbol,
            kind: _kind,
            triggerPrice: triggerPrice,
            quantity: quantity,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_kind == ConditionalOrderKind.stopLoss
              ? l10n.conditionalOrderStopLossSet
              : l10n.conditionalOrderTakeProfitSet),
          backgroundColor: const Color(0xFF26A69A),
        ),
      );
    } catch (_) {
      setState(() => _errorText = l10n.conditionalOrderSubmitError);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _cancel(ConditionalOrder order) async {
    final uid = ref.read(currentUidProvider)!;
    await ref.read(conditionalOrderRepositoryProvider).cancelConditionalOrder(uid, order.id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currency = ref.watch(currencyPreferenceProvider);
    final rate = ref.watch(usdToInrRateProvider).valueOrNull;
    final existingForSymbol =
        ref.watch(activeConditionalOrdersForSymbolProvider(widget.holding.coinSymbol));
    final existingStopLoss = existingForSymbol
        .cast<ConditionalOrder?>()
        .firstWhere((o) => o?.kind == ConditionalOrderKind.stopLoss, orElse: () => null);
    final existingTakeProfit = existingForSymbol
        .cast<ConditionalOrder?>()
        .firstWhere((o) => o?.kind == ConditionalOrderKind.takeProfit, orElse: () => null);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.conditionalOrderSheetTitle(widget.holding.coinSymbol),
            style: const TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(l10n.tradeSheetLivePrice(formatCurrency(widget.currentPrice, currency, rate)),
                  style: const TextStyle(color: Colors.white54, fontSize: 13)),
            ],
          ),
          if (existingStopLoss != null) ...[
            const SizedBox(height: 12),
            _ActiveOrderRow(
              label: l10n.conditionalOrderStopLossLabel,
              order: existingStopLoss,
              currency: currency,
              rate: rate,
              onCancel: () => _cancel(existingStopLoss),
            ),
          ],
          if (existingTakeProfit != null) ...[
            const SizedBox(height: 8),
            _ActiveOrderRow(
              label: l10n.conditionalOrderTakeProfitLabel,
              order: existingTakeProfit,
              currency: currency,
              rate: rate,
              onCancel: () => _cancel(existingTakeProfit),
            ),
          ],
          const SizedBox(height: 16),
          SegmentedButton<ConditionalOrderKind>(
            segments: [
              ButtonSegment(
                value: ConditionalOrderKind.stopLoss,
                label: Text(l10n.conditionalOrderStopLossLabel),
              ),
              ButtonSegment(
                value: ConditionalOrderKind.takeProfit,
                label: Text(l10n.conditionalOrderTakeProfitLabel),
              ),
            ],
            selected: {_kind},
            onSelectionChanged: (selection) => setState(() {
              _kind = selection.first;
              _errorText = null;
            }),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _priceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: l10n.conditionalOrderTriggerPriceLabel,
              border: const OutlineInputBorder(),
              helperText: _kind == ConditionalOrderKind.stopLoss
                  ? l10n.conditionalOrderStopLossHelper
                  : l10n.conditionalOrderTakeProfitHelper,
              helperStyle: const TextStyle(color: Colors.white38),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _quantityController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: l10n.tradeSheetQuantityLabel,
              suffixText: widget.holding.coinSymbol.replaceAll('USDT', ''),
              border: const OutlineInputBorder(),
              helperText: l10n.conditionalOrderHoldingQuantity(
                  widget.holding.totalQuantity.toString()),
              helperStyle: const TextStyle(color: Colors.white38),
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (_errorText != null) ...[
            const SizedBox(height: 12),
            Text(_errorText!, style: const TextStyle(color: Color(0xFFEF5350))),
          ],
          const SizedBox(height: 20),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _kind == ConditionalOrderKind.stopLoss
                  ? const Color(0xFFEF5350)
                  : const Color(0xFF26A69A),
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: _submitting ? null : () => _submit(existingForSymbol),
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(_kind == ConditionalOrderKind.stopLoss
                    ? l10n.conditionalOrderSetStopLoss
                    : l10n.conditionalOrderSetTakeProfit),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.conditionalOrderDisclaimer,
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _ActiveOrderRow extends StatelessWidget {
  const _ActiveOrderRow({
    required this.label,
    required this.order,
    required this.currency,
    required this.rate,
    required this.onCancel,
  });

  final String label;
  final ConditionalOrder order;
  final String currency;
  final double? rate;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final color =
        order.isStopLoss ? const Color(0xFFEF5350) : const Color(0xFF26A69A);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$label: ${order.quantity} @ ${formatCurrency(order.triggerPrice, currency, rate)}',
              style: TextStyle(color: color, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: onCancel,
            child: Text(l10n.conditionalOrderCancel, style: TextStyle(color: color)),
          ),
        ],
      ),
    );
  }
}
