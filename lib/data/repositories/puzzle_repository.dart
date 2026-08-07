import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/daily_puzzle.dart';
import '../firestore/firestore_paths.dart';
import '../firestore/puzzle_mappers.dart';

/// Read side of the daily chart puzzle — public and readable with no auth
/// (see the `daily_puzzle` match block in firestore.rules). Submitting an
/// answer goes through the `submitPuzzleAnswer` callable instead (see
/// SubmitPuzzleAnswerUseCase), since scoring and streak updates have to
/// happen atomically against the answer doc this repository can never read.
class PuzzleRepository {
  PuzzleRepository(FirebaseFirestore firestore)
      : _paths = FirestorePaths(firestore);

  final FirestorePaths _paths;

  /// Null until generateDailyPuzzle.ts has produced a doc for [date].
  Stream<DailyPuzzle?> watchPuzzle(String date) {
    return _paths.dailyPuzzle(date).snapshots().map(
          (doc) => doc.exists ? DailyPuzzleFirestoreMapping.fromDoc(doc) : null,
        );
  }
}
