import 'package:cloud_firestore/cloud_firestore.dart';

/// Centralizes the Firestore document/collection layout so every reader and
/// writer (usecase, repositories, security rules) agrees on the same paths:
///
/// ```
/// users/{userId}
/// users/{userId}/portfolio/{coinSymbol}
/// users/{userId}/orders/{orderId}
/// chat_rooms/{roomId}
/// chat_rooms/{roomId}/messages/{messageId}
/// chat_rate_limits/{userId}
/// reports/{reportId}
/// ```
class FirestorePaths {
  FirestorePaths(this._firestore);

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> user(String uid) =>
      _firestore.collection('users').doc(uid);

  CollectionReference<Map<String, dynamic>> portfolio(String uid) =>
      user(uid).collection('portfolio');

  DocumentReference<Map<String, dynamic>> portfolioPosition(
    String uid,
    String coinSymbol,
  ) =>
      portfolio(uid).doc(coinSymbol);

  CollectionReference<Map<String, dynamic>> orders(String uid) =>
      user(uid).collection('orders');

  DocumentReference<Map<String, dynamic>> newOrderRef(String uid) =>
      orders(uid).doc();

  CollectionReference<Map<String, dynamic>> chatRooms() =>
      _firestore.collection('chat_rooms');

  DocumentReference<Map<String, dynamic>> chatRoom(String roomId) =>
      chatRooms().doc(roomId);

  CollectionReference<Map<String, dynamic>> chatMessages(String roomId) =>
      chatRoom(roomId).collection('messages');

  DocumentReference<Map<String, dynamic>> chatRateLimit(String uid) =>
      _firestore.collection('chat_rate_limits').doc(uid);

  CollectionReference<Map<String, dynamic>> reports() =>
      _firestore.collection('reports');

  DocumentReference<Map<String, dynamic>> newReportRef() => reports().doc();

  // See the path-naming note in functions/src/sentiment/aggregateSentiment.ts
  // for why this is a flat top-level collection rather than nested under a
  // shared "public" document.
  DocumentReference<Map<String, dynamic>> publicSentiment(String symbol) =>
      _firestore.collection('public_sentiment').doc(symbol);

  DocumentReference<Map<String, dynamic>> dailyPuzzle(String date) =>
      _firestore.collection('daily_puzzle').doc(date);

  DocumentReference<Map<String, dynamic>> publicCohortMedian(String cohortKey) =>
      _firestore.collection('public_cohort_medians').doc(cohortKey);

  // Written only by functions/src/certifications/*.ts (Admin SDK) — see
  // firestore.rules's `certifications` match block.
  CollectionReference<Map<String, dynamic>> certifications(String uid) =>
      user(uid).collection('certifications');

  // ------------------------------------------------------------------
  // Trader Profiles (Phase 8)
  // ------------------------------------------------------------------

  // Client-writable (display_name + is_public only) — see
  // functions/src/traderProfile/syncProfileVisibility.ts for how this
  // mirrors onto profileStats below.
  DocumentReference<Map<String, dynamic>> profileSettings(String uid) =>
      user(uid).collection('profile_settings').doc('data');

  // Entirely Cloud-Function-written — functions/src/traderProfile/
  // recomputeTraderStats.ts, syncProfileVisibility.ts, onFollowChange.ts.
  DocumentReference<Map<String, dynamic>> profileStats(String uid) =>
      user(uid).collection('profile_stats').doc('data');

  CollectionReference<Map<String, dynamic>> following(String uid) =>
      user(uid).collection('following');

  DocumentReference<Map<String, dynamic>> followingDoc(String uid, String followedUid) =>
      following(uid).doc(followedUid);

  // Cloud-Function-written factual activity log — see
  // functions/src/traderProfile/publicActivity.ts.
  CollectionReference<Map<String, dynamic>> publicActivity(String uid) =>
      user(uid).collection('public_activity');

  // Singleton per order — one rationale note per closed trade. Written
  // only via the addTradeRationale callable (see
  // functions/src/rationale/addTradeRationale.ts and
  // domain/usecases/add_trade_rationale.dart).
  DocumentReference<Map<String, dynamic>> tradeRationale(String uid, String orderId) =>
      orders(uid).doc(orderId).collection('rationale').doc('note');

  // Requires the `user_id` field addTradeRationale.ts writes onto every
  // rationale doc — see trader_profile_repository.dart's
  // fetchTraderRationales for why a collection-group query is needed
  // here instead of listing a trader's orders directly.
  Query<Map<String, dynamic>> rationaleCollectionGroup() =>
      _firestore.collectionGroup('rationale');

  DocumentReference<Map<String, dynamic>> publicLeaderboard(String window) =>
      _firestore.collection('public_leaderboard').doc(window);
}
