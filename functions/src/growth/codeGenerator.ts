import { randomInt } from "crypto";

// Excludes visually-ambiguous characters (0/O, 1/I/L) — these codes get
// typed by hand or read off a screenshot, so a code that's easy to
// mis-transcribe defeats the point. Shared by both referral codes and org
// invite codes so a code's shape doesn't leak which kind it is.
const ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

export function generateCode(length = 8): string {
  let code = "";
  for (let i = 0; i < length; i++) {
    code += ALPHABET[randomInt(ALPHABET.length)];
  }
  return code;
}
