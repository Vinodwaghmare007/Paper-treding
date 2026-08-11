import 'package:cloud_functions/cloud_functions.dart';

class ReferralCodeException implements Exception {
  ReferralCodeException(this.message);
  final String message;

  @override
  String toString() => message;

  factory ReferralCodeException.fromFirebase(FirebaseFunctionsException e) {
    return ReferralCodeException(e.message ?? 'Could not create a referral code (${e.code}).');
  }
}

/// Thin wrapper around the `generateReferralCode` callable — idempotent
/// server-side (see functions/src/growth/referrals.ts), so it's safe to
/// call every time referral_screen.dart opens for a user who doesn't have
/// a code yet.
class GenerateReferralCodeUseCase {
  GenerateReferralCodeUseCase({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  Future<String> call() async {
    try {
      final result =
          await _functions.httpsCallable('generateReferralCode').call<Map<String, dynamic>>();
      return result.data['code'] as String;
    } on FirebaseFunctionsException catch (e) {
      throw ReferralCodeException.fromFirebase(e);
    }
  }
}
