import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/sources/crypto_news_source.dart';
import '../../domain/entities/news_headline.dart';
import '../auth/sign_out_button.dart';
import 'news_providers.dart';

class NewsFeedScreen extends ConsumerWidget {
  const NewsFeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final headlinesAsync = ref.watch(newsHeadlinesProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E222D),
        title: const Text('Crypto News'),
        actions: const [SignOutButton()],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(newsHeadlinesProvider.future),
        child: headlinesAsync.when(
          data: (headlines) {
            if (headlines.isEmpty) {
              return ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text('No headlines right now.',
                          style: TextStyle(color: Colors.white54)),
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: headlines.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) =>
                  _HeadlineCard(headline: headlines[index]),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    e is CryptoNewsException
                        ? e.message
                        : 'Failed to load headlines: $e',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFEF5350)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeadlineCard extends StatelessWidget {
  const _HeadlineCard({required this.headline});

  final NewsHeadline headline;

  Future<void> _open(BuildContext context) async {
    // Opens the source's own external page in an in-app browser tab
    // (Custom Tabs / SFSafariViewController) rather than this app
    // rendering or copying the article — see the class doc on
    // CryptoNewsSource for why.
    final launched = await launchUrl(
      headline.url,
      mode: LaunchMode.inAppBrowserView,
    );
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open this link.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final published = headline.publishedAt.toLocal();
    final timeLabel =
        '${published.year}-${published.month.toString().padLeft(2, '0')}-'
        '${published.day.toString().padLeft(2, '0')} '
        '${published.hour.toString().padLeft(2, '0')}:'
        '${published.minute.toString().padLeft(2, '0')}';

    return Card(
      color: const Color(0xFF1E222D),
      child: ListTile(
        onTap: () => _open(context),
        title: Text(
          headline.title,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '${headline.sourceName} · $timeLabel',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ),
        trailing: const Icon(Icons.open_in_new, color: Colors.white38, size: 18),
      ),
    );
  }
}
