import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/leaderboard_entry.dart';
import '../firestore/firestore_paths.dart';

class LeaderboardRepository {
  LeaderboardRepository(FirebaseFirestore firestore) : _paths = FirestorePaths(firestore);

  final FirestorePaths _paths;

  Stream<List<LeaderboardEntry>> watchLeaderboard(LeaderboardWindow window) {
    return _paths.publicLeaderboard(window.docId).snapshots().map((snap) {
      final entries = snap.data()?['entries'] as List<dynamic>? ?? const [];
      return entries
          .map((e) => LeaderboardEntry.fromMap(e as Map<String, dynamic>))
          .toList(growable: false);
    });
  }
}
