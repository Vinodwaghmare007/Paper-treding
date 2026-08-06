import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/community_sentiment.dart';

/// Converts between the pure domain entity and its Firestore document
/// shape. Kept out of `domain/` so the entity stays Firebase-free.
extension CommunitySentimentFirestoreMapping on CommunitySentiment {
  static CommunitySentiment fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) {
      throw StateError('public_sentiment/${doc.id} does not exist');
    }
    final ts = data['updated_at'];
    return CommunitySentiment(
      symbol: data['symbol'] as String? ?? doc.id,
      bullishPct: (data['bullish_pct'] as num?)?.toDouble(),
      bearishPct: (data['bearish_pct'] as num?)?.toDouble(),
      totalOrders: (data['total_orders'] as num?)?.toInt() ?? 0,
      windowMinutes: (data['window_minutes'] as num?)?.toInt() ?? 60,
      updatedAt: ts is Timestamp
          ? ts.toDate().toUtc()
          : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}
