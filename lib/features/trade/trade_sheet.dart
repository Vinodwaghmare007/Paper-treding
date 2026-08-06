import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/order.dart';
import '../../domain/entities/portfolio_position.dart';
import '../../domain/usecases/execute_trade.dart';
import '../portfolio/portfolio_providers.dart';
import '../ticker/ticker_providers.dart';

enum _Side { buy, sell }

/// Opens the Buy/Sell bottom sheet for [coinSymbol]. [currentPrice] seeds
/// the estimate before the sheet's own live price watch takes over.
Future<void> showTradeSheet(
  BuildContext context, {
  required String coinSymbol,
  required double currentPrice,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1E222D),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => TradeSheet(coinSymbol: coinSymbol, seedPrice: currentPrice),
  );
}

class TradeSheet extends ConsumerStatefulWidget {
  const TradeSheet({
    super.key,
    required this.coinSymbol,
    required this.seedPrice,
  });

  final String coinSymbol;
  final double seedPrice;

  @override
  ConsumerState<TradeSheet> createState() => _TradeSheetState();
}

class _TradeSheetState extends ConsumerState<TradeSheet> {
  final _quantityController = TextEditingController();
  _Side _side = _Side.buy;
  bool _submitting = false;
  String? _errorText;
  Timer? _tickerTimer;

  @override
  void initState() {
    super.initState();
    // Repaints the lock countdown every second without depending on a new
    // tick arriving.
    _tickerTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tickerTimer?.cancel();
    _quantityController.dispose();
    super.dispose();
  }

  double get _quantity => double.tryParse(_quantityController.text) ?? 0;

  Future<void> _submit(double price, PortfolioPosition? holding) async {
    final quantity = _quantity;
    if (quantity <= 0) {
      setState(() => _errorText = 'Enter a quantity greater than zero.');
      return;
    }
    setState(() {
      _submitting = true;
      _errorText = null;
    });

    final engine = ref.read(executeTradeUseCaseProvider);
    try {
      final order = _side == _Side.buy
          ? await engine.buy(
              coinSymbol: widget.coinSymbol, price: price, quantity: quantity)
          : await engine.sell(
              coinSymbol: widget.coinSymbol, price: price, quantity: quantity);

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${order.orderType.code} ${order.quantity} ${order.coinSymbol} '
            '@ ${order.price.toStringAsFixed(2)}'
            '${order.realizedPnl != null ? '  (P&L ${order.realizedPnl!.toStringAsFixed(2)})' : ''}',
          ),
          backgroundColor: (order.realizedPnl ?? 0) < 0
              ? const Color(0xFFEF5350)
              : const Color(0xFF26A69A),
        ),
      );
    } on TradeRejected catch (e) {
      setState(() => _errorText = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final liveTick = ref.watch(klineTickProvider).valueOrNull;
    final price = (liveTick != null && liveTick.symbol == widget.coinSymbol)
        ? liveTick.candle.close
        : widget.seedPrice;

    final account = ref.watch(accountStreamProvider).valueOrNull;
    final positions = ref.watch(portfolioStreamProvider).valueOrNull ?? const [];
    final holding = positions
        .cast<PortfolioPosition?>()
        .firstWhere((p) => p?.coinSymbol == widget.coinSymbol, orElse: () => null);

    final now = DateTime.now().toUtc();
    final lockedUntil = account?.buyLockedUntil;
    final isLocked = _side == _Side.buy &&
        lockedUntil != null &&
        lockedUntil.isAfter(now);
    final total = price * _quantity;
    final canAffordBuy = account != null && total <= account.virtualBalance;
    final canAffordSell = holding != null && _quantity <= holding.totalQuantity;
    final canSubmit = !_submitting &&
        !isLocked &&
        _quantity > 0 &&
        (_side == _Side.buy ? canAffordBuy : canAffordSell);

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
            widget.coinSymbol,
            style: const TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Live price: ${price.toStringAsFixed(2)}',
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 16),
          SegmentedButton<_Side>(
            segments: const [
              ButtonSegment(value: _Side.buy, label: Text('BUY')),
              ButtonSegment(value: _Side.sell, label: Text('SELL')),
            ],
            selected: {_side},
            onSelectionChanged: (selection) => setState(() {
              _side = selection.first;
              _errorText = null;
            }),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _quantityController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Quantity',
              suffixText: widget.coinSymbol.replaceAll('USDT', ''),
              border: const OutlineInputBorder(),
              helperText: holding != null
                  ? 'Holding: ${holding.totalQuantity} @ avg ${holding.avgBuyPrice.toStringAsFixed(2)}'
                  : 'No holdings yet',
              helperStyle: const TextStyle(color: Colors.white38),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Estimated total', style: TextStyle(color: Colors.white54)),
              Text(
                total.toStringAsFixed(2),
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
          if (account != null) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Available balance', style: TextStyle(color: Colors.white38, fontSize: 12)),
                Text(
                  account.virtualBalance.toStringAsFixed(2),
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ],
          if (isLocked) ...[
            const SizedBox(height: 12),
            _LockNotice(lockedUntil: lockedUntil),
          ],
          if (_errorText != null) ...[
            const SizedBox(height: 12),
            Text(_errorText!, style: const TextStyle(color: Color(0xFFEF5350))),
          ],
          const SizedBox(height: 20),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _side == _Side.buy
                  ? const Color(0xFF26A69A)
                  : const Color(0xFFEF5350),
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: canSubmit ? () => _submit(price, holding) : null,
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text(_side == _Side.buy ? 'Confirm Buy' : 'Confirm Sell'),
          ),
        ],
      ),
    );
  }
}

class _LockNotice extends StatelessWidget {
  const _LockNotice({required this.lockedUntil});

  final DateTime lockedUntil;

  @override
  Widget build(BuildContext context) {
    final remaining = lockedUntil.difference(DateTime.now().toUtc());
    final minutes = remaining.inMinutes.clamp(0, 999);
    final seconds = (remaining.inSeconds % 60).clamp(0, 59);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFEF5350).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFEF5350)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_clock, color: Color(0xFFEF5350), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Buying locked after 3 losing trades in a row. '
              'Try again in ${minutes}m ${seconds}s.',
              style: const TextStyle(color: Color(0xFFEF5350), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
