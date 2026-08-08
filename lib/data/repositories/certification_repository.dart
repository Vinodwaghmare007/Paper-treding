import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../domain/entities/certification.dart';
import '../firestore/firestore_paths.dart';

/// Read side of certifications (server-written only, see
/// functions/src/certifications/*.ts) plus the write-side signal that
/// feeds the backtest milestone — recording a completed backtest run.
class CertificationRepository {
  CertificationRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : _paths = FirestorePaths(firestore ?? FirebaseFirestore.instance),
        _functions = functions ?? FirebaseFunctions.instance;

  final FirestorePaths _paths;
  final FirebaseFunctions _functions;

  Stream<List<Certification>> watchCertifications(String uid) {
    return _paths.certifications(uid).snapshots().map(
          (snap) => snap.docs
              .map((doc) => Certification.fromMap(doc.data()))
              .toList(growable: false),
        );
  }

  /// Tells the backend a backtest just finished — see
  /// recordBacktestCompletion.ts. Deliberately fire-and-forget from the
  /// caller's perspective (backtester_screen.dart doesn't block or show
  /// an error for this); a dropped call just means one backtest doesn't
  /// count toward the milestone, not a broken feature.
  Future<void> recordBacktestCompletion() {
    return _functions.httpsCallable('recordBacktestCompletion').call<void>();
  }
}
