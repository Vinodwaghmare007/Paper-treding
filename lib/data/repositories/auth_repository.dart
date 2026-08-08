import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../analytics/analytics_service.dart';
import '../firestore/firestore_paths.dart';
import '../firestore/trading_mappers.dart';

/// A human-readable auth failure, derived from [FirebaseAuthException.code]
/// so the UI never has to know Firebase's error taxonomy.
class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;

  @override
  String toString() => message;

  factory AuthFailure.fromFirebase(FirebaseAuthException e) {
    final message = switch (e.code) {
      'invalid-email' => 'That email address looks invalid.',
      'user-disabled' => 'This account has been disabled.',
      'user-not-found' => 'No account found for that email.',
      'wrong-password' || 'invalid-credential' => 'Incorrect email or password.',
      'email-already-in-use' => 'An account already exists for that email.',
      'weak-password' => 'Choose a stronger password (6+ characters).',
      'network-request-failed' => 'Network error — check your connection.',
      'too-many-requests' => 'Too many attempts. Try again later.',
      _ => e.message ?? 'Authentication failed (${e.code}).',
    };
    return AuthFailure(message);
  }
}

/// Wraps Firebase Auth (email/password + Google) and bootstraps the
/// Firestore `users/{uid}` document the first time an account is created,
/// per the schema in [UserAccountFirestoreMapping.initialDoc].
class AuthRepository {
  AuthRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    GoogleSignIn? googleSignIn,
    AnalyticsService? analytics,
    FirebaseFunctions? functions,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _paths = FirestorePaths(firestore ?? FirebaseFirestore.instance),
        _googleSignIn = googleSignIn ?? GoogleSignIn(scopes: const ['email']),
        _analytics = analytics ?? AnalyticsService(),
        _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirestorePaths _paths;
  final GoogleSignIn _googleSignIn;
  final AnalyticsService _analytics;
  final FirebaseFunctions _functions;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<void> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final uid = credential.user?.uid;
      if (uid == null) {
        throw const AuthFailure('Sign-up did not return a user.');
      }
      final created = await _ensureUserDocument(uid);
      if (created) await _analytics.logSignUp(method: 'email');
    } on FirebaseAuthException catch (e) {
      throw AuthFailure.fromFirebase(e);
    }
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      throw AuthFailure.fromFirebase(e);
    }
  }

  Future<void> signInWithGoogle() async {
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        // User dismissed the Google account picker — not an error.
        return;
      }
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final userCredential = await _auth.signInWithCredential(credential);
      final uid = userCredential.user?.uid;
      if (uid == null) {
        throw const AuthFailure('Google sign-in did not return a user.');
      }
      final created = await _ensureUserDocument(uid);
      if (created) await _analytics.logSignUp(method: 'google');
    } on FirebaseAuthException catch (e) {
      throw AuthFailure.fromFirebase(e);
    }
  }

  Future<void> signOut() async {
    await Future.wait([
      _auth.signOut(),
      _googleSignIn.signOut(),
    ]);
  }

  /// Permanently deletes the signed-in user's account and data via the
  /// `deleteAccount` callable (see functions/src/account/deleteAccount.ts
  /// for exactly what that removes) — irreversible, no undo. Routed
  /// through a Cloud Function rather than client-side deletes for the
  /// same reason as trading: `orders` is an append-only ledger the client
  /// can't delete from directly (firestore.rules), and only server-side
  /// Admin SDK access can delete the Auth account itself. Signs the local
  /// session out afterward, since the ID token now refers to a user that
  /// no longer exists.
  Future<void> deleteAccount() async {
    try {
      await _functions.httpsCallable('deleteAccount').call<Map<String, dynamic>>();
    } on FirebaseFunctionsException catch (e) {
      throw AuthFailure(e.message ?? 'Could not delete your account (${e.code}).');
    }
    await signOut();
  }

  /// Creates the `users/{uid}` document with the starting balance if (and
  /// only if) it doesn't already exist. Safe to call on every sign-in —
  /// covers both brand-new email sign-ups and a user's first Google
  /// sign-in — without ever resetting an existing account. Returns
  /// whether this call was the one that created it, which is also exactly
  /// "was this a brand-new account" — the correct, one-shot signal for
  /// the `sign_up` analytics event (a returning user's sign-in must never
  /// re-fire it).
  Future<bool> _ensureUserDocument(String uid) async {
    final ref = _paths.user(uid);
    var created = false;
    await _firestore.runTransaction((transaction) async {
      final snap = await transaction.get(ref);
      if (!snap.exists) {
        transaction.set(ref, UserAccountFirestoreMapping.initialDoc());
        created = true;
      }
    });
    return created;
  }
}
