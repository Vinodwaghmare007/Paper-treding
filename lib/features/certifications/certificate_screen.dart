import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/entities/certification.dart';
import 'certificate_share_card.dart';
import 'certification_providers.dart';

/// Lists every certification the signed-in user has earned; tapping one
/// opens the shareable certificate. Certifications are entirely
/// server-awarded (see functions/src/certifications/*.ts) — this screen
/// only displays and shares what already exists in Firestore.
class CertificateScreen extends ConsumerWidget {
  const CertificateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final certsAsync = ref.watch(certificationsStreamProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E222D),
        title: const Text('Certifications'),
      ),
      body: certsAsync.when(
        data: (certs) {
          if (certs.isEmpty) return const _EmptyState();
          final sorted = [...certs]..sort((a, b) => b.earnedAt.compareTo(a.earnedAt));
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: sorted.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final cert = sorted[index];
              return Card(
                color: const Color(0xFF1E222D),
                child: ListTile(
                  leading: const Icon(Icons.workspace_premium, color: Color(0xFF6FD3C7)),
                  title: Text(cert.milestoneType.milestoneTitle,
                      style: const TextStyle(color: Colors.white)),
                  subtitle: Text(cert.milestoneType.milestoneDescription,
                      style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _CertificateDetailScreen(certification: cert),
                    ),
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('Could not load certifications: $e',
              style: const TextStyle(color: Color(0xFFEF5350))),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Center(
        child: Text(
          'Keep trading and backtesting — certifications unlock '
          'automatically as you hit milestones.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white54),
        ),
      ),
    );
  }
}

class _CertificateDetailScreen extends StatefulWidget {
  const _CertificateDetailScreen({required this.certification});

  final Certification certification;

  @override
  State<_CertificateDetailScreen> createState() => _CertificateDetailScreenState();
}

class _CertificateDetailScreenState extends State<_CertificateDetailScreen> {
  final _screenshotController = ScreenshotController();
  bool _sharing = false;

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final bytes = await _screenshotController.capture(pixelRatio: 2);
      if (bytes == null) return;
      await Share.shareXFiles(
        [XFile.fromData(bytes, mimeType: 'image/png', name: 'certificate.png')],
        text: 'I earned the "${widget.certification.milestoneType.milestoneTitle}" '
            'certification on Crypto Paper Trader (educational simulator — '
            'no real money). Verify it: '
            '${verificationUrlFor(widget.certification.verificationCode)}',
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E222D),
        title: const Text('Certificate'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Screenshot(
                    controller: _screenshotController,
                    child: CertificateShareCard(certification: widget.certification),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: _sharing ? null : _share,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF26A69A),
                minimumSize: const Size.fromHeight(48),
              ),
              icon: _sharing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.share),
              label: const Text('Share certificate'),
            ),
          ),
        ],
      ),
    );
  }
}
