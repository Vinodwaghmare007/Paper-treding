import 'dart:async';

import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/order.dart';
import '../../domain/entities/portfolio_position.dart';
import '../../domain/usecases/execute_trade.dart';
import '../../l10n/generated/app_localizations.dart';
import '../auth/auth_providers.dart';
import '../chart/price_source.dart';
import '../connectivity/connectivity_providers.dart';
import '../portfolio/portfolio_providers.dart';
import '../settings/currency_providers.dart';
import '../settings/price_text.dart';
import 'revenge_blocker_sheet.dart';
import 'trade_lock_provider.dart';

/// Public so callers (e.g. ticker_screen.dart's separate Buy/Sell FABs) can
/// open the sheet pre-selected to a side, instead of always landing on Buy
/// and making the user pick.
enum TradeSide { buy, sell }

/// Opens the Buy/Sell bottom sheet for [coinSymbol]. [currentPrice] seeds
/// the estimate before the sheet's own live price watch takes over.
/// [initialSide] controls which segment is selected when the sheet opens —
/// the segmented control inside still lets the user switch either way.
Future<void> showTradeSheet(
  BuildContext context, {
  required String coinSymbol,
  required double currentPrice,
  TradeSide initialSide = TradeSide.buy,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1E222D),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => TradeSheet(
      coinSymbol: coinSymbol,
      seedPrice: currentPrice,
      initialSide: initialSide,
    ),
  );
}

class TradeSheet extends ConsumerStatefulWidget {
  const TradeSheet({
    super.key,
    required this.coinSymbol,
    required this.seedPrice,
    this.initialSide = TradeSide.buy,
  });

  final String coinSymbol;
  final double seedPrice;
  final TradeSide initialSide;

  @override
  ConsumerState<TradeSheet> createState() => _TradeSheetState();
}

class _TradeSheetState extends ConsumerState<TradeSheet> {
  final _quantityController = TextEditingController();
  late TradeSide _side = widget.initialSide;
  bool _submitting = false;
  String? _errorText;

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  double get _quantity => double.tryParse(_quantityController.text) ?? 0;

