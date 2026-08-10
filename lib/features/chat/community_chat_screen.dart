import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/chat_message.dart';
import '../../domain/usecases/send_chat_message.dart';
import '../../l10n/generated/app_localizations.dart';
import '../auth/auth_providers.dart';
import 'chat_providers.dart';

List<String> _reportReasons(AppLocalizations l10n) => [
      l10n.chatReportSpam,
      l10n.chatReportHarassment,
      l10n.chatReportFinancialAdvice,
      l10n.chatReportOther,
    ];

/// Combines the "room list filtered by skill level" and "chat screen"
/// requirements into one screen: the seeded layout is one room per skill
/// level (see functions/src/scripts/seedChatRooms.ts), so filtering by
/// skill level always resolves to exactly one room — there is nothing left
/// for a separate list screen to do beyond immediately opening it.
class CommunityChatScreen extends ConsumerWidget {
  const CommunityChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final roomAsync = ref.watch(myChatRoomProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E222D),
        title: roomAsync.when(
          data: (room) => Text(room?.name ?? l10n.chatTitle),
          loading: () => Text(l10n.chatTitle),
          error: (_, __) => Text(l10n.chatTitle),
        ),
        actions: const [_DisplayNameAction()],
      ),
      body: roomAsync.when(
        data: (room) => room == null
            ? const _EmptyRoomsNotice()
            : _ChatBody(roomId: room.id),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(l10n.chatLoadRoomError(e.toString()),
              style: const TextStyle(color: Color(0xFFEF5350))),
        ),
      ),
    );
  }
}

class _EmptyRoomsNotice extends StatelessWidget {
  const _EmptyRoomsNotice();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          AppLocalizations.of(context)!.chatNoRoomAvailable,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white54),
        ),
      ),
    );
  }
}

class _ChatBody extends ConsumerStatefulWidget {
  const _ChatBody({required this.roomId});

  final String roomId;

  @override
  ConsumerState<_ChatBody> createState() => _ChatBodyState();
}

class _ChatBodyState extends ConsumerState<_ChatBody> {
  final _textController = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _sending) return;

    final displayName = ref.read(chatDisplayNameProvider).valueOrNull;
    if (displayName == null) return;

    setState(() => _sending = true);
    try {
      await ref.read(sendChatMessageUseCaseProvider).send(
            roomId: widget.roomId,
            text: text,
            displayName: displayName,
          );
      _textController.clear();
    } on ChatMessageRejected catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final messagesAsync = ref.watch(chatMessagesProvider(widget.roomId));
    final myUid = ref.watch(currentUidProvider);

    return Column(
      children: [
        Expanded(
          child: messagesAsync.when(
            data: (messages) => messages.isEmpty
                ? Center(
                    child: Text(l10n.chatNoMessagesYet,
                        style: const TextStyle(color: Colors.white54)),
                  )
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(12),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      return _MessageTile(
                        message: message,
                        isMine: message.userId == myUid,
                        roomId: widget.roomId,
                      );
                    },
                  ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Text(l10n.chatLoadMessagesError(e.toString()),
                  style: const TextStyle(color: Color(0xFFEF5350))),
            ),
          ),
        ),
        _InputBar(
          controller: _textController,
          sending: _sending,
          onSend: _send,
        ),
      ],
    );
  }
}

class _MessageTile extends ConsumerWidget {
  const _MessageTile({
    required this.message,
    required this.isMine,
    required this.roomId,
  });

  final ChatMessage message;
  final bool isMine;
  final String roomId;

  Future<void> _report(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        backgroundColor: const Color(0xFF1E222D),
        title: Text(l10n.chatReportMessageAction, style: const TextStyle(color: Colors.white)),
        children: [
          for (final reason in _reportReasons(l10n))
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(reason),
              child: Text(reason, style: const TextStyle(color: Colors.white)),
            ),
        ],
      ),
    );
    if (reason == null) return;

    final uid = ref.read(currentUidProvider);
    if (uid == null) return;

    await ref.read(chatRepositoryProvider).reportMessage(
          reportedBy: uid,
          roomId: roomId,
          messageId: message.id,
          reason: reason,
        );

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.chatReportedSnackbar)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final time = TimeOfDay.fromDateTime(message.timestamp.toLocal());
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isMine ? const Color(0xFF26A69A) : const Color(0xFF1E222D),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message.displayName,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                Text(time.format(context),
                    style: const TextStyle(color: Colors.white38, fontSize: 10)),
                if (!isMine) ...[
                  const SizedBox(width: 4),
                  // A plain 14px Icon+InkWell would give an ~14x14 tap
                  // target, well under the 44x44 minimum — IconButton pads
                  // the tappable area out to Material's minimum regardless
                  // of iconSize, and doubles as the screen-reader label.
                  IconButton(
                    onPressed: () => _report(context, ref),
                    icon: const Icon(Icons.flag_outlined, size: 14, color: Colors.white38),
                    iconSize: 14,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                    tooltip: l10n.chatReportMessageAction,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Text(message.text, style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                maxLength: 500,
                minLines: 1,
                maxLines: 4,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: l10n.chatMessageHint,
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: const Color(0xFF1E222D),
                  border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: sending ? null : onSend,
              tooltip: l10n.chatSendTooltip,
              icon: sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send, color: Color(0xFF26A69A)),
            ),
          ],
        ),
      ),
    );
  }
}

class _DisplayNameAction extends ConsumerWidget {
  const _DisplayNameAction();

  Future<void> _edit(BuildContext context, WidgetRef ref, String current) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: current);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E222D),
        title: Text(l10n.chatUsernameDialogTitle, style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 24,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: l10n.chatUsernameHint,
            hintStyle: const TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    );
    if (newName == null) return;
    await ref.read(chatDisplayNameProvider.notifier).setDisplayName(newName);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final nameAsync = ref.watch(chatDisplayNameProvider);
    return nameAsync.when(
      data: (name) => IconButton(
        tooltip: l10n.chatUsernameTooltip(name),
        icon: const Icon(Icons.badge_outlined),
        onPressed: () => _edit(context, ref, name),
      ),
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
