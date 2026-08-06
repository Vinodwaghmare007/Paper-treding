/**
 * Deterministic pseudo-random number in [0, 1) derived from a string seed
 * (e.g. a date like "2026-08-06"). Same seed always produces the same
 * value — this is what makes the daily puzzle identical for every user on
 * a given date, which is required for the "X% of players got it right
 * today" social-proof feature to mean anything.
 *
 * Not cryptographically secure — doesn't need to be; the only property
 * that matters here is determinism plus a reasonably even distribution,
 * which a simple string hash feeding a mulberry32-style mix gives us
 * without a new dependency.
 */
export function seededRandom(seed: string): number {
  let hash = 0;
  for (let i = 0; i < seed.length; i++) {
    hash = (Math.imul(31, hash) + seed.charCodeAt(i)) | 0;
  }
  let t = (hash + 0x6d2b79f5) | 0;
  t = Math.imul(t ^ (t >>> 15), t | 1);
  t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}
