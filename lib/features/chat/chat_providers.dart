import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/chat_repository.dart';
import '../../data/sources/chat_display_name_store.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/chat_room.dart';
import '../../domain/usecases/send_chat_message.dart';
import '../auth/auth_providers.dart';
import '../portfolio/portfolio_providers.dart';

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ChatRepository(ref.watch(firebaseFirestoreProvider));
});

final sendChatMessageUseCaseProvider = Provider<SendChatMessageUseCase>((ref) {
  return SendChatMessageUseCase(functions: FirebaseFunctions.instance);
});

/// The single room matching the signed-in user's own (server-cached) skill
/// level. The seeded layout (see functions/src/scripts/seedChatRooms.ts) is
/// one room per level, so "the room list filtered by skill level" is
/// exactly this one room — see community_chat_screen.dart for why the list
/// and chat views are collapsed into a single screen as a result.
final myChatRoomProvider = StreamProvider<ChatRoom?>((ref) {
  final skillLevel =
      ref.watch(accountStreamProvider).valueOrNull?.skillLevel ??
          SkillLevel.beginner;
  return ref.watch(chatRepositoryProvider).watchRoomForSkillLevel(skillLevel);
});

final chatMessagesProvider =
    StreamProvider.family<List<ChatMessage>, String>((ref, roomId) {
  return ref.watch(chatRepositoryProvider).watchMessages(roomId);
});

final chatDisplayNameStoreProvider =
    Provider<ChatDisplayNameStore>((ref) => ChatDisplayNameStore());

/// The user's on-device chat username. Loaded once (auto-generating a
/// pseudonym on first use) and editable via [setDisplayName].
class ChatDisplayNameNotifier extends AsyncNotifier<String> {
  @override
  Future<String> build() {
    return ref.watch(chatDisplayNameStoreProvider).read();
  }

  Future<void> setDisplayName(String displayName) async {
    final trimmed = displayName.trim();
    if (trimmed.isEmpty) return;
    await ref.read(chatDisplayNameStoreProvider).write(trimmed);
    state = AsyncData(trimmed);
  }
}

final chatDisplayNameProvider =
    AsyncNotifierProvider<ChatDisplayNameNotifier, String>(
        ChatDisplayNameNotifier.new);
