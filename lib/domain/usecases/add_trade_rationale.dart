import 'package:cloud_functions/cloud_functions.dart';

class TradeRationaleException implements Exception {
  TradeRationaleException(this.message);
  final String message;

  @override
  String toString() => message;

  factory TradeRationaleException.fromFirebase(FirebaseFunctionsException e) {
    return TradeRationaleException(e.message ?? 'Could not save your note (${e.code}).');
  }
}

/// A thin wrapper around the `addTradeRationale` callable — deliberately
/// thin, because the constraints that actually matter (must be a closed
/// SELL trade, must be timestamped after the trade closed, content
/// filtering) are all enforced server-side in
/// functions/src/rationale/addTradeRationale.ts, not here. The client-side
/// length check below is instant UX feedback only, the same role
/// send_chat_message.dart's local debounce plays for chat rate limiting —
/// it is not what's protecting anything.
class AddTradeRationaleUseCase {
  AddTradeRationaleUseCase({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  static const maxLength = 280;

  /// Returns true if the server soft-flagged the text as forward-looking
  /// phrasing (still saved either way — see addTradeRationale.ts).
  Future<bool> call({required String orderId, required String text}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw TradeRationaleException("Rationale can't be empty.");
    }
    if (trimmed.length > maxLength) {
      throw TradeRationaleException('Rationale must be $maxLength characters or fewer.');
    }

    try {
      final result = await _functions.httpsCallable('addTradeRationale').call<Map<String, dynamic>>({
        'orderId': orderId,
        'text': trimmed,
      });
      return result.data['flagged'] as bool? ?? false;
    } on FirebaseFunctionsException catch (e) {
      throw TradeRationaleException.fromFirebase(e);
    }
  }
}
