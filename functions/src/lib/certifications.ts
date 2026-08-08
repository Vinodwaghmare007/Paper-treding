import * as crypto from "crypto";

import { db } from "./admin";

// Excludes 0/O/1/I so a code printed on a certificate or typed in by hand
// on the verification page isn't ambiguous.
const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

function generateVerificationCode(): string {
  const bytes = crypto.randomBytes(10);
  let code = "";
  for (let i = 0; i < bytes.length; i++) {
    code += CODE_ALPHABET[bytes[i] % CODE_ALPHABET.length];
  }
  return `${code.slice(0, 5)}-${code.slice(5)}`;
}

/**
 * Awards `milestoneType` to `userId` if not already earned.
 *
 * Idempotent by construction: `milestoneType` is used directly as the
 * `certifications` doc ID, and `.create()` throws ALREADY_EXISTS instead
 * of silently overwriting, so two trigger invocations racing for the same
 * user/milestone (e.g. two SELL orders written in quick succession) can't
 * both award it or generate two verification codes.
 *
 * Also writes a PII-free mirror to `public_certifications/{code}` —
 * milestone type and earned-at date only, no uid or email — so the public
 * verification page/function (docs/verify.html) can confirm a code is
 * genuine without needing read access into a user's private subcollection.
 */
export async function awardCertificationIfNeeded(
  userId: string,
  milestoneType: string,
): Promise<void> {
  const verificationCode = generateVerificationCode();
  const earnedAt = new Date();
  const certRef = db.doc(`users/${userId}/certifications/${milestoneType}`);

  try {
    await certRef.create({
      milestone_type: milestoneType,
      earned_at: earnedAt,
      verification_code: verificationCode,
    });
  } catch (err) {
    const code = (err as { code?: number }).code;
    if (code === 6 /* ALREADY_EXISTS */) return;
    throw err;
  }

  await db.doc(`public_certifications/${verificationCode}`).set({
    milestone_type: milestoneType,
    earned_at: earnedAt,
  });
}
