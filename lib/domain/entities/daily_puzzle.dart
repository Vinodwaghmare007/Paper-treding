import '../../data/models/kline_tick.dart';

/// The public half of a daily chart puzzle — everything needed to *render*
/// it and show the running aggregate stats. The answer itself lives only
/// server-side until a player has submitted a guess (see
/// submit_puzzle_answer.dart). Pure domain entity aside from reusing
/// [Candle], which is already a plain data model with no Firestore
/// coupling — see the note on [DailyPuzzleFirestoreMapping] for why
/// duplicating it here would be pure boilerplate.
class DailyPuzzle {
  const DailyPuzzle({
    required this.date,
    required this.symbol,
    required this.shownCandles,
    required this.totalAnswers,
    required this.correctAnswers,
  });

  /// ISO date string (YYYY-MM-DD, UTC) — also the Firestore doc id.
  final String date;
  final String symbol;
  final List<Candle> shownCandles;
  final int totalAnswers;
  final int correctAnswers;

  /// Null until at least one player has answered.
  double? get correctPct =>
      totalAnswers == 0 ? null : correctAnswers / totalAnswers * 100;
}
