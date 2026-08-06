import { HttpsError, onCall } from "firebase-functions/v2/https";
import { FieldValue, Timestamp } from "firebase-admin/firestore";

import { db } from "../lib/admin";

type Guess = "up" | "down";

function isValidGuess(value: unknown): value is Guess {
  return value === "up" || value === "down";
}

function yesterday(dateStr: string): string {
  const d = new Date(`${dateStr}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() - 1);
  return d.toISOString().slice(0, 10);
}

/**
 * Scores a daily puzzle guess. Works for signed-out players too — "no
 * login required to play" per the product spec — but streak tracking
 * only applies when `request.auth` is present, since a streak has to live
 * somewhere durable (users/{uid}) that an anonymous session doesn't have.
 *
 * The correct answer is never sent to the client until *after* this
 * function has scored the guess against the copy of it we already hold
 * server-side (`daily_puzzle/{date}/secret/answer`, unreadable by clients
 * — see firestore.rules).
 */
export const submitPuzzleAnswer = onCall(async (request) => {
  const date = request.data?.date;
  const guess = request.data?.guess;
  if (typeof date !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(date)) {
    throw new HttpsError("invalid-argument", "date must be an ISO date string (YYYY-MM-DD).");
  }
  if (!isValidGuess(guess)) {
    throw new HttpsError("invalid-argument", 'guess must be "up" or "down".');
  }

  const puzzleRef = db.doc(`daily_puzzle/${date}`);
  const answerRef = db.doc(`daily_puzzle/${date}/secret/answer`);
  const uid = request.auth?.uid;
  const userRef = uid ? db.doc(`users/${uid}`) : null;

  const result = await db.runTransaction(async (tx) => {
    const [puzzleSnap, answerSnap, userSnap] = await Promise.all([
      tx.get(puzzleRef),
      tx.get(answerRef),
      userRef ? tx.get(userRef) : Promise.resolve(null),
    ]);

    if (!puzzleSnap.exists || !answerSnap.exists) {
      throw new HttpsError("not-found", `No puzzle found for ${date}.`);
    }

    if (userSnap && userSnap.exists && userSnap.data()?.puzzle_last_played_date === date) {
      throw new HttpsError("already-exists", "You've already played today's puzzle.");
    }

    const answerData = answerSnap.data()!;
    const correctAnswer = answerData.correct_answer as Guess;
    const actualMovePct = answerData.actual_move_pct as number;
    const correct = guess === correctAnswer;

    tx.update(puzzleRef, {
      total_answers: FieldValue.increment(1),
      correct_answers: FieldValue.increment(correct ? 1 : 0),
    });

    if (userRef) {
      const previousDate = userSnap?.data()?.puzzle_last_played_date as string | undefined;
      const previousStreak = (userSnap?.data()?.puzzle_streak as number | undefined) ?? 0;
      const newStreak = previousDate === yesterday(date) ? previousStreak + 1 : 1;
      tx.set(
        userRef,
        {
          puzzle_streak: newStreak,
          puzzle_last_played_date: date,
          puzzle_last_played_at: Timestamp.now(),
        },
        { merge: true },
      );
    }

    const puzzleData = puzzleSnap.data()!;
    const totalAfter = (puzzleData.total_answers ?? 0) + 1;
    const correctAfter = (puzzleData.correct_answers ?? 0) + (correct ? 1 : 0);

    return {
      correct,
      correctAnswer,
      actualMovePct,
      aggregateCorrectPct: Math.round((correctAfter / totalAfter) * 1000) / 10,
      totalAnswers: totalAfter,
    };
  });

  return result;
});
