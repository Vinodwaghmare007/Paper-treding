import { onDocumentCreated } from "firebase-functions/v2/firestore";

import { db } from "../lib/admin";
import { awardCertificationIfNeeded } from "../lib/certifications";
import { MILESTONES } from "../lib/milestones";

/** Testable core: given a newly-created order, award the trade milestone
 * if it's now been earned. Split out from the trigger wrapper below so
 * emulator tests can call it directly without going through a real
 * Firestore-triggered event. */
export async function evaluateTradeMilestonesForOrder(
  userId: string,
  order: Record<string, unknown> | undefined,
): Promise<void> {
  if (!order || order.order_type !== "SELL") return;

  const completedTradesSnap = await db
    .collection(`users/${userId}/orders`)
    .where("order_type", "==", "SELL")
    .count()
    .get();

  if (completedTradesSnap.data().count >= MILESTONES.disciplinedTrader.completedTradesThreshold) {
    await awardCertificationIfNeeded(userId, MILESTONES.disciplinedTrader.type);
  }
}

/**
 * Fires once per new order, not on every read — same count()-on-write
 * shape as updateSkillLevelOnOrder.ts.
 */
export const evaluateTradeMilestones = onDocumentCreated(
  "users/{userId}/orders/{orderId}",
  async (event) => {
    await evaluateTradeMilestonesForOrder(event.params.userId, event.data?.data());
  },
);
