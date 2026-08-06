import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/auth_repository.dart';

final firebaseFirestoreProvider =
    Provider<FirebaseFirestore>((ref) => FirebaseFirestore.instance);

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(firestore: ref.watch(firebaseFirestoreProvider));
});

final authStateChangesProvider = StreamProvider<User?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});

/// The signed-in user's uid, or null while signed out. UI that requires a
/// user should be built beneath [AuthGate], which guarantees this is
/// non-null whenever its child tree runs.
final currentUidProvider = Provider<String?>((ref) {
  return ref.watch(authStateChangesProvider).valueOrNull?.uid;
});
