import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/conditional_order.dart';
import '../firestore/firestore_paths.dart';

class ConditionalOrderRepository {
  ConditionalOrderRepository(FirebaseFirestore firestore)
      : _firestore = firestore,
        _paths = FirestorePaths(firestore);

  final FirebaseFirestore _firestore;
  final FirestorePaths _paths;

  /// All conditional orders for [uid] (active and already-triggered),
  /// newest first — the UI filters down to active-per-symbol itself.
  Stream<List<ConditionalOrder>> watchConditionalOrders(String uid) {
    return _paths.conditionalOrders(uid).orderBy('created_at', descending: true).snapshots().map(
          (snap) =>
              [for (final doc in snap.docs) ConditionalOrder.fromMap(doc.id, doc.data())],
        );
  }

  /// Cancels any existing active order of [kind] for [coinSymbol] (if any)
  /// and creates a new one in the same batch — the "set" action always
  /// replaces rather than stacking, since firestore.rules only allows a
  /// client to create or delete, never edit a live order's price.
  Future<void> setConditionalOrder(
    String uid, {
    required List<ConditionalOrder> existingForSymbol,
    required String coinSymbol,
    required ConditionalOrderKind kind,
    required double triggerPrice,
    required double quantity,
  }) {
    final batch = _firestore.batch();
    for (final existing in existingForSymbol) {
      if (existing.isActive && existing.kind == kind) {
        batch.delete(_paths.conditionalOrderDoc(uid, existing.id));
      }
    }
    batch.set(_paths.newConditionalOrderRef(uid), {
      'coin_symbol': coinSymbol,
      'kind': kind.code,
      'trigger_price': triggerPrice,
      'quantity': quantity,
      'is_active': true,
      'triggered_at': null,
      'last_checked_price': null,
      'created_at': FieldValue.serverTimestamp(),
    });
    return batch.commit();
  }

  Future<void> cancelConditionalOrder(String uid, String orderId) {
    return _paths.conditionalOrderDoc(uid, orderId).delete();
  }
}
