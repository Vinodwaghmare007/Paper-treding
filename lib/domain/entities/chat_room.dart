import 'skill_level.dart' show SkillLevel;
export 'skill_level.dart' show SkillLevel;

/// A chat room, scoped to one skill level. Pure domain entity — no
/// Firestore types.
class ChatRoom {
  const ChatRoom({
    required this.id,
    required this.name,
    required this.skillLevel,
    required this.memberCount,
    required this.createdAt,
  });

  final String id;
  final String name;
  final SkillLevel skillLevel;
  final int memberCount;
  final DateTime createdAt;
}
