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
}
