import 'package:cloud_firestore/cloud_firestore.dart';

import '../firestore/firestore_paths.dart';

/// Which curated coins someone has starred on the Markets screen — pure
/// personal preference, read/written directly by the client (see
/// firestore.rules's `watchlist` match block for why this doesn't need a
/// Cloud Function the way `following`, Phase 8's server-verified
/// relationship, does).
class WatchlistRepository {
  WatchlistRepository(FirebaseFirestore firestore) : _paths = FirestorePaths(firestore);

  final FirestorePaths _paths;

  Stream<Set<String>> watchFollowedSymbols(String uid) {
    return _paths.watchlist(uid).snapshots().map(
          (snap) => snap.docs.map((d) => d.id).toSet(),
        );
  }

  Future<void> follow(String uid, String symbol) {
    return _paths.watchlistDoc(uid, symbol).set({
      'created_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> unfollow(String uid, String symbol) {
    return _paths.watchlistDoc(uid, symbol).delete();
  }
}
