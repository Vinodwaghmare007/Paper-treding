import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/watchlist_entry.dart';
import '../firestore/firestore_paths.dart';

/// Which curated coins someone has starred on the Markets screen — pure
/// personal preference, read/written directly by the client (see
/// firestore.rules's `watchlist` match block for why this doesn't need a
/// Cloud Function the way `following`, Phase 8's server-verified
/// relationship, does).
class WatchlistRepository {
  WatchlistRepository(FirebaseFirestore firestore)
      : _paths = FirestorePaths(firestore),
        _firestore = firestore;

  final FirestorePaths _paths;
  final FirebaseFirestore _firestore;

  /// Ordered by `sort_order` ascending — the order the Markets screen pins
  /// starred coins to the top in.
  Stream<List<WatchlistEntry>> watchWatchlist(String uid) {
    return _paths.watchlist(uid).orderBy('sort_order').snapshots().map(
          (snap) => [
            for (final doc in snap.docs) WatchlistEntry.fromMap(doc.id, doc.data()),
          ],
        );
  }

  /// Convenience view for screens that only need to know *which* symbols
  /// are followed (e.g. drawing a filled vs. outline star), without caring
  /// about order.
  Stream<Set<String>> watchFollowedSymbols(String uid) {
    return _paths.watchlist(uid).snapshots().map(
          (snap) => snap.docs.map((d) => d.id).toSet(),
        );
  }

  /// New entries go to the end of the list — reads the current max
  /// `sort_order` first. The watchlist tops out at 15 entries (the whole
  /// curated coin list), so this extra read is negligible.
  Future<void> follow(String uid, String symbol) async {
    final existing = await _paths.watchlist(uid).orderBy('sort_order', descending: true).limit(1).get();
    final nextOrder = existing.docs.isEmpty ? 0 : (existing.docs.first.data()['sort_order'] as num).toInt() + 1;
    await _paths.watchlistDoc(uid, symbol).set({
      'added_at': FieldValue.serverTimestamp(),
      'sort_order': nextOrder,
    });
  }

  Future<void> unfollow(String uid, String symbol) {
    return _paths.watchlistDoc(uid, symbol).delete();
  }

  /// Persists a full reorder (e.g. after a drag-and-drop reorder in the
  /// UI) — writes every entry's new `sort_order` in one batch so readers
  /// never see a half-reordered list.
  Future<void> reorder(String uid, List<String> symbolsInOrder) async {
    final batch = _firestore.batch();
    for (var i = 0; i < symbolsInOrder.length; i++) {
      batch.set(_paths.watchlistDoc(uid, symbolsInOrder[i]), {'sort_order': i}, SetOptions(merge: true));
    }
    await batch.commit();
  }
}
