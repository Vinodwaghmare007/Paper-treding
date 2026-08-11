import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/sources/news_feed_source.dart';
import '../../domain/entities/news_headline.dart';
import '../auth/auth_providers.dart';

final newsFeedSourceProvider = Provider<NewsFeedSource>((ref) {
  return NewsFeedSource(ref.watch(firebaseFirestoreProvider));
});

/// Paginated news feed state. [loadMoreError] is separate from the
/// notifier's own [AsyncError] state so a failed "load more" (page 2+)
/// never wipes the headlines already on screen — only the very first
/// page's failure surfaces as a full-screen error (see
/// news_feed_screen.dart's `.when()`).
class NewsFeedState {
  const NewsFeedState({
    required this.headlines,
    required this.lastDocument,
    required this.hasMore,
    this.loadingMore = false,
    this.loadMoreError,
  });

  final List<NewsHeadline> headlines;
  final DocumentSnapshot<Map<String, dynamic>>? lastDocument;
  final bool hasMore;
  final bool loadingMore;
  final Object? loadMoreError;

  NewsFeedState copyWith({
    List<NewsHeadline>? headlines,
    DocumentSnapshot<Map<String, dynamic>>? lastDocument,
    bool? hasMore,
    bool? loadingMore,
    Object? loadMoreError,
    bool clearLoadMoreError = false,
  }) {
    return NewsFeedState(
      headlines: headlines ?? this.headlines,
      lastDocument: lastDocument ?? this.lastDocument,
      hasMore: hasMore ?? this.hasMore,
      loadingMore: loadingMore ?? this.loadingMore,
      loadMoreError: clearLoadMoreError ? null : (loadMoreError ?? this.loadMoreError),
    );
  }
}

/// Owns the news feed's pagination — [build] loads the first page,
/// [loadMore] appends the next one (driven by news_feed_screen.dart's
/// scroll listener), [refresh] re-queries from the top (pull-to-refresh).
/// Every one of these is a fresh Firestore query, never a client-side RSS
/// fetch — see news_feed_source.dart's doc comment.
class NewsFeedController extends AsyncNotifier<NewsFeedState> {
  @override
  Future<NewsFeedState> build() async {
    final page = await ref.watch(newsFeedSourceProvider).fetchPage();
    return NewsFeedState(
      headlines: page.headlines,
      lastDocument: page.lastDocument,
      hasMore: page.hasMore,
    );
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || current.loadingMore) return;

    state = AsyncData(current.copyWith(loadingMore: true, clearLoadMoreError: true));
    try {
      final page = await ref
          .read(newsFeedSourceProvider)
          .fetchPage(startAfter: current.lastDocument);
      state = AsyncData(NewsFeedState(
        headlines: [...current.headlines, ...page.headlines],
        lastDocument: page.lastDocument,
        hasMore: page.hasMore,
      ));
    } catch (e) {
      state = AsyncData(current.copyWith(loadingMore: false, loadMoreError: e));
    }
  }

  Future<void> refresh() async {
    state = const AsyncLoading<NewsFeedState>().copyWithPrevious(state);
    state = await AsyncValue.guard(() async {
      final page = await ref.read(newsFeedSourceProvider).fetchPage();
      return NewsFeedState(
        headlines: page.headlines,
        lastDocument: page.lastDocument,
        hasMore: page.hasMore,
      );
    });
  }
}

final newsFeedControllerProvider =
    AsyncNotifierProvider<NewsFeedController, NewsFeedState>(NewsFeedController.new);
