import { db } from "./admin";

/** Shared by every trigger that should skip doing work for a private
 * account (recomputeTraderStats.ts's on-order path, publicActivity.ts) —
 * one implementation so "is this profile public" always means the same
 * single read of profile_settings/data. */
export async function isPublicProfile(userId: string): Promise<boolean> {
  const settingsSnap = await db.doc(`users/${userId}/profile_settings/data`).get();
  return settingsSnap.data()?.is_public === true;
}
