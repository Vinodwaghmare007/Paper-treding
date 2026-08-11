import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';

/// Persistent "you're looking at old data" banner — shown instead of a
/// blank screen or an infinite spinner whenever a screen has fallen back
/// to cached data because the device is offline. Two variants:
///
/// - [asOf] set: names exactly when the cached data was fetched (used by
///   the chart screen, which has a precise local timestamp from
///   app_database.dart's candle cache).
/// - [asOf] null: a generic "showing your last synced data" message, for
///   Firestore-backed screens (portfolio, orders) where `cloud_firestore`'s
///   own offline persistence is already serving the cached snapshot but
///   doesn't expose an exact fetch timestamp to show here.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, this.asOf});

  final DateTime? asOf;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final asOfLocal = asOf;
    final message = asOfLocal == null
        ? l10n.offlineBannerGeneric
        : l10n.offlineBannerMessage(_formatTimestamp(asOfLocal.toLocal()));

    return Container(
      width: double.infinity,
      color: const Color(0xFFEF5350).withValues(alpha: 0.15),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, size: 14, color: Color(0xFFEF5350)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFFEF5350), fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
