import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/daily_puzzle.dart';
import '../models/kline_tick.dart';

/// Converts between [DailyPuzzle] and its Firestore document shape. Kept
/// out of `domain/` so the entity stays Firebase-free — [Candle] itself
/// already lives in `data/models` rather than `domain/entities` (it
/// predates this feature, shared with the live ticker and Market Replay),
/// so this mapper only has to translate the puzzle doc's own fields.
extension DailyPuzzleFirestoreMapping on DailyPuzzle {
  static DailyPuzzle fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) {
      throw StateError('daily_puzzle/${doc.id} does not exist');
    }
    final shownRaw = data['shown_candles'] as List<dynamic>? ?? const [];
    return DailyPuzzle(
      date: doc.id,
      symbol: data['symbol'] as String? ?? 'BTCUSDT',
      shownCandles: shownRaw
          .map((e) => Candle.fromMap(e as Map<String, dynamic>))
          .toList(growable: false),
      totalAnswers: (data['total_answers'] as num?)?.toInt() ?? 0,
      correctAnswers: (data['correct_answers'] as num?)?.toInt() ?? 0,
    );
  }
}
