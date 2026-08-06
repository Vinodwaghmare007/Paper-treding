/// Mirrored in functions/src/lib/skillLevel.ts — keep both in sync.
/// Bucketed by *completed* trades (SELL orders, i.e. closed round-trips)
/// rather than total order count, since a pile of open BUYs isn't the same
/// signal of experience as trades actually closed out.
enum SkillLevel { beginner, intermediate, advanced }

extension SkillLevelCode on SkillLevel {
  String get code => switch (this) {
        SkillLevel.beginner => 'beginner',
        SkillLevel.intermediate => 'intermediate',
        SkillLevel.advanced => 'advanced',
      };

  static SkillLevel fromCode(String code) => switch (code) {
        'beginner' => SkillLevel.beginner,
        'intermediate' => SkillLevel.intermediate,
        'advanced' => SkillLevel.advanced,
        _ => throw ArgumentError.value(code, 'code', 'Unknown skill level'),
      };
}

const int intermediateSkillThreshold = 5;
const int advancedSkillThreshold = 20;

SkillLevel skillLevelForCompletedTrades(int completedTrades) {
  if (completedTrades >= advancedSkillThreshold) return SkillLevel.advanced;
  if (completedTrades >= intermediateSkillThreshold) return SkillLevel.intermediate;
  return SkillLevel.beginner;
}
