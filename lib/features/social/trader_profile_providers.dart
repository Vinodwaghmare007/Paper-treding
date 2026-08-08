import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/leaderboard_repository.dart';
import '../../data/repositories/trader_profile_repository.dart';
import '../../domain/entities/activity_event.dart';
import '../../domain/entities/leaderboard_entry.dart';
import '../../domain/entities/trade_rationale.dart';
import '../../domain/entities/trader_profile.dart';
import '../../domain/usecases/add_trade_rationale.dart';
import '../auth/auth_providers.dart';

final traderProfileRepositoryProvider = Provider<TraderProfileRepository>((ref) {
  return TraderProfileRepository(ref.watch(firebaseFirestoreProvider));
});

final leaderboardRepositoryProvider = Provider<LeaderboardRepository>((ref) {
  return LeaderboardRepository(ref.watch(firebaseFirestoreProvider));
});

final addTradeRationaleUseCaseProvider =
    Provider<AddTradeRationaleUseCase>((ref) => AddTradeRationaleUseCase());

/// The signed-in user's own settings — read/write, for
/// profile_settings_screen.dart.
final ownProfileSettingsProvider =
    StreamProvider<({String displayName, bool isPublic})>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return const Stream.empty();
  return ref.watch(traderProfileRepositoryProvider).watchOwnSettings(uid);
});

/// A trader's public profile by uid — works for both "my own" and
/// visiting someone else's, since the underlying read is the same
/// profile_stats doc either way (gated by firestore.rules).
final traderProfileProvider =
    StreamProvider.family<TraderProfile?, String>((ref, uid) {
  return ref.watch(traderProfileRepositoryProvider).watchProfile(uid);
});

final isFollowingProvider = StreamProvider.family<bool, String>((ref, targetUid) {
  final myUid = ref.watch(currentUidProvider);
  if (myUid == null) return Stream.value(false);
  return ref.watch(traderProfileRepositoryProvider).watchIsFollowing(myUid, targetUid);
});

final followedUserIdsProvider = StreamProvider<List<String>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(traderProfileRepositoryProvider).watchFollowedUserIds(uid);
});

/// The signed-in user's own rationale note (if any) on one of their own
/// orders — used by order_history_screen.dart to show/edit it.
final ownRationaleProvider = StreamProvider.family<TradeRationale?, String>((ref, orderId) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(null);
  return ref.watch(traderProfileRepositoryProvider).watchRationale(uid, orderId);
});

final traderRationalesProvider =
    FutureProvider.family<List<TradeRationale>, String>((ref, uid) {
  return ref.watch(traderProfileRepositoryProvider).fetchTraderRationales(uid);
});

final leaderboardProvider =
    StreamProvider.family<List<LeaderboardEntry>, LeaderboardWindow>((ref, window) {
  return ref.watch(leaderboardRepositoryProvider).watchLeaderboard(window);
});

/// Merged, most-recent-first activity across everyone the current user
/// follows. See trader_profile_repository.dart's fetchRecentActivity doc
/// comment for the N+1-reads-per-followed-user trade-off: this is fine at
/// this app's scale, but a real fan-out inbox (Cloud-Function-maintained,
/// like public_activity itself already is per-user) would be the next
/// step if the followed-count ever got large enough for this to matter.
final followingFeedProvider = FutureProvider<List<ActivityEvent>>((ref) async {
  final followedIds = ref.watch(followedUserIdsProvider).valueOrNull ?? const [];
  final repo = ref.watch(traderProfileRepositoryProvider);

  final perUserFeeds = await Future.wait(
    followedIds.map((uid) => repo.fetchRecentActivity(uid)),
  );

  final merged = perUserFeeds.expand((events) => events).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return merged.take(50).toList(growable: false);
});
