import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/conditional_order_repository.dart';
import '../../domain/entities/conditional_order.dart';
import '../auth/auth_providers.dart';

final conditionalOrderRepositoryProvider = Provider<ConditionalOrderRepository>((ref) {
  return ConditionalOrderRepository(ref.watch(firebaseFirestoreProvider));
});

/// Every conditional order (active and already-triggered) for the signed-in
/// user — screens filter down to what they need (active-only, one symbol)
/// themselves, same shape as [orderHistoryStreamProvider] in
/// portfolio_providers.dart.
final conditionalOrdersProvider = StreamProvider<List<ConditionalOrder>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return const Stream.empty();
  return ref.watch(conditionalOrderRepositoryProvider).watchConditionalOrders(uid);
});

/// Just the active stop-loss/take-profit for one symbol — what the
/// Portfolio holding tile and the set-order sheet actually care about.
final activeConditionalOrdersForSymbolProvider =
    Provider.family<List<ConditionalOrder>, String>((ref, coinSymbol) {
  final all = ref.watch(conditionalOrdersProvider).valueOrNull ?? const [];
  return [for (final o in all) if (o.isActive && o.coinSymbol == coinSymbol) o];
});
