/**
 * Basic denylist-based profanity/spam filter — deliberately simple for v1.
 *
 * NOTE FOR FUTURE WORK: replace this with a proper moderation service
 * (e.g. Google Cloud's Perspective API, or a dedicated moderation vendor)
 * before public launch. A static denylist catches none of: leetspeak
 * substitutions, non-English slurs, context-dependent harassment, or
 * evolving spam patterns. This exists only to block the most obvious cases
 * so the v1 chat isn't immediately unusable.
 */

const DENYLIST = [
  // Intentionally short and generic — a real list belongs in a moderation
  // service, not committed to source control where it's trivial to read
  // and work around.
  "fuck",
  "shit",
  "bitch",
  "asshole",
  "cunt",
  "whore",
  "slut",
  "nigger",
  "faggot",
  "retard",
];

const URL_PATTERN = /https?:\/\/\S+|www\.\S+/i;
const REPEATED_CHAR_PATTERN = /(.)\1{6,}/; // e.g. "aaaaaaaa" — common spam pattern

export interface FilterResult {
  allowed: boolean;
  reason?: string;
}

export function filterMessage(text: string): FilterResult {
  const trimmed = text.trim();
  if (trimmed.length === 0) {
    return { allowed: false, reason: "Message is empty." };
  }
  if (trimmed.length > 500) {
    return { allowed: false, reason: "Message is too long (max 500 characters)." };
  }

  const normalized = trimmed.toLowerCase();
  for (const word of DENYLIST) {
    if (normalized.includes(word)) {
      return { allowed: false, reason: "Message contains disallowed language." };
    }
  }

  if (URL_PATTERN.test(trimmed)) {
    return { allowed: false, reason: "Links aren't allowed in chat." };
  }

  if (REPEATED_CHAR_PATTERN.test(trimmed)) {
    return { allowed: false, reason: "Message looks like spam." };
  }

  return { allowed: true };
}
