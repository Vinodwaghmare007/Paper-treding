import 'package:cloud_functions/cloud_functions.dart';

/// A chat message was rejected. Never thrown for infrastructure failures
/// unrelated to the message itself (those surface as the underlying
/// [FirebaseFunctionsException]).
sealed class ChatMessageRejected implements Exception {
  const ChatMessageRejected(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Either the local 3s debounce, or the server's own rate limit (returned
/// as a `resource-exhausted` error if a request somehow slips past the
/// local check — see the long comment on [SendChatMessageUseCase.send]).
class ChatRateLimitException extends ChatMessageRejected {
  const ChatRateLimitException(this.retryAfter)
      : super('You\'re sending messages too quickly — wait a moment.');
  final Duration retryAfter;
}

/// Rejected by the server-side profanity/spam filter, or malformed input.
class ChatContentRejectedException extends ChatMessageRejected {
  const ChatContentRejectedException(super.message);
}

/// Not allowed to post in this room right now — wrong skill level for the
/// room, or the account is flagged for review. The server's message
/// already explains which.
class ChatPermissionDeniedException extends ChatMessageRejected {
  const ChatPermissionDeniedException(super.message);
}

class ChatUnknownException extends ChatMessageRejected {
  const ChatUnknownException(super.message);
}

/// Sends a chat message via the `sendChatMessage` Cloud Function callable.
///
/// This calls a server-side callable rather than writing to Firestore
/// directly — firestore.rules can't make per-message rate limiting
/// airtight on its own (a rules-only "cooldown doc" pattern only works if
/// the client is *also* trusted to keep that cooldown doc honest, and a
/// modified client that just never updates it gets a permanent bypass
/// after the first message). The Cloud Function does the rate-limit
/// check, the profanity filter, and the skill-level match as one atomic
/// server-side transaction — see functions/src/chat/sendChatMessage.ts.
///
/// The debounce here is a *local, instant* UX guard only — it stops an
/// eager double-tap from ever reaching the network, but it is not what
/// actually enforces the rate limit; the server transaction is. A
/// determined client could skip straight past this class entirely and
/// call the Cloud Function directly, and the server-side check would
/// still catch it.
class SendChatMessageUseCase {
  SendChatMessageUseCase({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  static const debounceWindow = Duration(seconds: 3);

  DateTime? _lastSendAttemptAt;

  Future<void> send({
    required String roomId,
    required String text,
    required String displayName,
  }) async {
    final now = DateTime.now();
    final last = _lastSendAttemptAt;
    if (last != null) {
      final elapsed = now.difference(last);
      if (elapsed < debounceWindow) {
        throw ChatRateLimitException(debounceWindow - elapsed);
      }
    }
    _lastSendAttemptAt = now;

    try {
      final callable = _functions.httpsCallable('sendChatMessage');
      await callable.call<Map<String, dynamic>>({
        'roomId': roomId,
        'text': text,
        'displayName': displayName,
      });
    } on FirebaseFunctionsException catch (e) {
      throw _mapError(e);
    }
  }

  ChatMessageRejected _mapError(FirebaseFunctionsException e) {
    final message = e.message ?? 'Could not send message.';
    return switch (e.code) {
      'resource-exhausted' => ChatRateLimitException(debounceWindow),
      'invalid-argument' => ChatContentRejectedException(message),
      'permission-denied' => ChatPermissionDeniedException(message),
      _ => ChatUnknownException(message),
    };
  }
}
