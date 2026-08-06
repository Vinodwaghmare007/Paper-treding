/// A single chat message. Pure domain entity — no Firestore types.
///
/// [displayName] is a chosen username, never a real name — the schema
/// deliberately has no field for one (see chat_rooms/{roomId}/messages in
/// firestore.rules and send_chat_message.dart).
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.userId,
    required this.displayName,
    required this.text,
    required this.timestamp,
  });

  final String id;
  final String userId;
  final String displayName;
  final String text;
  final DateTime timestamp;
}
