import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/usecases/whatif_generator.dart';
import '../ticker/ticker_providers.dart';

final whatIfGeneratorProvider = Provider<WhatIfGeneratorUseCase>((ref) {
  final restService = ref.watch(binanceRestServiceProvider);
  return WhatIfGeneratorUseCase(restService: restService);
});

/// Async state for the currently generated (or generating) What-If result.
/// A plain [Notifier] rather than a stream — generation only ever happens
/// on an explicit user tap (see whatif_screen.dart's "Generate" button),
/// never something to watch continuously.
class WhatIfNotifier extends AsyncNotifier<WhatIfResult?> {
  @override
  Future<WhatIfResult?> build() async => null;

  Future<void> generate() async {
    state = const AsyncLoading<WhatIfResult?>().copyWithPrevious(state);
    state = await AsyncValue.guard(
      () => ref.read(whatIfGeneratorProvider).generate(),
    );
  }
}

final whatIfProvider = AsyncNotifierProvider<WhatIfNotifier, WhatIfResult?>(
  WhatIfNotifier.new,
);
