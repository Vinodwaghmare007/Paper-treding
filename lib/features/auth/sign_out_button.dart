import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/auth_repository.dart';
import '../social/profile_settings_screen.dart';
import '../social/trader_profile_screen.dart';
import 'auth_providers.dart';

/// Account menu shown in every screen's app bar — sign out, or
/// permanently delete the account and its data (see AuthRepository
/// .deleteAccount / functions/src/account/deleteAccount.ts). Kept as one
/// shared widget rather than adding a deletion entry point to each
/// screen individually, so this single, tested implementation is what
/// every screen actually uses.
class SignOutButton extends ConsumerWidget {
  const SignOutButton({super.key});

  Future<void> _confirmAndDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E222D),
        title: const Text('Delete account?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This permanently deletes your account, simulated trade history, '
          'and chat messages. This cannot be undone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFEF5350)),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(authRepositoryProvider).deleteAccount();
    } on AuthFailure catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<_AccountAction>(
      icon: const Icon(Icons.account_circle_outlined),
      tooltip: 'Account',
      onSelected: (action) {
        switch (action) {
          case _AccountAction.myProfile:
            final uid = ref.read(currentUidProvider);
            if (uid == null) return;
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => TraderProfileScreen(uid: uid)),
            );
          case _AccountAction.profileSettings:
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ProfileSettingsScreen()),
            );
          case _AccountAction.signOut:
            ref.read(authRepositoryProvider).signOut();
          case _AccountAction.deleteAccount:
            _confirmAndDelete(context, ref);
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: _AccountAction.myProfile, child: Text('My trader profile')),
        PopupMenuItem(value: _AccountAction.profileSettings, child: Text('Public profile settings')),
        PopupMenuDivider(),
        PopupMenuItem(value: _AccountAction.signOut, child: Text('Sign out')),
        PopupMenuItem(
          value: _AccountAction.deleteAccount,
          child: Text('Delete account', style: TextStyle(color: Color(0xFFEF5350))),
        ),
      ],
    );
  }
}

enum _AccountAction { myProfile, profileSettings, signOut, deleteAccount }
