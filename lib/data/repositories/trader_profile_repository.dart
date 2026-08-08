import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/activity_event.dart';
import '../../domain/entities/trade_rationale.dart';
import '../../domain/entities/trader_profile.dart';
import '../firestore/firestore_paths.dart';

/// Reads/writes for opt-in public trader profiles, follow relationships,
/// and the factual activity feed. Everything under profile_stats and
/// public_activity is Cloud-Function-written only (see firestore.rules) —
/// this repository never attempts to write those directly.
class TraderProfileRepository {
  TraderProfileRepository(FirebaseFirestore firestore) : _paths = FirestorePaths(firestore);

  final FirestorePaths _paths;

  /// The owner's own settings — display_name + is_public. This is the
  /// only trader-profile data a client can write at all.
  Stream<({String displayName, bool isPublic})> watchOwnSettings(String uid) {
    return _paths.profileSettings(uid).snapshots().map((snap) {
      final data = snap.data();
      return (
        displayName: data?['display_name'] as String? ?? '',
        isPublic: data?['is_public'] as bool? ?? false,
      );
    });
  }

  Future<void> updateSettings(
    String uid, {
    required String displayName,
    required bool isPublic,
  }) {
    return _paths.profileSettings(uid).set({
      'display_name': displayName,
      'is_public': isPublic,
    });
  }

  /// A public profile's derived stats (also carries a mirrored
  /// display_name/is_public — see syncProfileVisibility.ts — so viewing
  /// someone else's profile only needs this one read, not a second one
  /// against profile_settings). Null if the profile doesn't exist or
  /// isn't public (the read itself is rules-denied in that case, which
  /// surfaces as a stream error — callers should treat any error here as
  /// "not visible," not necessarily "broken").
  Stream<TraderProfile?> watchProfile(String uid) {
    return _paths.profileStats(uid).snapshots().map((snap) {
      final data = snap.data();
      if (data == null) return null;
      return TraderProfile.fromMap(uid, data);
    });
  }

  Stream<bool> watchIsFollowing(String followerUid, String followedUid) {
    return _paths.followingDoc(followerUid, followedUid).snapshots().map((s) => s.exists);
  }

  Future<void> follow(String followerUid, String followedUid) {
    return _paths.followingDoc(followerUid, followedUid).set({
      'created_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> unfollow(String followerUid, String followedUid) {
    return _paths.followingDoc(followerUid, followedUid).delete();
  }

  Stream<List<String>> watchFollowedUserIds(String uid) {
    return _paths.following(uid).snapshots().map(
          (snap) => snap.docs.map((d) => d.id).toList(growable: false),
        );
  }

  /// The (at most one) rationale note on a specific order — used by
  /// order_history_screen.dart both to show an owner's own note and to
  /// decide whether to offer "add a note" at all.
  Stream<TradeRationale?> watchRationale(String uid, String orderId) {
    return _paths.tradeRationale(uid, orderId).snapshots().map((snap) {
      final data = snap.data();
      if (data == null) return null;
      return TradeRationale.fromMap(orderId, data);
    });
  }

  /// Every rationale a trader has posted, most recent first — used by
  /// trader_profile_screen.dart to show a visitor a read-only list.
  /// A collectionGroup query rather than per-order lookups: a visitor's
  /// security rules grant read access to `rationale` docs but not to the
  /// trader's `orders` collection itself (owner-only), so there's no way
  /// to first list "which orders have a note" and look each one up — the
  /// user_id field on the rationale doc (see addTradeRationale.ts) is
  /// what this filters on instead.
  Future<List<TradeRationale>> fetchTraderRationales(String uid, {int limit = 20}) async {
    final snap = await _paths
        .rationaleCollectionGroup()
        .where('user_id', isEqualTo: uid)
        .orderBy('created_at', descending: true)
        .limit(limit)
        .get();
    return snap.docs
        .map((doc) => TradeRationale.fromMap(doc.reference.parent.parent!.id, doc.data()))
        .toList(growable: false);
  }

  /// Most recent activity entries for one followed trader — bounded by
  /// [limit] since public_activity isn't actively pruned server-side (see
  /// publicActivity.ts's doc comment); the read side is what keeps this
  /// cheap, not the write side. Two reads per call (display_name from
  /// profile_stats, then the activity page) rather than one — see
  /// following_feed_screen.dart's doc comment for the N+1-reads-per-
  /// followed-user trade-off this and its caller both accept.
  Future<List<ActivityEvent>> fetchRecentActivity(String uid, {int limit = 20}) async {
    final statsSnap = await _paths.profileStats(uid).get();
    final displayName = statsSnap.data()?['display_name'] as String? ?? 'Trader';

    final activitySnap = await _paths
        .publicActivity(uid)
        .orderBy('created_at', descending: true)
        .limit(limit)
        .get();
    return activitySnap.docs
        .map((doc) => ActivityEvent.fromMap(uid, displayName, doc.data()))
        .whereType<ActivityEvent>()
        .toList(growable: false);
  }
}
