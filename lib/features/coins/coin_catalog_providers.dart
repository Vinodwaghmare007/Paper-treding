import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/entities/supported_coin.dart';
import '../../data/sources/remote_config_coin_source.dart';

final remoteConfigCoinSourceProvider = Provider<RemoteConfigCoinSource>((ref) {
  return RemoteConfigCoinSource();
});

/// The coin catalog every screen should actually list/search/pick from —
/// the bundled [supportedCoins] default, overlaid with a live Remote
/// Config payload once one has been fetched, so a coin can be added
/// without an app store release. Callers should read
/// `ref.watch(supportedCoinsProvider).valueOrNull ?? supportedCoins` so the
/// UI has a synchronous, always-correct list before the first fetch
/// resolves too (see RemoteConfigCoinSource's doc comment for the full
/// fallback chain).
final supportedCoinsProvider = FutureProvider<List<SupportedCoin>>((ref) async {
  return ref.watch(remoteConfigCoinSourceProvider).fetchSupportedCoins();
});
