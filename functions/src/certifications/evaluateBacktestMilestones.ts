import { onDocumentUpdated } from "firebase-functions/v2/firestore";

import { awardCertificationIfNeeded } from "../lib/certifications";
import { MILESTONES } from "../lib/milestones";

/** Testable core, split out for the same reason as
 * evaluateTradeMilestonesForOrder — see that file. */
export async function evaluateBacktestMilestonesForCounts(
  userId: string,
  beforeCount: number,
  afterCount: number,
): Promise<void> {
  if (afterCount <= beforeCount) return;
  if (afterCount >= MILESTONES.backtesterMaster.backtestRunThreshold) {
    await awardCertificationIfNeeded(userId, MILESTONES.backtesterMaster.type);
  }
}

/**
 * `users/{userId}` is written on every balance change, skill_level update,
 * puzzle streak bump, etc. — this trigger fires on all of those, but the
 * before/after count comparison above is what keeps it a cheap no-op on
 * every write that isn't a backtest completion, rather than re-querying
 * anything.
 */
export const evaluateBacktestMilestones = onDocumentUpdated(
  "users/{userId}",
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!after) return;

    const beforeCount = (before?.backtest_run_count as number | undefined) ?? 0;
    const afterCount = (after.backtest_run_count as number | undefined) ?? 0;
    await evaluateBacktestMilestonesForCounts(event.params.userId, beforeCount, afterCount);
  },
);
