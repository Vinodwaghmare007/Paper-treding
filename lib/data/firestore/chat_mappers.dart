import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/chat_message.dart';
import '../../domain/entities/chat_room.dart';
import '../../domain/entities/skill_level.dart';

/// Converts between the pure domain entities and their Firestore document
/// shape. Kept out of `domain/` so the entities stay Firebase-free.
extension ChatRoomFirestoreMapping on ChatRoom {
  static ChatRoom fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) {
      throw StateError('chat_rooms/${doc.id} does not exist');
    }
    final createdTs = data['created_at'];
    return ChatRoom(
      id: doc.id,
      name: data['name'] as String,
      skillLevel: SkillLevelCode.fromCode(data['skill_level'] as String),
      memberCount: (data['member_count'] as num?)?.toInt() ?? 0,
      createdAt: createdTs is Timestamp
          ? createdTs.toDate().toUtc()
          : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}

extension ChatMessageFirestoreMapping on ChatMessage {
  static ChatMessage fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) {
      throw StateError('chat message doc ${doc.id} does not exist');
    }
    final ts = data['timestamp'];
    return ChatMessage(
      id: doc.id,
      userId: data['user_id'] as String,
      displayName: data['display_name'] as String,
      text: data['text'] as String,
      // A just-sent message may still have a null server timestamp in the
      // local cache until the write round-trips — fall back to "now" so it
      // renders immediately instead of throwing.
      timestamp: ts is Timestamp ? ts.toDate().toUtc() : DateTime.now().toUtc(),
    );
  }
}
