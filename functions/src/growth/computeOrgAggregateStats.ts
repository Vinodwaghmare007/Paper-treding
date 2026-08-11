import { onSchedule } from "firebase-functions/v2/scheduler";
import { Timestamp } from "firebase-admin/firestore";

import { db } from "../lib/admin";

/**
 * Runs daily: for every org, averages each enrolled member's
 * discipline_score (from their own profile_stats/data — Admin SDK read,
 * bypassing the isProfilePublic() rule that would normally hide a private
 * profile from anyone else) into one anonymous
 * organizations/{orgId}/aggregate_stats/data doc. This is precisely what
 * lets org_admin_dashboard.dart show a cohort average without the admin
 * ever reading an individual student's private stats directly — the admin
 * only ever has read access to aggregate_stats and members (display_name +
 * joined_at only), never to profile_stats itself.
 */
export const computeOrgAggregateStats = onSchedule(
  { schedule: "30 1 * * *", timeZone: "UTC" }, // after computeCohortMedians (01:00 UTC)
  async () => {
    const orgsSnap = await db.collection("organizations").get();
    if (orgsSnap.empty) return;

    await Promise.all(
      orgsSnap.docs.map(async (orgDoc) => {
        const membersSnap = await orgDoc.ref.collection("members").get();
        const memberCount = membersSnap.size;

        if (memberCount === 0) {
          await orgDoc.ref.collection("aggregate_stats").doc("data").set({
            member_count: 0,
            avg_discipline_score: 0,
            computed_at: Timestamp.now(),
          });
          return;
        }

        const scores = await Promise.all(
          membersSnap.docs.map(async (memberDoc) => {
            const statsSnap = await db.doc(`users/${memberDoc.id}/profile_stats/data`).get();
            return (statsSnap.data()?.discipline_score as number | undefined) ?? 0;
          }),
        );

        const avgDisciplineScore = scores.reduce((sum, s) => sum + s, 0) / scores.length;

        await orgDoc.ref.collection("aggregate_stats").doc("data").set({
          member_count: memberCount,
          avg_discipline_score: Math.round(avgDisciplineScore * 100) / 100,
          computed_at: Timestamp.now(),
        });
      }),
    );
  },
);
