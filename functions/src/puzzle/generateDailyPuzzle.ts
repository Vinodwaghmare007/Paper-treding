import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions/v2";
import { Timestamp } from "firebase-admin/firestore";

import { db } from "../lib/admin";
import { fetchKlines } from "../lib/binance";
import { seededRandom } from "../lib/seededRandom";

const SYMBOL = "BTCUSDT";
const SHOWN_CANDLES = 45; // 45 minutes shown
const REVEAL_CANDLES = 15; // 15 minutes masked — the thing being guessed
const TOTAL_CANDLES = SHOWN_CANDLES + REVEAL_CANDLES;
const MAX_ATTEMPTS = 5;

function utcDateString(date: Date): string {
  return date.toISOString().slice(0, 10); // "YYYY-MM-DD"
}

/** Picks a deterministic-by-date window somewhere in the last ~3 years,
 * leaving a 2-day buffer so the "reveal" candles are always real, already-
 * closed history rather than reaching into data that doesn't exist yet. */
function pickWindowStartMs(dateSeed: string, attempt: number): number {
  const bufferMs = 2 * 24 * 60 * 60 * 1000;
  const rangeMs = 3 * 365 * 24 * 60 * 60 * 1000;
  const rangeEnd = Date.now() - bufferMs;
  const rangeStart = rangeEnd - rangeMs;
  const fraction = seededRandom(`${dateSeed}:${attempt}`);
  const offsetMs = Math.floor(fraction * (rangeEnd - rangeStart));
  const raw = rangeStart + offsetMs;
  // Round down to the hour for a clean, human-readable window boundary.
  return raw - (raw % (60 * 60 * 1000));
}

/**
 * Runs daily at midnight UTC: picks one deterministic historical 1-hour
 * window (by date, so every user gets the same puzzle), shows the first
 * 45 minutes, and hides the actual outcome of the last 15.
 *
 * Splits the write into two docs on purpose:
 * - `daily_puzzle/{date}` — public, everything needed to *render* the
 *   puzzle (shown candles) plus the running aggregate stats.
 * - `daily_puzzle/{date}/secret/answer` — never client-readable (see
 *   firestore.rules); only submitPuzzleAnswer's Cloud Function reads it.
 *   Keeping the answer out of the public doc is a deliberate deviation
 *   from a flatter single-document schema: a single public doc containing
 *   `correct_answer` would let anyone read the answer straight out of
 *   Firestore before playing, which defeats the entire feature.
 */
export const generateDailyPuzzle = onSchedule(
  { schedule: "0 0 * * *", timeZone: "UTC" },
  async () => {
    const dateSeed = utcDateString(new Date());
    const puzzleRef = db.doc(`daily_puzzle/${dateSeed}`);

    if ((await puzzleRef.get()).exists) {
      logger.info(`Puzzle for ${dateSeed} already exists — skipping.`);
      return;
    }

    let attempt = 0;
    while (attempt < MAX_ATTEMPTS) {
      const windowStartMs = pickWindowStartMs(dateSeed, attempt);
      try {
        const candles = await fetchKlines({
          symbol: SYMBOL,
          interval: "1m",
          startTimeMs: windowStartMs,
          limit: TOTAL_CANDLES,
        });

        if (candles.length < TOTAL_CANDLES) {
          logger.warn(
            `Attempt ${attempt} for ${dateSeed}: only ${candles.length}/${TOTAL_CANDLES} candles, retrying.`,
          );
          attempt++;
          continue;
        }

        const shown = candles.slice(0, SHOWN_CANDLES);
        const reveal = candles.slice(SHOWN_CANDLES, TOTAL_CANDLES);
        const lastShownClose = shown[shown.length - 1].close;
        const finalClose = reveal[reveal.length - 1].close;
        const actualMovePct = ((finalClose - lastShownClose) / lastShownClose) * 100;
        const correctAnswer = actualMovePct >= 0 ? "up" : "down";

        await puzzleRef.set({
          symbol: SYMBOL,
          shown_candles: shown,
          window_start_ms: windowStartMs,
          generated_at: Timestamp.now(),
          total_answers: 0,
          correct_answers: 0,
        });
        await db.doc(`daily_puzzle/${dateSeed}/secret/answer`).set({
          correct_answer: correctAnswer,
          actual_move_pct: Math.round(actualMovePct * 100) / 100,
          reveal_candles: reveal,
        });

        logger.info(`Generated puzzle for ${dateSeed}: ${correctAnswer} (${actualMovePct.toFixed(2)}%)`);
        return;
      } catch (error) {
        logger.error(`Attempt ${attempt} for ${dateSeed} failed`, error);
        attempt++;
      }
    }

    logger.error(`Failed to generate a puzzle for ${dateSeed} after ${MAX_ATTEMPTS} attempts.`);
  },
);
