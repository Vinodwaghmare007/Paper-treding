import 'package:cloud_functions/cloud_functions.dart';

class OrgInviteCodeException implements Exception {
  OrgInviteCodeException(this.message);
  final String message;

  @override
  String toString() => message;

  factory OrgInviteCodeException.fromFirebase(FirebaseFunctionsException e) {
    return OrgInviteCodeException(e.message ?? 'Could not create an invite code (${e.code}).');
  }
}

/// Thin wrapper around the `createOrgInviteCode` callable — every real
/// check (caller is actually an admin of this org) happens server-side in
/// functions/src/growth/orgs.ts, same division of responsibility as
/// AddTradeRationaleUseCase.
class CreateOrgInviteCodeUseCase {
  CreateOrgInviteCodeUseCase({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  Future<String> call({required String orgId}) async {
    try {
      final result = await _functions
          .httpsCallable('createOrgInviteCode')
          .call<Map<String, dynamic>>({'orgId': orgId});
      return result.data['code'] as String;
    } on FirebaseFunctionsException catch (e) {
      throw OrgInviteCodeException.fromFirebase(e);
    }
  }
}
