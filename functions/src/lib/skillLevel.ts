export type SkillLevel = "beginner" | "intermediate" | "advanced";

// Mirrored in lib/domain/usecases/skill_level.dart on the Flutter side —
// keep both in sync. Bucketed by *completed* trades (SELL orders, i.e.
// closed round-trips) rather than total order count, since a pile of open
// BUYs isn't the same signal of experience as trades actually closed out.
const INTERMEDIATE_THRESHOLD = 5;
const ADVANCED_THRESHOLD = 20;

export function skillLevelForCompletedTrades(completedTrades: number): SkillLevel {
  if (completedTrades >= ADVANCED_THRESHOLD) return "advanced";
  if (completedTrades >= INTERMEDIATE_THRESHOLD) return "intermediate";
  return "beginner";
}
