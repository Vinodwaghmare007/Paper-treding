import { onSchedule } from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";

import { db } from "../lib/admin";
import { fetchMarketPrices } from "../lib/coingecko";
import { SYMBOL_TO_COINGECKO_ID } from "../lib/supportedCoins";
import { detectCrossing } from "../alerts/checkPriceAlerts";
import { safeExecuteConditionalOrder } from "./executeConditionalOrder";

/**
 * Runs every minute, same cadence and cheap-when-idle shape as
 * checkPriceAlerts.ts: the first query is `is_active == true` across
 * every user's conditional_orders collection group, and the function
 * returns immediately if that's empty.
 *
 * A separate scheduled function (not folded into checkPriceAlerts) even
 * though both do "fetch prices, detect a crossing" — alerts only ever
 * flip a flag and send a push, this one executes real money-math inside
 * a Firestore transaction per order. Keeping them apart means a bug or
 * slowdown in one never blocks the other, at the cost of one extra
 * CoinGecko call per minute when both have active work — an acceptable
 * trade for a free public API at this scale.
 *
 * v1 scope: only closes/reduces a LONG position (STOP_LOSS fires on a
 * downward crossing, TAKE_PROFIT on an upward one) — see
 * firestore.rules' conditional_orders match block for where that's
 * enforced at creation time.
 */
export const checkConditionalOrders = onSchedule("every 1 minutes", async () => {
  const activeOrders = await db
    .collectionGroup("conditional_orders")
    .where("is_active", "==", true)
    .get();
  if (activeOrders.empty) return;

  const symbols = [...new Set(activeOrders.docs.map((d) => d.data().coin_symbol as string))];
  const coingeckoIds = symbols
    .map((s) => SYMBOL_TO_COINGECKO_ID[s])
    .filter((id): id is string => id !== undefined);
  if (coingeckoIds.length === 0) return;

  let prices: Map<string, number>;
  try {
    prices = await fetchMarketPrices(coingeckoIds);
  } catch (error) {
    // Same reasoning as checkPriceAlerts.ts: a failed fetch just means
    // "try again next minute" — no order doc is touched, so
    // last_checked_price still reflects the last successful check.
    logger.error("[checkConditionalOrders] fetchMarketPrices failed", error);
    return;
  }

  const batch = db.batch();
  let batchHasWrites = false;
  const executions: Array<Promise<void>> = [];

  for (const doc of activeOrders.docs) {
    const order = doc.data();
    const coinSymbol = order.coin_symbol as string;
    const geckoId = SYMBOL_TO_COINGECKO_ID[coinSymbol];
    const currentPrice = geckoId ? prices.get(geckoId) : undefined;
    if (currentPrice === undefined) continue;

    const kind = order.kind as "STOP_LOSS" | "TAKE_PROFIT";
    const triggerPrice = order.trigger_price as number;
    const lastCheckedPrice = order.last_checked_price as number | undefined;
    const uid = doc.ref.parent.parent?.id;
    if (!uid) continue;

    // STOP_LOSS protects a long against the price falling ("below");
    // TAKE_PROFIT locks in a gain as the price rises ("above") — same
    // detectCrossing() the price-alerts function uses, direction implied
    // by which kind of order this is rather than a separate stored field.
    const direction = kind === "STOP_LOSS" ? "below" : "above";

    if (detectCrossing(direction, triggerPrice, lastCheckedPrice, currentPrice)) {
      // Executed via its own transaction (needs to read account/position
      // first, which a plain batch write can't do) — collected and run
      // after the batch below so one order's transaction retrying never
      // blocks writing last_checked_price for the others.
      executions.push(safeExecuteConditionalOrder(uid, doc.ref, currentPrice));
    } else if (currentPrice !== lastCheckedPrice) {
      batch.update(doc.ref, { last_checked_price: currentPrice });
      batchHasWrites = true;
    }
  }

  if (batchHasWrites) await batch.commit();
  await Promise.all(executions);
});
