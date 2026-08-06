import 'package:cloud_firestore/cloud_firestore.dart';

/// Centralizes the Firestore document/collection layout so every reader and
/// writer (usecase, repositories, security rules) agrees on the same paths:
///
/// ```
/// users/{userId}
/// users/{userId}/portfolio/{coinSymbol}
/// users/{userId}/orders/{orderId}
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
}
