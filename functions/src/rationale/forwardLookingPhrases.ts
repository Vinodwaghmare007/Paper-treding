// Deliberately blunt phrase matching, per the spec: "imperfect but adds a
// layer beyond the timestamp check" — the timestamp-after-close +
// SELL-only constraints in addTradeRationale.ts are the real safeguard
// against disguised forward guidance; this only *flags* a submission for
// manual review, it never blocks one (a rationale like "I sold too early,
// it will probably keep going up" is a legitimate retrospective note that
// happens to contain "will").
const FORWARD_LOOKING_PATTERNS = [
  /\bwill\b/i,
  /\bgoing to\b/i,
  /\bbuy now\b/i,
  /\bsell now\b/i,
];

export function containsForwardLookingLanguage(text: string): boolean {
  return FORWARD_LOOKING_PATTERNS.some((pattern) => pattern.test(text));
}
