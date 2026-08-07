import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/puzzle_repository.dart';
import '../../data/sources/anonymous_puzzle_play_counter.dart';
import '../../domain/entities/daily_puzzle.dart';
import '../../domain/usecases/submit_puzzle_answer.dart';
import '../auth/auth_providers.dart';

final puzzleRepositoryProvider = Provider<PuzzleRepository>((ref) {
  return PuzzleRepository(ref.watch(firebaseFirestoreProvider));
});

final submitPuzzleAnswerUseCaseProvider =
    Provider<SubmitPuzzleAnswerUseCase>((ref) {
  return SubmitPuzzleAnswerUseCase(functions: FirebaseFunctions.instance);
});

final anonymousPuzzlePlayCounterProvider =
    Provider<AnonymousPuzzlePlayCounter>((ref) => AnonymousPuzzlePlayCounter());

/// Today's UTC date as YYYY-MM-DD — matches generateDailyPuzzle.ts's
/// `daily_puzzle/{date}` doc id exactly, since both derive it the same way
/// (`Date.toISOString().slice(0, 10)` server-side).
String todayPuzzleDate() => DateTime.now().toUtc().toIso8601String().substring(0, 10);

final todayPuzzleProvider = StreamProvider<DailyPuzzle?>((ref) {
  return ref.watch(puzzleRepositoryProvider).watchPuzzle(todayPuzzleDate());
});
