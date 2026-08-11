import { HttpsError, onCall } from "firebase-functions/v2/https";
import { Timestamp } from "firebase-admin/firestore";

import { db } from "../lib/admin";
import { generateCode } from "./codeGenerator";

/** Pro-access days granted to EACH side of a successful referral. */
export const REFERRAL_BONUS_DAYS = 7;

const MAX_CODE_GENERATION_ATTEMPTS = 5;

/**
 * Assigns this user their own referral code, if they don't already have
 * one — idempotent, so a retried call (network blip after the first
 * attempt actually succeeded) never orphans a `referral_codes` lookup doc
 * or overwrites an already-shared code out from under someone. Collision
 * retry exists for completeness (32^8 combinations makes an actual
 * collision astronomically unlikely) rather than because it's expected to
 * ever fire.
 */
export async function generateReferralCodeForUser(uid: string): Promise<{ code: string }> {
  const userRef = db.doc(`users/${uid}`);
  const userSnap = await userRef.get();
  if (!userSnap.exists) {
    throw new HttpsError("not-found", "Account not found.");
  }
  const existing = userSnap.data()?.referral_code as string | undefined;
  if (existing) {
    return { code: existing };
  }

  for (let attempt = 0; attempt < MAX_CODE_GENERATION_ATTEMPTS; attempt++) {
    const code = generateCode();
    const codeRef = db.doc(`referral_codes/${code}`);

    const assigned = await db.runTransaction(async (tx) => {
      const [codeSnap, freshUserSnap] = await Promise.all([tx.get(codeRef), tx.get(userRef)]);
      if (codeSnap.exists) return false; // collision — try another code

      // Re-check inside the transaction: another concurrent call (e.g. a
      // double-tap on the client before the first response lands) may
      // have assigned a code between our first read above and now.
      const alreadyAssigned = freshUserSnap.data()?.referral_code as string | undefined;
      if (alreadyAssigned) return alreadyAssigned;

      tx.set(codeRef, { uid, created_at: Timestamp.now() });
      tx.update(userRef, { referral_code: code });
      return true;
    });

    if (assigned === true) return { code };
    if (typeof assigned === "string") return { code: assigned };
    // assigned === false: collision, loop and try the next generated code.
  }

  throw new HttpsError("resource-exhausted", "Could not generate a unique referral code — try again.");
}

/**
 * Redeems a referral code entered at signup. Grants REFERRAL_BONUS_DAYS of
 * Pro access to BOTH the referrer and the new user by extending
 * `pro_access_until` (never overwriting a longer window either of them
 * might already have from an earlier referral), and logs an audit doc in
 * `referrals` that referral_screen.dart counts against. One redemption per
 * account, ever — `referred_by` is set once and then guarded by
 * firestore.rules the same way every other server-only field is.
 */
export async function redeemReferralCodeForUser(
  newUserId: string,
  rawCode: string,
  { now }: { now?: Timestamp } = {},
): Promise<{ grantedDays: number }> {
  const code = rawCode.trim().toUpperCase();
  if (code.length === 0) {
    throw new HttpsError("invalid-argument", "Referral code is required.");
  }

  const codeSnap = await db.doc(`referral_codes/${code}`).get();
  if (!codeSnap.exists) {
    throw new HttpsError("not-found", "That referral code doesn't exist.");
  }
  const referrerId = codeSnap.data()!.uid as string;
  if (referrerId === newUserId) {
    throw new HttpsError("invalid-argument", "You can't redeem your own referral code.");
  }

  const effectiveNow = now ?? Timestamp.now();
  const bonusMs = REFERRAL_BONUS_DAYS * 24 * 60 * 60 * 1000;

  await db.runTransaction(async (tx) => {
    const newUserRef = db.doc(`users/${newUserId}`);
    const referrerRef = db.doc(`users/${referrerId}`);
    const [newUserSnap, referrerSnap] = await Promise.all([tx.get(newUserRef), tx.get(referrerRef)]);

    if (!newUserSnap.exists) {
      throw new HttpsError("not-found", "Account not found.");
    }
    if (!referrerSnap.exists) {
      // The referrer's account was deleted after sharing the code — the
      // code itself is now dangling. Nothing to credit; fail clearly
      // rather than silently granting only one side's bonus.
      throw new HttpsError("failed-precondition", "This referral code is no longer valid.");
    }
    if (newUserSnap.data()!.referred_by) {
      throw new HttpsError("already-exists", "A referral code has already been redeemed for this account.");
    }

    const extend = (data: FirebaseFirestore.DocumentData) => {
      const currentUntil = data.pro_access_until as Timestamp | undefined;
      const base = Math.max(currentUntil?.toMillis() ?? 0, effectiveNow.toMillis());
      return Timestamp.fromMillis(base + bonusMs);
    };

    tx.update(newUserRef, {
      referred_by: referrerId,
      pro_access_until: extend(newUserSnap.data()!),
      pro_days_earned: (newUserSnap.data()!.pro_days_earned as number | undefined ?? 0) + REFERRAL_BONUS_DAYS,
    });
    tx.update(referrerRef, {
      pro_access_until: extend(referrerSnap.data()!),
      pro_days_earned: (referrerSnap.data()!.pro_days_earned as number | undefined ?? 0) + REFERRAL_BONUS_DAYS,
    });
    tx.set(db.collection("referrals").doc(), {
      referrer_id: referrerId,
      referred_id: newUserId,
      created_at: effectiveNow,
    });
  });

  return { grantedDays: REFERRAL_BONUS_DAYS };
}

export const generateReferralCode = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  return generateReferralCodeForUser(uid);
});

export const redeemReferralCode = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  const code = request.data?.code;
  if (typeof code !== "string" || code.trim().length === 0) {
    throw new HttpsError("invalid-argument", "code is required.");
  }
  return redeemReferralCodeForUser(uid, code);
});