  Future<void> _submit(double price, PortfolioPosition? holding) async {
    final l10n = AppLocalizations.of(context)!;
    final quantity = _quantity;
    if (quantity <= 0) {
      setState(() => _errorText = l10n.tradeSheetEnterQuantity);
      return;
    }
    setState(() {
      _submitting = true;
      _errorText = null;
    });

    final engine = ref.read(executeTradeUseCaseProvider);
    try {
      final order = _side == TradeSide.buy
          ? await engine.buy(
              coinSymbol: widget.coinSymbol, price: price, quantity: quantity)
          : await engine.sell(
              coinSymbol: widget.coinSymbol, price: price, quantity: quantity);

      if (await ref.read(firstTradeTrackerProvider).markFirstTradeIfNeeded()) {
        unawaited(ref.read(analyticsServiceProvider).logFirstTrade(orderType: order.orderType.code));
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      final currency = ref.read(currencyPreferenceProvider);
      final rate = ref.read(usdToInrRateProvider).valueOrNull;
      final priceStr = formatCurrency(order.price, currency, rate);
      final pnlStr = order.realizedPnl == null
          ? ''
          : '  (P&L ${formatCurrency(order.realizedPnl!, currency, rate)})';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${order.orderType.code} ${order.quantity} ${order.coinSymbol} '
            '@ $priceStr$pnlStr',
          ),
          backgroundColor: (order.realizedPnl ?? 0) < 0
              ? const Color(0xFFEF5350)
              : const Color(0xFF26A69A),
        ),
      );
    } on TradeRejected catch (e) {
      setState(() => _errorText = e.message);
    } on FirebaseException catch (e) {
      // A trade is a transaction, which (unlike a plain write) can't be
      // resolved from Firestore's offline cache — it needs a real
      // round-trip to check the account/position state first. Offline or
      // flaky connectivity surfaces here as `unavailable`/`deadline-
      // exceeded` rather than a TradeRejected, and rather than let that
      // propagate as an unhandled exception (which would leave the user
      // with no feedback and no way to know the trade never happened),
      // it's surfaced as an explicit, retryable error.
      setState(() => _errorText = e.code == 'unavailable' || e.code == 'deadline-exceeded'
          ? l10n.tradeSheetOfflineError
          : 'Trade failed: ${e.message ?? e.code}');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final latestTick = ref.watch(activeTickProvider).valueOrNull;
    final price = (latestTick != null && latestTick.symbol == widget.coinSymbol)
        ? latestTick.candle.close
        : widget.seedPrice;

    final account = ref.watch(accountStreamProvider).valueOrNull;
    final positions = ref.watch(portfolioStreamProvider).valueOrNull ?? const [];
    final holding = positions
        .cast<PortfolioPosition?>()
        .firstWhere((p) => p?.coinSymbol == widget.coinSymbol, orElse: () => null);

    // The buy-lock only ever blocks opening/adding to a long — covering an
    // existing short is risk-reducing and stays exempt, mirroring
    // TradeMath.applyBuy's identical carve-out.
    final isCoveringShort = holding != null && holding.isShort;
    final lockState = ref.watch(tradeLockProvider);
    final isLocked = _side == TradeSide.buy && lockState.isLocked && !isCoveringShort;
    final isOnline = ref.watch(isOnlineProvider);

    final currency = ref.watch(currencyPreferenceProvider);
    final rate = ref.watch(usdToInrRateProvider).valueOrNull;

    final total = price * _quantity;
    final canAffordBuy = account != null && total <= account.virtualBalance;
    // A long holding: Sell can only close up to what's held (no
    // same-order flip to short — see TradeMath's doc comment). Flat or
    // already-short: Sell opens/adds to a short, gated by the same
    // balance-based collateral check as a buy.
    final canAffordSell = (holding != null && holding.isLong)
        ? _quantity <= holding.totalQuantity
        : (account != null && total <= account.virtualBalance);
    final canSubmit = !_submitting &&
        !isLocked &&
        isOnline &&
        _quantity > 0 &&
        (_side == TradeSide.buy ? canAffordBuy : canAffordSell);

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
            l10n.tradeSheetLivePrice(formatCurrency(price, currency, rate)),
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 16),
          SegmentedButton<TradeSide>(
            segments: [
              ButtonSegment(value: TradeSide.buy, label: Text(l10n.tradeSheetBuy)),
              ButtonSegment(value: TradeSide.sell, label: Text(l10n.tradeSheetSell)),
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
              labelText: l10n.tradeSheetQuantityLabel,
              suffixText: widget.coinSymbol.replaceAll('USDT', ''),
              border: const OutlineInputBorder(),
              helperText: holding == null
                  ? l10n.tradeSheetNoHoldingsYet
                  : holding.isShort
                      ? l10n.tradeSheetShortSummary(
                          (-holding.totalQuantity).toString(),
                          formatCurrency(holding.avgBuyPrice, currency, rate),
                        )
                      : l10n.tradeSheetHoldingSummary(
                          holding.totalQuantity.toString(),
                          formatCurrency(holding.avgBuyPrice, currency, rate),
                        ),
              helperStyle: const TextStyle(color: Colors.white38),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l10n.tradeSheetEstimatedTotal, style: const TextStyle(color: Colors.white54)),
              PriceText(total, style: const TextStyle(color: Colors.white, fontSize: 16)),
            ],
          ),
          if (account != null) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.tradeSheetAvailableBalance,
                    style: const TextStyle(color: Colors.white38, fontSize: 12)),
                PriceText(account.virtualBalance,
                    style: const TextStyle(color: Colors.white38, fontSize: 12)),
              ],
            ),
          ],
          if (isLocked) ...[
            const SizedBox(height: 12),
            _LockNotice(lockState: lockState),
          ],
          if (!isOnline) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFEF5350).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFEF5350)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.cloud_off, color: Color(0xFFEF5350), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.tradeSheetOfflineNotice,
                      style: const TextStyle(color: Color(0xFFEF5350), fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_errorText != null) ...[
            const SizedBox(height: 12),
            Text(_errorText!, style: const TextStyle(color: Color(0xFFEF5350))),
          ],
          const SizedBox(height: 20),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: (isLocked || !isOnline)
                  ? Colors.white12
                  : (_side == TradeSide.buy
                      ? const Color(0xFF26A69A)
                      : const Color(0xFFEF5350)),
              minimumSize: const Size.fromHeight(48),
            ),
            // While locked, the button stays tappable — tapping it opens the
            // hard-lock sheet — but never actually submits a trade. A truly
            // disabled (onPressed: null) button couldn't do that. Offline
            // has no equivalent explainer sheet to open, so it just
            // disables outright — the notice above already says why.
            onPressed: isLocked
                ? () => showRevengeBlockerSheet(context)
                : (canSubmit ? () => _submit(price, holding) : null),
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text(
                    isLocked
                        ? l10n.tradeSheetLockedRemaining(_formatCountdown(lockState.remainingSeconds))
                        : (_side == TradeSide.buy ? l10n.tradeSheetConfirmBuy : l10n.tradeSheetConfirmSell),
                    style: TextStyle(color: (isLocked || !isOnline) ? Colors.white38 : null),
                  ),
          ),
        ],
      ),
    );
  }
}

String _formatCountdown(int totalSeconds) {
  final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

class _LockNotice extends StatelessWidget {
  const _LockNotice({required this.lockState});

  final TradeLockState lockState;

  @override
  Widget build(BuildContext context) {
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
              AppLocalizations.of(context)!
                  .tradeSheetLockNotice(_formatCountdown(lockState.remainingSeconds)),
              style: const TextStyle(color: Color(0xFFEF5350), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
