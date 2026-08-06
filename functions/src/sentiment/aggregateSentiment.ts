import { onSchedule } from "firebase-functions/v2/scheduler";
import { Timestamp } from "firebase-admin/firestore";

import { db } from "../lib/admin";

// The app currently only trades BTCUSDT (see lib/features/ticker), but
// sentiment is written per-symbol so this extends cleanly if that changes.
const TRACKED_SYMBOLS = ["BTCUSDT"];

/**
 * Runs hourly: aggregates the last hour of BUY vs SELL orders across every
 * user for each tracked symbol into a single public, anonymous doc. Only
 * ever writes counts and percentages — never a user id, order id, or
 * anything traceable back to an individual trade.
 *
 * PATH NOTE: the product spec describes this as living at
 * `public/sentiment/{symbol}`, but that's a 3-segment path, which in
 * Firestore addresses a *collection* (segments alternate collection/doc),
 * not a writable document — collection `public`, then within document
 * `sentiment`, an implied `{symbol}` sub-collection with no document
 * specified. The same issue applies to every other "public/..." path in
 * this phase's spec (market_weather, cohort_medians). Using flat top-level
 * collections instead (`public_sentiment/{symbol}`,
 * `public_market_weather/current`, `public_cohort_medians/{cohortKey}`)
 * keeps the same intent — small, public, Cloud-Function-only docs — as
 * valid 2-segment document paths that are also simpler to target
 * individually in security rules.
 */
export const aggregateCommunitySentiment = onSchedule(
  { schedule: "every 60 minutes", timeZone: "UTC" },
  async () => {
    const oneHourAgo = Timestamp.fromMillis(Date.now() - 60 * 60 * 1000);

    for (const symbol of TRACKED_SYMBOLS) {
      const ordersSnap = await db
        .collectionGroup("orders")
        .where("coin_symbol", "==", symbol)
        .where("timestamp", ">=", oneHourAgo)
        .get();

      let buyCount = 0;
      let sellCount = 0;
      for (const doc of ordersSnap.docs) {
        const type = doc.data().order_type;
        if (type === "BUY") buyCount++;
        else if (type === "SELL") sellCount++;
      }

      const total = buyCount + sellCount;
      const bullishPct = total === 0 ? null : Math.round((buyCount / total) * 1000) / 10;
      const bearishPct = total === 0 ? null : Math.round((sellCount / total) * 1000) / 10;

      await db.doc(`public_sentiment/${symbol}`).set({
        symbol,
        bullish_pct: bullishPct,
        bearish_pct: bearishPct,
        total_orders: total,
        window_minutes: 60,
        updated_at: Timestamp.now(),
      });
    }
  },
);
