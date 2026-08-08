import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import 'trader_profile_providers.dart';

/// Opt-in toggle for the public trader profile (Phase 8). Defaults off —
/// see profile_settings/data's create/update rule and
/// syncProfileVisibility.ts — and explains exactly what becomes visible
/// before the toggle is switched on, per the spec's "clear toggle ...
/// with an explanation of what becomes visible" requirement.
class ProfileSettingsScreen extends ConsumerStatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  ConsumerState<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends ConsumerState<ProfileSettingsScreen> {
  final _controller = TextEditingController();
  bool _isPublic = false;
  bool _initialized = false;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save(String uid) async {
    setState(() => _saving = true);
    try {
      await ref.read(traderProfileRepositoryProvider).updateSettings(
            uid,
            displayName: _controller.text.trim().isEmpty ? 'Trader' : _controller.text.trim(),
            isPublic: _isPublic,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile settings saved.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(currentUidProvider);
    if (uid == null) return const SizedBox.shrink();

    // Populates the form once, the first time the owner's settings load —
    // ref.listen (not a direct mutation inside build) is what makes this
    // safe to do without fighting Flutter's build-phase rules, matching
    // HomeShell's ref.listen usage for its own one-shot state sync.
    ref.listen(ownProfileSettingsProvider, (_, next) {
      final settings = next.valueOrNull;
      if (settings == null || _initialized) return;
      setState(() {
        _controller.text = settings.displayName;
        _isPublic = settings.isPublic;
        _initialized = true;
      });
    });
    final settingsAsync = ref.watch(ownProfileSettingsProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E222D),
        title: const Text('Public Profile Settings'),
      ),
      body: settingsAsync.when(
        data: (_) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Turning this on lets other users find your trader profile, '
                'follow you, and see:',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 8),
              const _BulletList(items: [
                'Your chosen display name (not your real name or email)',
                'Simulated accuracy, discipline, and win-rate stats — '
                    'computed from your trade history, never editable',
                'Your follower/following counts',
                'Any Trade Rationale notes you post on closed trades',
              ]),
              const SizedBox(height: 8),
              const Text(
                "It never shows your email, real name, or account balance.",
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _controller,
                maxLength: 30,
                decoration: const InputDecoration(
                  labelText: 'Display name',
                  border: OutlineInputBorder(),
                  helperText: 'Shown publicly if your profile is public.',
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Make my profile public', style: TextStyle(color: Colors.white)),
                value: _isPublic,
                activeColor: const Color(0xFF26A69A),
                onChanged: (value) => setState(() => _isPublic = value),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _saving ? null : () => _save(uid),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ],
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('Could not load settings: $e',
              style: const TextStyle(color: Color(0xFFEF5350))),
        ),
      ),
    );
  }
}

class _BulletList extends StatelessWidget {
  const _BulletList({required this.items});
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('•  ', style: TextStyle(color: Colors.white54)),
                Expanded(child: Text(item, style: const TextStyle(color: Colors.white54, fontSize: 13))),
              ],
            ),
          ),
      ],
    );
  }
}
