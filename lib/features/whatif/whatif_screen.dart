import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';

import 'whatif_providers.dart';
import 'whatif_share_card.dart';

class WhatIfScreen extends ConsumerStatefulWidget {
  const WhatIfScreen({super.key});

  @override
  ConsumerState<WhatIfScreen> createState() => _WhatIfScreenState();
}

class _WhatIfScreenState extends ConsumerState<WhatIfScreen> {
  final _screenshotController = ScreenshotController();
  bool _sharing = false;

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final bytes = await _screenshotController.capture(pixelRatio: 2);
      if (bytes == null) return;
      await Share.shareXFiles(
        [XFile.fromData(bytes, mimeType: 'image/png', name: 'whatif.png')],
        text: 'What if I had invested in crypto? Play with the What-If '
            'Time Machine on Crypto Paper Trader (paper trading only — no '
            'real money).',
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final resultAsync = ref.watch(whatIfProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E222D),
        title: const Text('What-If Time Machine'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: resultAsync.when(
                data: (result) => result == null
                    ? const _EmptyState()
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 340),
                          child: Screenshot(
                            controller: _screenshotController,
                            child: WhatIfShareCard(result: result),
                          ),
                        ),
                      ),
                loading: () => const CircularProgressIndicator(),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Could not generate a What-If scenario: $e',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFEF5350)),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: resultAsync.isLoading
                        ? null
                        : () => ref.read(whatIfProvider.notifier).generate(),
                    icon: const Icon(Icons.casino_outlined),
                    label: Text(
                      resultAsync.valueOrNull == null ? 'Generate' : 'Try another',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: resultAsync.valueOrNull == null || _sharing ? null : _share,
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF26A69A)),
                    icon: _sharing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.share),
                    label: const Text('Share'),
                  ),
                ),
              ],
            ),
          ),
        ],
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
      child: Text(
        'See what a hypothetical investment on a random day in BTC history '
        'would be worth today — purely for fun, not investment advice.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white54),
      ),
    );
  }
}
