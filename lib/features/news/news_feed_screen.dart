import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/entities/news_headline.dart';
import '../../l10n/generated/app_localizations.dart';
import '../home/more_menu_button.dart';
import 'news_providers.dart';
import 'relative_time.dart';

/// Headlines aggregated server-side from a handful of crypto RSS feeds
/// (see functions/src/news/aggregateNews.ts) — this screen only ever
/// reads `news_items` from Firestore, never fetches RSS itself. Tapping a
/// card opens the original article externally (an in-app browser tab,
/// not a page rendered inside this app) — that link-out is what keeps
/// this feature clear of republishing/copyright concerns, since only a
/// headline + a short server-truncated summary + attribution are ever
/// shown here, never the article body.
class NewsFeedScreen extends ConsumerStatefulWidget {
  const NewsFeedScreen({super.key});

  @override
  ConsumerState<NewsFeedScreen> createState() => _NewsFeedScreenState();
}

class _NewsFeedScreenState extends ConsumerState<NewsFeedScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final nearBottom =
        _scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 300;
    if (nearBottom) {
      ref.read(newsFeedControllerProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final feedAsync = ref.watch(newsFeedControllerProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E222D),
        title: Text(l10n.newsTitle),
        actions: const [MoreMenuButton()],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(newsFeedControllerProvider.notifier).refresh(),
        child: feedAsync.when(
          data: (state) {
            if (state.headlines.isEmpty) {
              return ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(l10n.newsEmpty, style: const TextStyle(color: Colors.white54)),
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: state.headlines.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                if (index == state.headlines.length) {
                  return _FeedFooter(state: state);
                }
                return _HeadlineCard(headline: state.headlines[index]);
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    l10n.newsLoadError(e.toString()),
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

class _FeedFooter extends ConsumerWidget {
  const _FeedFooter({required this.state});
  final NewsFeedState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    if (state.loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (state.loadMoreError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Text(
              l10n.newsLoadMoreError(state.loadMoreError.toString()),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFEF5350), fontSize: 12),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => ref.read(newsFeedControllerProvider.notifier).loadMore(),
              child: Text(l10n.newsRetry),
            ),
          ],
        ),
      );
    }

    if (!state.hasMore) {
      return const SizedBox.shrink();
    }

    // hasMore is true but nothing is loading yet — the scroll listener
    // triggers loadMore() before the user actually reaches this row in
    // the common case, so this blank frame is rarely seen in practice.
    return const SizedBox(height: 24);
  }
}

class _HeadlineCard extends StatelessWidget {
  const _HeadlineCard({required this.headline});

  final NewsHeadline headline;

  Future<void> _open(BuildContext context) async {
    // Opens the source's own external page in an in-app browser tab
    // (Custom Tabs / SFSafariViewController) rather than this app
    // rendering or copying the article — its own visible URL bar is part
    // of what makes clear this is a link-out, not a re-publish.
    final launched = await launchUrl(
      headline.sourceUrl,
      mode: LaunchMode.inAppBrowserView,
    );
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.newsLinkOpenError)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final relative = computeRelativeTime(headline.publishedAt, DateTime.now());
    final timeLabel = switch (relative.unit) {
      RelativeTimeUnit.justNow => l10n.newsRelativeJustNow,
      RelativeTimeUnit.minutes => l10n.newsRelativeMinutesAgo(relative.magnitude),
      RelativeTimeUnit.hours => l10n.newsRelativeHoursAgo(relative.magnitude),
      RelativeTimeUnit.days => l10n.newsRelativeDaysAgo(relative.magnitude),
    };
    final sourceInitial =
        headline.sourceName.isNotEmpty ? headline.sourceName[0].toUpperCase() : '?';

    return Card(
      color: const Color(0xFF1E222D),
      child: InkWell(
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFF6FD3C7).withValues(alpha: 0.15),
                child: Text(sourceInitial, style: const TextStyle(color: Color(0xFF6FD3C7))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline.headline,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                    if (headline.summary.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        headline.summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white54, fontSize: 13),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      '${headline.sourceName} · $timeLabel',
                      style: const TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.open_in_new, color: Colors.white38, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
