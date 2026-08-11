import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/referral_repository.dart';
import '../../domain/usecases/generate_referral_code.dart';
import '../auth/auth_providers.dart';

final referralRepositoryProvider = Provider<ReferralRepository>((ref) {
  return ReferralRepository(ref.watch(firebaseFirestoreProvider));
});

final generateReferralCodeUseCaseProvider =
    Provider<GenerateReferralCodeUseCase>((ref) => GenerateReferralCodeUseCase());

/// How many people the signed-in user has successfully referred.
/// autoDispose + no caching beyond the widget's lifetime — this is a
/// glance-once stat, not something that needs to stay live-updating while
/// the screen is closed.
final referralCountProvider = FutureProvider.autoDispose<int>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return 0;
  return ref.watch(referralRepositoryProvider).fetchReferralCount(uid);
});
