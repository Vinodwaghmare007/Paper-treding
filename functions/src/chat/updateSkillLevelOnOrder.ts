import { onDocumentCreated } from "firebase-functions/v2/firestore";

import { db } from "../lib/admin";
import { skillLevelForCompletedTrades } from "../lib/skillLevel";

/**
 * Keeps `users/{uid}.skill_level` in sync with completed-trade count.
 *
 * This exists because Firestore *security rules* can't run a count()
 * aggregation query to compute skill level on the fly — rules can only
 * read single documents by known path (`get()`/`exists()`), not query a
 * collection. Caching a server-computed skill_level field onto the user
 * doc (writable only via this Cloud Function, never the client) is what
 * lets firestore.rules cheaply and trustworthily gate chat room reads by
 * skill level with a single get().
 */
export const updateSkillLevelOnOrder = onDocumentCreated(
  "users/{userId}/orders/{orderId}",
  async (event) => {
    const order = event.data?.data();
    // Only SELL orders count as a "completed trade" — an open BUY isn't a
    // closed round-trip yet.
    if (!order || order.order_type !== "SELL") return;

    const userId = event.params.userId;
    const completedTradesSnap = await db
      .collection(`users/${userId}/orders`)
      .where("order_type", "==", "SELL")
      .count()
      .get();

    const skillLevel = skillLevelForCompletedTrades(completedTradesSnap.data().count);
    await db.doc(`users/${userId}`).set({ skill_level: skillLevel }, { merge: true });
  },
);
