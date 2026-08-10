import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/kline_tick.dart';
import '../../domain/entities/daily_puzzle.dart';
import '../../domain/entities/puzzle_guess.dart';
import '../../domain/usecases/submit_puzzle_answer.dart';
import '../../l10n/generated/app_localizations.dart';
import '../auth/auth_providers.dart';
import '../chart/trading_chart_view.dart';
import '../portfolio/portfolio_providers.dart';
import 'puzzle_providers.dart';

/// No login required to play (see puzzle_providers.dart / submit_puzzle_
/// answer.dart) — this screen is reachable both pre-auth (pushed from
/// SignInScreen) and from the signed-in HomeShell tab.
class DailyPuzzleScreen extends ConsumerWidget {
  const DailyPuzzleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final puzzleAsync = ref.watch(todayPuzzleProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E222D),
        title: Text(l10n.puzzleTitle),
        actions: [
          if (ref.watch(currentUidProvider) != null) const _StreakBadge(),
        ],
      ),
      body: puzzleAsync.when(
        data: (puzzle) => puzzle == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    l10n.puzzleNotReady,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54),
                  ),
                ),
              )
            : _PuzzleBody(key: ValueKey(puzzle.date), puzzle: puzzle),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(l10n.puzzleLoadError(e.toString()),
              style: const TextStyle(color: Color(0xFFEF5350))),
        ),
      ),
    );
  }
}

class _StreakBadge extends ConsumerWidget {
  const _StreakBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streak = ref.watch(accountStreamProvider).valueOrNull?.puzzleStreak ?? 0;
    if (streak == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.local_fire_department, color: Colors.orange, size: 18),
            const SizedBox(width: 2),
            Text('$streak', style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

class _PuzzleBody extends ConsumerStatefulWidget {
  const _PuzzleBody({super.key, required this.puzzle});

  final DailyPuzzle puzzle;

  @override
  ConsumerState<_PuzzleBody> createState() => _PuzzleBodyState();
}

class _PuzzleBodyState extends ConsumerState<_PuzzleBody> {
  final _revealController = StreamController<KlineTick>.broadcast();
  PuzzleAnswerResult? _result;
  bool _submitting = false;

  @override
  void dispose() {
    _revealController.close();
    super.dispose();
  }

  Future<void> _answer(PuzzleGuess guess) async {
    if (_submitting || _result != null) return;
    setState(() => _submitting = true);

    try {
      final result = await ref.read(submitPuzzleAnswerUseCaseProvider).submit(
            date: widget.puzzle.date,
            guess: guess,
          );
      if (!mounted) return;
      setState(() {
        _result = result;
        _submitting = false;
      });
      unawaited(_animateReveal(result.revealCandles));
      unawaited(_maybePromptSignup());
      unawaited(ref.read(analyticsServiceProvider).logPuzzlePlayed(correct: result.correct));
    } on PuzzleAnswerRejected catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _animateReveal(List<Candle> revealCandles) async {
    for (final candle in revealCandles) {
      if (!mounted) return;
      _revealController.add(KlineTick(
        eventTimeMs: candle.closeTimeMs,
        symbol: widget.puzzle.symbol,
        interval: '1m',
        candle: candle,
        isCandleClosed: true,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
  }

  /// The signup nudge is purely a local pacing device — it counts plays on
  /// this device, not a server-enforced limit. Enforcing "one play per
  /// day" server-side would need a durable per-player identity, which an
  /// anonymous player doesn't have; that's an acceptable gap for a free,
  /// no-login practice puzzle rather than something worth an anonymous-
  /// auth system just to close.
  Future<void> _maybePromptSignup() async {
    if (ref.read(currentUidProvider) != null) return;
    final count = await ref.read(anonymousPuzzlePlayCounterProvider).increment();
    if (count >= 3 && mounted) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text(l10n.puzzleSignupPrompt),
          action: SnackBarAction(
            label: l10n.puzzleSignupAction,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final result = _result;
    return Column(
      children: [
        _StatsHeader(puzzle: widget.puzzle, result: result),
        Expanded(
          child: TradingChartView(
            fetchSeedCandles: () async => widget.puzzle.shownCandles,
            ticks: _revealController.stream,
            interval: '1m',
          ),
        ),
        if (result != null) _ResultBanner(result: result),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: result == null && !_submitting
                      ? () => _answer(PuzzleGuess.up)
                      : null,
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF26A69A)),
                  icon: const Icon(Icons.arrow_upward),
                  label: Text(l10n.puzzleUpButton),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: result == null && !_submitting
                      ? () => _answer(PuzzleGuess.down)
                      : null,
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF5350)),
                  icon: const Icon(Icons.arrow_downward),
                  label: Text(l10n.puzzleDownButton),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatsHeader extends StatelessWidget {
  const _StatsHeader({required this.puzzle, required this.result});

  final DailyPuzzle puzzle;
  final PuzzleAnswerResult? result;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final pct = result?.aggregateCorrectPct ?? puzzle.correctPct;
    final totalAnswers = result?.totalAnswers ?? puzzle.totalAnswers;
    return Container(
      width: double.infinity,
      color: const Color(0xFF1E222D),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.puzzleQuestion(puzzle.symbol),
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 4),
          Text(
            pct == null
                ? l10n.puzzleBeFirst
                : l10n.puzzlePlayersCorrect(pct.toStringAsFixed(0), totalAnswers),
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(height: 2),
          // This screen is reachable without an account (see sign_in_screen
          // .dart), so it can't rely on HomeShell's shared SimulatedFooter
          // being present — it needs its own reminder regardless of entry
          // point.
          Text(
            l10n.puzzlePracticeOnlyNote,
            // white70 rather than the dimmer white24/38 used for purely
            // decorative text elsewhere: safety-relevant copy needs to
            // clear WCAG AA contrast against this dark background.
            style: const TextStyle(color: Colors.white70, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _ResultBanner extends StatelessWidget {
  const _ResultBanner({required this.result});

  final PuzzleAnswerResult result;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final color = result.correct ? const Color(0xFF26A69A) : const Color(0xFFEF5350);
    final direction =
        result.correctAnswer == PuzzleGuess.up ? l10n.puzzleDirectionUp : l10n.puzzleDirectionDown;
    final sign = result.actualMovePct >= 0 ? '+' : '';
    final move = '$sign${result.actualMovePct.toStringAsFixed(2)}%';
    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.15),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(
        result.correct
            ? l10n.puzzleCorrectResult(direction, move)
            : l10n.puzzleIncorrectResult(direction, move),
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
