import 'package:cloud_firestore/cloud_firestore.dart';

import '../firestore/firestore_paths.dart';

/// Read side of the referral program — the `referrals` audit log is the
/// only thing this repository touches; `referral_code`/`referred_by`/
/// `pro_days_earned`/`pro_access_until` all live on the user's own account
/// doc and are already exposed via accountStreamProvider (see
/// TradingRepository.watchAccount), so there's no need to duplicate them
/// here.
class ReferralRepository {
  ReferralRepository(FirebaseFirestore firestore) : _paths = FirestorePaths(firestore);

  final FirestorePaths _paths;

  /// How many people this uid has successfully referred, via a count
  /// aggregation rather than fetching every doc — firestore.rules allows
  /// this because the query's own equality filter
  /// (`referrer_id == request.auth.uid`) already guarantees the same
  /// condition the rule checks per document.
  Future<int> fetchReferralCount(String uid) async {
    final agg = await _paths.referrals().where('referrer_id', isEqualTo: uid).count().get();
    return agg.count ?? 0;
  }
}
