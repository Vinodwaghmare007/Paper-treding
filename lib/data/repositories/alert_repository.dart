import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/price_alert.dart';
import '../firestore/firestore_paths.dart';

class AlertRepository {
  AlertRepository(FirebaseFirestore firestore) : _paths = FirestorePaths(firestore);

  final FirestorePaths _paths;

  /// Newest first, active alerts before triggered ones within that —
  /// matches how create_alert_screen.dart groups its list.
  Stream<List<PriceAlert>> watchAlerts(String uid) {
    return _paths.alerts(uid).orderBy('created_at', descending: true).snapshots().map(
          (snap) => [for (final doc in snap.docs) PriceAlert.fromMap(doc.id, doc.data())],
        );
  }

  Future<void> createAlert(
    String uid, {
    required String coinSymbol,
    required double targetPrice,
    required AlertDirection direction,
  }) {
    return _paths.newAlertRef(uid).set({
      'coin_symbol': coinSymbol,
      'target_price': targetPrice,
      'direction': direction.value,
      'is_active': true,
      'triggered_at': null,
      'created_at': FieldValue.serverTimestamp(),
    });
  }

  /// A partial `.update()` (not `.set()`) so `is_active`/`triggered_at`/
  /// `created_at` are simply never touched by this write — no read-modify-
  /// write race against checkPriceAlerts.ts flipping them server-side
  /// concurrently.
  Future<void> editAlert(
    String uid,
    String alertId, {
    required String coinSymbol,
    required double targetPrice,
    required AlertDirection direction,
  }) {
    return _paths.alertDoc(uid, alertId).update({
      'coin_symbol': coinSymbol,
      'target_price': targetPrice,
      'direction': direction.value,
    });
  }

  Future<void> deleteAlert(String uid, String alertId) {
    return _paths.alertDoc(uid, alertId).delete();
  }
}
