/// Mirrored in functions/src/puzzle/submitPuzzleAnswer.ts's `Guess` type —
/// keep both in sync.
enum PuzzleGuess { up, down }

extension PuzzleGuessCode on PuzzleGuess {
  String get code => switch (this) {
        PuzzleGuess.up => 'up',
        PuzzleGuess.down => 'down',
      };

  static PuzzleGuess fromCode(String code) => switch (code) {
        'up' => PuzzleGuess.up,
        'down' => PuzzleGuess.down,
        _ => throw ArgumentError.value(code, 'code', 'Unknown puzzle guess'),
      };
}
