import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/chat_message.dart';
import '../../domain/entities/chat_room.dart';
import '../../domain/entities/skill_level.dart';
import '../firestore/chat_mappers.dart';
import '../firestore/firestore_paths.dart';

/// Read side of the community chat feature, plus report filing. Sending a
/// message is deliberately *not* here — that goes through the
/// `sendChatMessage` callable (see [SendChatMessageUseCase]), not a direct
/// Firestore write, since firestore.rules denies client writes to
/// `chat_rooms/{roomId}/messages` outright.
class ChatRepository {
  ChatRepository(FirebaseFirestore firestore)
      : _paths = FirestorePaths(firestore);

  final FirestorePaths _paths;

  /// All chat rooms — room metadata is readable by any signed-in user
  /// regardless of their own skill level, per firestore.rules.
  Stream<List<ChatRoom>> watchRooms() {
    return _paths.chatRooms().snapshots().map(
          (snap) => snap.docs
              .map(ChatRoomFirestoreMapping.fromDoc)
              .toList(growable: false),
        );
  }

  /// The single room matching [skillLevel], if the one-room-per-level
  /// layout seeded by seedChatRooms.ts has been provisioned.
  Stream<ChatRoom?> watchRoomForSkillLevel(SkillLevel skillLevel) {
    return _paths
        .chatRooms()
        .where('skill_level', isEqualTo: skillLevel.code)
        .limit(1)
        .snapshots()
        .map(
          (snap) => snap.docs.isEmpty
              ? null
              : ChatRoomFirestoreMapping.fromDoc(snap.docs.first),
        );
  }

  /// Most recent messages first. Firestore denies this read entirely
  /// (empty stream error) if [roomId] isn't the room matching the caller's
  /// own cached skill level — see the `messages` match block in
  /// firestore.rules.
  Stream<List<ChatMessage>> watchMessages(String roomId, {int limit = 100}) {
    return _paths
        .chatMessages(roomId)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(ChatMessageFirestoreMapping.fromDoc)
              .toList(growable: false),
        );
  }

  /// Files a report for manual moderator review. Nothing automated happens
  /// on the client's side of this — see the `reports` match block in
  /// firestore.rules for why the collection is write-only from here.
  Future<void> reportMessage({
    required String reportedBy,
    required String roomId,
    required String messageId,
    required String reason,
  }) {
    return _paths.newReportRef().set({
      'reported_by': reportedBy,
      'room_id': roomId,
      'message_id': messageId,
      'reason': reason,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }
}
