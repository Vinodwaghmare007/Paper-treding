import { FieldValue } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import { db } from "../lib/admin";

/**
 * Bumps `users/{uid}.backtest_run_count` by 1.
 *
 * Backtests run entirely on-device (see backtest_runner.dart) and are
 * never persisted — this callable exists solely to give
 * evaluateBacktestMilestones.ts a Firestore write to trigger on, per the
 * "evaluate on write, not on every read" requirement. It deliberately
 * stores only a counter, not backtest parameters/results.
 */
export const recordBacktestCompletion = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  await db.doc(`users/${uid}`).set(
    { backtest_run_count: FieldValue.increment(1) },
    { merge: true },
  );
});
