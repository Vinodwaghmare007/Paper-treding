import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/entities/supported_coin.dart';
import '../../domain/entities/price_alert.dart';
import '../../l10n/generated/app_localizations.dart';
import '../auth/auth_providers.dart';
import '../settings/price_text.dart';
import 'alerts_providers.dart';

/// Create/manage price alerts — target price + above/below per coin,
/// pushed via FCM when checkPriceAlerts.ts (scheduled every minute)
/// detects the price crossed the target. See notifications_service.dart
/// for the device-token registration this depends on.
class CreateAlertScreen extends ConsumerStatefulWidget {
  const CreateAlertScreen({super.key});

  @override
  ConsumerState<CreateAlertScreen> createState() => _CreateAlertScreenState();
}

class _CreateAlertScreenState extends ConsumerState<CreateAlertScreen> {
  final _priceController = TextEditingController();
  String _symbol = 'BTCUSDT';
  AlertDirection _direction = AlertDirection.above;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final l10n = AppLocalizations.of(context)!;
    final price = double.tryParse(_priceController.text);
    if (price == null || price <= 0) {
      setState(() => _error = l10n.alertsEnterPriceError);
      return;
    }
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(alertRepositoryProvider).createAlert(
            uid,
            coinSymbol: _symbol,
            targetPrice: price,
            direction: _direction,
          );
      _priceController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.alertsCreatedSnackbar)),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final alertsAsync = ref.watch(alertsProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E222D),
        title: Text(l10n.alertsTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _CreateCard(
            priceController: _priceController,
            symbol: _symbol,
            direction: _direction,
            saving: _saving,
            error: _error,
            onSymbolChanged: (v) => setState(() => _symbol = v),
            onDirectionChanged: (v) => setState(() => _direction = v),
            onCreate: _create,
          ),
          const SizedBox(height: 24),
          alertsAsync.when(
            data: (alerts) {
              final active = alerts.where((a) => a.isActive).toList();
              final triggered = alerts.where((a) => !a.isActive).toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.alertsActiveSectionTitle,
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  if (active.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(l10n.alertsNoActiveAlerts, style: const TextStyle(color: Colors.white38)),
                    )
                  else
                    ...active.map((a) => _AlertTile(alert: a)),
                  if (triggered.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(l10n.alertsTriggeredSectionTitle,
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    ...triggered.map((a) => _AlertTile(alert: a)),
                  ],
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) =>
                Text(l10n.alertsLoadError(e.toString()), style: const TextStyle(color: Color(0xFFEF5350))),
          ),
        ],
      ),
    );
  }
}

class _CreateCard extends StatelessWidget {
  const _CreateCard({
    required this.priceController,
    required this.symbol,
    required this.direction,
    required this.saving,
    required this.error,
    required this.onSymbolChanged,
    required this.onDirectionChanged,
    required this.onCreate,
  });

  final TextEditingController priceController;
  final String symbol;
  final AlertDirection direction;
  final bool saving;
  final String? error;
  final ValueChanged<String> onSymbolChanged;
  final ValueChanged<AlertDirection> onDirectionChanged;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E222D),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.alertsNewAlertTitle,
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: symbol,
            dropdownColor: const Color(0xFF1E222D),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(labelText: l10n.coinFieldLabel, isDense: true),
            items: [
              for (final coin in supportedCoins)
                DropdownMenuItem(value: coin.symbol, child: Text('${coin.baseAsset} · ${coin.displayName}')),
            ],
            onChanged: (v) {
              if (v != null) onSymbolChanged(v);
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: priceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: l10n.alertsTargetPriceLabel,
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SegmentedButton<AlertDirection>(
                segments: [
                  ButtonSegment(value: AlertDirection.above, label: Text(l10n.alertsDirectionAbove)),
                  ButtonSegment(value: AlertDirection.below, label: Text(l10n.alertsDirectionBelow)),
                ],
                selected: {direction},
                onSelectionChanged: (s) => onDirectionChanged(s.first),
              ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!, style: const TextStyle(color: Color(0xFFEF5350), fontSize: 12)),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: saving ? null : onCreate,
            child: saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(l10n.alertsCreateButton),
          ),
        ],
      ),
    );
  }
}

class _AlertTile extends ConsumerWidget {
  const _AlertTile({required this.alert});

  final PriceAlert alert;

  Future<void> _delete(WidgetRef ref) async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;
    await ref.read(alertRepositoryProvider).deleteAlert(uid, alert.id);
  }

  Future<void> _editPrice(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: alert.targetPrice.toString());
    var direction = alert.direction;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E222D),
          title: Text(l10n.alertsEditDialogTitle, style: const TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(labelText: l10n.alertsTargetPriceLabel),
              ),
              const SizedBox(height: 12),
              SegmentedButton<AlertDirection>(
                segments: [
                  ButtonSegment(value: AlertDirection.above, label: Text(l10n.alertsDirectionAbove)),
                  ButtonSegment(value: AlertDirection.below, label: Text(l10n.alertsDirectionBelow)),
                ],
                selected: {direction},
                onSelectionChanged: (s) => setDialogState(() => direction = s.first),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.commonSave),
            ),
          ],
        ),
      ),
    );
    if (result != true || !context.mounted) return;

    final price = double.tryParse(controller.text);
    if (price == null || price <= 0) return;
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;
    await ref.read(alertRepositoryProvider).editAlert(
          uid,
          alert.id,
          coinSymbol: alert.coinSymbol,
          targetPrice: price,
          direction: direction,
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final coin = coinForSymbol(alert.coinSymbol);
    final isAbove = alert.direction == AlertDirection.above;

    return Card(
      color: const Color(0xFF1E222D),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: alert.isActive ? () => _editPrice(context, ref) : null,
        leading: Icon(
          isAbove ? Icons.trending_up : Icons.trending_down,
          color: alert.isActive
              ? (isAbove ? const Color(0xFF26A69A) : const Color(0xFFEF5350))
              : Colors.white24,
        ),
        title: Row(
          children: [
            Text('${coin.baseAsset} ${isAbove ? '≥' : '≤'} ',
                style: TextStyle(color: alert.isActive ? Colors.white : Colors.white54)),
            PriceText(alert.targetPrice,
                style: TextStyle(color: alert.isActive ? Colors.white : Colors.white54)),
          ],
        ),
        subtitle: !alert.isActive && alert.triggeredAt != null
            ? Text(l10n.alertsTriggeredOn(_fmt(alert.triggeredAt!)),
                style: const TextStyle(color: Colors.white38, fontSize: 12))
            : null,
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.white38),
          onPressed: () => _delete(ref),
        ),
      ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
