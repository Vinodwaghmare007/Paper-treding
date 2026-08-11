import { HttpsError, onCall } from "firebase-functions/v2/https";
import { Timestamp } from "firebase-admin/firestore";

import { db } from "../lib/admin";
import { generateCode } from "./codeGenerator";

const MAX_CODE_GENERATION_ATTEMPTS = 5;

/**
 * Generates a fresh invite code for an org, callable only by one of that
 * org's own admins. Unlike referral codes, org invite codes are
 * many-per-org and single-use (see redeemOrgInviteCodeForUser) — an admin
 * calls this once per batch of students they want to onboard, shares the
 * code out of band, and each redemption consumes it.
 */
export async function createOrgInviteCodeForUser(
  callerUid: string,
  orgId: string,
): Promise<{ code: string }> {
  const orgRef = db.doc(`organizations/${orgId}`);
  const orgSnap = await orgRef.get();
  if (!orgSnap.exists) {
    throw new HttpsError("not-found", "Organization not found.");
  }
  const adminIds = (orgSnap.data()?.admin_user_ids as string[] | undefined) ?? [];
  if (!adminIds.includes(callerUid)) {
    throw new HttpsError("permission-denied", "Only an admin of this organization can create invite codes.");
  }

  for (let attempt = 0; attempt < MAX_CODE_GENERATION_ATTEMPTS; attempt++) {
    const code = generateCode();
    const codeRef = db.doc(`org_invite_codes/${code}`);
    const codeSnap = await codeRef.get();
    if (codeSnap.exists) continue; // collision — try another code

    await codeRef.set({
      org_id: orgId,
      used: false,
      created_by: callerUid,
      created_at: Timestamp.now(),
    });
    return { code };
  }

  throw new HttpsError("resource-exhausted", "Could not generate a unique invite code — try again.");
}

/**
 * Redeems an org invite code at signup, consuming a seat. Everything here
 * happens inside a single transaction — the invite-code doc, the org doc,
 * and the caller's own user doc are all read together and written
 * together — specifically so two students redeeming the last open seat at
 * the same moment can't both succeed: only one read of `seats_used` wins
 * the transaction, the other retries and then fails the seat-limit check
 * against the now-current count.
 */
export async function redeemOrgInviteCodeForUser(
  uid: string,
  rawCode: string,
  displayNameHint: string,
): Promise<{ orgId: string }> {
  const code = rawCode.trim().toUpperCase();
  if (code.length === 0) {
    throw new HttpsError("invalid-argument", "Invite code is required.");
  }

  const codeRef = db.doc(`org_invite_codes/${code}`);
  const userRef = db.doc(`users/${uid}`);

  const orgId = await db.runTransaction(async (tx) => {
    const [codeSnap, userSnap] = await Promise.all([tx.get(codeRef), tx.get(userRef)]);

    if (!codeSnap.exists) {
      throw new HttpsError("not-found", "That invite code doesn't exist.");
    }
    const codeData = codeSnap.data()!;
    if (codeData.used === true) {
      throw new HttpsError("already-exists", "That invite code has already been used.");
    }

    if (!userSnap.exists) {
      throw new HttpsError("not-found", "Account not found.");
    }
    if (userSnap.data()!.org_id) {
      throw new HttpsError("failed-precondition", "This account already belongs to an organization.");
    }

    const targetOrgId = codeData.org_id as string;
    const orgRef = db.doc(`organizations/${targetOrgId}`);
    const orgSnap = await tx.get(orgRef);
    if (!orgSnap.exists) {
      // The org was deleted after the code was issued — the code is
      // dangling. Fail clearly rather than enrolling into nothing.
      throw new HttpsError("failed-precondition", "This invite code is no longer valid.");
    }
    const orgData = orgSnap.data()!;
    const seatLimit = orgData.seat_limit as number;
    const seatsUsed = (orgData.seats_used as number | undefined) ?? 0;
    if (seatsUsed >= seatLimit) {
      throw new HttpsError("resource-exhausted", "This organization has no available seats left.");
    }

    const displayName = displayNameHint.trim().length > 0 ? displayNameHint.trim() : "Student";

    tx.update(codeRef, { used: true, used_by: uid, used_at: Timestamp.now() });
    tx.update(orgRef, { seats_used: seatsUsed + 1 });
    tx.update(userRef, { org_id: targetOrgId });
    tx.set(db.doc(`organizations/${targetOrgId}/members/${uid}`), {
      display_name: displayName,
      joined_at: Timestamp.now(),
    });

    return targetOrgId;
  });

  return { orgId };
}

export const createOrgInviteCode = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  const orgId = request.data?.orgId;
  if (typeof orgId !== "string" || orgId.trim().length === 0) {
    throw new HttpsError("invalid-argument", "orgId is required.");
  }
  return createOrgInviteCodeForUser(uid, orgId);
});

export const redeemOrgInviteCode = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  const code = request.data?.code;
  if (typeof code !== "string" || code.trim().length === 0) {
    throw new HttpsError("invalid-argument", "code is required.");
  }
  const displayNameHint = typeof request.data?.displayName === "string" ? request.data.displayName : "";
  return redeemOrgInviteCodeForUser(uid, code, displayNameHint);
});
