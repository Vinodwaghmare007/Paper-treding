import { onSchedule } from "firebase-functions/v2/scheduler";
import { FieldValue } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import * as logger from "firebase-functions/logger";

import { db } from "../lib/admin";
import { fetchMarketPrices } from "../lib/coingecko";
import { SYMBOL_TO_COINGECKO_ID } from "../lib/supportedCoins";

export type AlertDirection = "above" | "below";

/**
 * True only on a genuine crossing since the last check — not merely
 * "currently past the target" — which is exactly what stops an alert
 * from re-firing every minute once the price settles past its target.
 *
 * `lastCheckedPrice === undefined` means this is the very first check
 * for this alert (just created, or created before this function's first
 * run touched it). There's no "before" to compare against yet, so this
 * deliberately does NOT fire on the first check even if the price is
 * already past the target — an alert means "tell me when it crosses this
 * line," not "tell me if it's already on the far side of this line." The
 * first check only seeds the baseline; a real crossing has to happen
 * after that.
 */
export function detectCrossing(
  direction: AlertDirection,
  targetPrice: number,
  lastCheckedPrice: number | undefined,
  currentPrice: number,
): boolean {
  if (lastCheckedPrice === undefined) return false;
  if (direction === "above") {
    return lastCheckedPrice < targetPrice && currentPrice >= targetPrice;
  }
  return lastCheckedPrice > targetPrice && currentPrice <= targetPrice;
}

/** Sends one push per registered device token for `uid` — a user with no
 * tokens (denied notification permission, or hasn't opened the app since
 * this feature shipped) is a silent no-op, not an error; the alert still
 * shows as triggered in-app either way. */
async function sendAlertPush(
  uid: string,
  coinSymbol: string,
  direction: AlertDirection,
  targetPrice: number,
): Promise<void> {
  const tokensSnap = await db.collection(`users/${uid}/fcm_tokens`).get();
  if (tokensSnap.empty) return;

  const tokens = tokensSnap.docs.map((d) => d.id);
  const base = coinSymbol.replace("USDT", "");
  const verb = direction === "above" ? "risen above" : "fallen below";

  try {
    await getMessaging().sendEachForMulticast({
      tokens,
      notification: {
        title: `${base} price alert`,
        body: `${base} has ${verb} $${targetPrice.toLocaleString()}`,
      },
      android: { notification: { channelId: "price_alerts" } },
    });
  } catch (error) {
    // A push failure (e.g. every token stale) shouldn't stop the alert
    // from being marked triggered — the in-app history is still correct
    // either way, and this is a scheduled function with no caller to
    // propagate the error to.
    logger.error(`[checkPriceAlerts] push failed for uid=${uid}`, error);
  }
}

/**
 * Runs every minute. Cheap when nothing needs checking: the very first
 * query is `is_active == true` across every user's alerts collection
 * group, and the function returns immediately if that's empty — no
 * CoinGecko call, no per-alert work, no writes.
 */
export const checkPriceAlerts = onSchedule("every 1 minutes", async () => {
  const activeAlerts = await db.collectionGroup("alerts").where("is_active", "==", true).get();
  if (activeAlerts.empty) return;

  const symbols = [...new Set(activeAlerts.docs.map((d) => d.data().coin_symbol as string))];
  const coingeckoIds = symbols
    .map((s) => SYMBOL_TO_COINGECKO_ID[s])
    .filter((id): id is string => id !== undefined);
  if (coingeckoIds.length === 0) return;

  let prices: Map<string, number>;
  try {
    prices = await fetchMarketPrices(coingeckoIds);
  } catch (error) {
    // A single failed CoinGecko fetch just means "try again next minute"
    // — no alert doc is touched, so `last_checked_price` still reflects
    // the last successful check, and no crossing gets missed or falsely
    // detected off a partial/failed fetch.
    logger.error("[checkPriceAlerts] fetchMarketPrices failed", error);
    return;
  }

  const batch = db.batch();
  let batchHasWrites = false;
  const pushes: Array<Promise<void>> = [];

  for (const doc of activeAlerts.docs) {
    const alert = doc.data();
    const coinSymbol = alert.coin_symbol as string;
    const geckoId = SYMBOL_TO_COINGECKO_ID[coinSymbol];
    const currentPrice = geckoId ? prices.get(geckoId) : undefined;
    if (currentPrice === undefined) continue;

    const direction = alert.direction as AlertDirection;
    const targetPrice = alert.target_price as number;
    const lastCheckedPrice = alert.last_checked_price as number | undefined;
    const uid = doc.ref.parent.parent?.id;
    if (!uid) continue;

    if (detectCrossing(direction, targetPrice, lastCheckedPrice, currentPrice)) {
      batch.update(doc.ref, {
        is_active: false,
        triggered_at: FieldValue.serverTimestamp(),
        last_checked_price: currentPrice,
      });
      batchHasWrites = true;
      pushes.push(sendAlertPush(uid, coinSymbol, direction, targetPrice));
    } else if (currentPrice !== lastCheckedPrice) {
      batch.update(doc.ref, { last_checked_price: currentPrice });
      batchHasWrites = true;
    }
  }

  if (batchHasWrites) await batch.commit();
  await Promise.all(pushes);
});
