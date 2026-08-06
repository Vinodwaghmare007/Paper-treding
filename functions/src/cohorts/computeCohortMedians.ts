import { onSchedule } from "firebase-functions/v2/scheduler";
import { Timestamp } from "firebase-admin/firestore";

import { db } from "../lib/admin";
import { fetchKlines } from "../lib/binance";

// Below this, a "median" is really just exposing 1-2 people's near-exact
// portfolio value under a public doc — the whole point of a cohort median
// is that it's not attributable to anyone. Cohorts smaller than this are
// skipped entirely (no doc written) rather than published with a
// misleading sample size.
const MIN_COHORT_SIZE = 5;

const SIGNUP_BUCKETS = [
  { maxDays: 7, label: "0to6days" },
  { maxDays: 30, label: "7to29days" },
  { maxDays: 90, label: "30to89days" },
  { maxDays: Infinity, label: "90plusDays" },
];

function signupBucket(daysSinceSignup: number): string {
  return (SIGNUP_BUCKETS.find((b) => daysSinceSignup < b.maxDays) ?? SIGNUP_BUCKETS[SIGNUP_BUCKETS.length - 1])
    .label;
}

function median(values: number[]): number {
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid];
}

/**
 * Runs daily: buckets users by (days since signup, starting-balance tier)
 * and writes each cohort's *median* current portfolio value to a public
 * doc — never any individual user's value, and never a cohort small
 * enough that the median is effectively identifiable (see
 * MIN_COHORT_SIZE).
 *
 * NOTE: every account in this app starts with the same 100,000 virtual
 * balance today (UserAccount.startingBalance in the Flutter app), so the
 * starting-balance dimension currently collapses to one tier ("100000")
 * for every user. The bucketing is still written generically by the
 * user's actual starting balance rather than hard-coded, so this is ready
 * to differentiate the moment starting balances become configurable,
 * without needing to revisit this function.
 */
export const computeCohortMedians = onSchedule(
  { schedule: "0 1 * * *", timeZone: "UTC" }, // 01:00 UTC — after the midnight puzzle generation
  async () => {
    const usersSnap = await db.collection("users").get();
    if (usersSnap.empty) return;

    // The app only trades BTCUSDT today; a real multi-symbol version would
    // fetch one price per symbol actually held across the user base.
    const [latestCandle] = await fetchKlines({ symbol: "BTCUSDT", interval: "1m", limit: 1 });
    const btcPrice = latestCandle?.close;

    const now = Date.now();
    const cohorts = new Map<string, number[]>();

    await Promise.all(
      usersSnap.docs.map(async (userDoc) => {
        const userData = userDoc.data();
        const createdAt = userData.created_at as Timestamp | undefined;
        if (!createdAt) return; // pre-cohort-feature accounts with no signup timestamp

        const daysSinceSignup = Math.floor((now - createdAt.toMillis()) / (24 * 60 * 60 * 1000));
        const startingBalanceTier = String(userData.starting_balance ?? 100000);
        const cohortKey = `${signupBucket(daysSinceSignup)}_${startingBalanceTier}`;

        const portfolioSnap = await userDoc.ref.collection("portfolio").get();
        let holdingsValue = 0;
        for (const positionDoc of portfolioSnap.docs) {
          const position = positionDoc.data();
          if (positionDoc.id === "BTCUSDT" && btcPrice !== undefined) {
            holdingsValue += (position.total_quantity as number) * btcPrice;
          } else {
            // No live price available for this symbol server-side yet —
            // fall back to cost basis so the cohort isn't silently
            // dropped, at the cost of slightly stale unrealized P&L.
            holdingsValue += (position.total_quantity as number) * (position.avg_buy_price as number);
          }
        }

        const portfolioValue = (userData.virtual_balance as number) + holdingsValue;
        const bucket = cohorts.get(cohortKey) ?? [];
        bucket.push(portfolioValue);
        cohorts.set(cohortKey, bucket);
      }),
    );

    const batch = db.batch();
    for (const [cohortKey, values] of cohorts) {
      const ref = db.doc(`public_cohort_medians/${cohortKey}`);
      if (values.length < MIN_COHORT_SIZE) {
        batch.delete(ref); // a previously-published cohort may have shrunk
        continue;
      }
      batch.set(ref, {
        median_portfolio_value: Math.round(median(values) * 100) / 100,
        member_count: values.length,
        updated_at: Timestamp.now(),
      });
    }
    await batch.commit();
  },
);
