import 'package:cloud_functions/cloud_functions.dart';

import '../../data/models/kline_tick.dart';
import '../entities/puzzle_guess.dart' show PuzzleGuess, PuzzleGuessCode;

/// A puzzle answer submission was rejected before it could be scored.
sealed class PuzzleAnswerRejected implements Exception {
  const PuzzleAnswerRejected(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Malformed `date`/`guess` arguments — shouldn't happen from this app's
/// own UI, but the server validates independently regardless.
class PuzzleInvalidArgumentException extends PuzzleAnswerRejected {
  const PuzzleInvalidArgumentException(super.message);
}

/// No puzzle exists yet for the requested date (e.g. generateDailyPuzzle.ts
/// hasn't run yet today).
class PuzzleNotFoundException extends PuzzleAnswerRejected {
  const PuzzleNotFoundException(super.message);
}

/// This player (by uid) has already answered today's puzzle.
class PuzzleAlreadyAnsweredException extends PuzzleAnswerRejected {
  const PuzzleAlreadyAnsweredException(super.message);
}

class PuzzleAnswerUnknownException extends PuzzleAnswerRejected {
  const PuzzleAnswerUnknownException(super.message);
}

/// The result of a scored guess — everything needed to show the reveal:
/// whether the player was right, the actual outcome, the candles that
/// happened during the masked window (so the chart can render them), and
/// the running "X% of players got it right today" aggregate.
class PuzzleAnswerResult {
  const PuzzleAnswerResult({
    required this.correct,
    required this.correctAnswer,
    required this.actualMovePct,
    required this.revealCandles,
    required this.aggregateCorrectPct,
    required this.totalAnswers,
  });

  final bool correct;
  final PuzzleGuess correctAnswer;
  final double actualMovePct;
  final List<Candle> revealCandles;
  final double aggregateCorrectPct;
  final int totalAnswers;
}

/// Submits a guess via the `submitPuzzleAnswer` Cloud Function callable.
///
/// This has to be a callable rather than a direct Firestore write for the
/// same reason as chat messages: scoring a guess means comparing it
/// against `daily_puzzle/{date}/secret/answer`, which is never
/// client-readable (see firestore.rules) — only the Cloud Function's own
/// Admin SDK access can do that comparison, atomically, in the same
/// transaction that records the guess and updates the streak.
class SubmitPuzzleAnswerUseCase {
  SubmitPuzzleAnswerUseCase({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  Future<PuzzleAnswerResult> submit({
    required String date,
    required PuzzleGuess guess,
  }) async {
    try {
      final callable = _functions.httpsCallable('submitPuzzleAnswer');
      final response = await callable.call({
        'date': date,
        'guess': guess.code,
      });
      return _parseResult(_asStringKeyedMap(response.data));
    } on FirebaseFunctionsException catch (e) {
      throw _mapError(e);
    }
  }

  PuzzleAnswerResult _parseResult(Map<String, dynamic> data) {
    final revealCandlesRaw = data['revealCandles'] as List<dynamic>? ?? const [];
    return PuzzleAnswerResult(
      correct: data['correct'] as bool,
      correctAnswer: PuzzleGuessCode.fromCode(data['correctAnswer'] as String),
      actualMovePct: (data['actualMovePct'] as num).toDouble(),
      revealCandles: revealCandlesRaw
          .map((e) => Candle.fromMap(_asStringKeyedMap(e)))
          .toList(growable: false),
      aggregateCorrectPct: (data['aggregateCorrectPct'] as num).toDouble(),
      totalAnswers: (data['totalAnswers'] as num).toInt(),
    );
  }

  Map<String, dynamic> _asStringKeyedMap(Object? value) {
    if (value is Map) {
      return value.map((key, v) => MapEntry(key.toString(), v));
    }
    throw StateError('Expected a map result from submitPuzzleAnswer, got: $value');
  }

  PuzzleAnswerRejected _mapError(FirebaseFunctionsException e) {
    final message = e.message ?? 'Could not submit your answer.';
    return switch (e.code) {
      'invalid-argument' => PuzzleInvalidArgumentException(message),
      'not-found' => PuzzleNotFoundException(message),
      'already-exists' => PuzzleAlreadyAnsweredException(message),
      _ => PuzzleAnswerUnknownException(message),
    };
  }
}
