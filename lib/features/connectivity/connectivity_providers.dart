import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final _connectivityInstanceProvider = Provider<Connectivity>((ref) => Connectivity());

/// The device's current connectivity state(s) — a list because a device
/// can technically report more than one active interface (e.g. wifi +
/// vpn). Seeded with an immediate [Connectivity.checkConnectivity] call
/// before switching to [Connectivity.onConnectivityChanged] so there's a
/// real value from the very first frame rather than a brief "loading"
/// state every screen watching [isOnlineProvider] would otherwise have to
/// handle.
final connectivityProvider = StreamProvider<List<ConnectivityResult>>((ref) async* {
  final connectivity = ref.watch(_connectivityInstanceProvider);
  yield await connectivity.checkConnectivity();
  yield* connectivity.onConnectivityChanged;
});

/// Whether the device has ANY active network interface. This is reachability
/// at the OS/radio level, not proof a given request will succeed (captive
/// portals, DNS issues, and a fully-down Binance/Firestore all still count
/// as "online" here) — screens that need "is data actually fresh" already
/// track that themselves via each cache's `isStale`/`fetchedAt`, this is
/// only for deciding whether to show the offline banner and lock trading.
final isOnlineProvider = Provider<bool>((ref) {
  final results = ref.watch(connectivityProvider).valueOrNull;
  // Optimistic default before the first connectivity read resolves —
  // matches every other feed in this app (chart, portfolio) starting in a
  // "loading" rather than "offline" state.
  if (results == null) return true;
  return results.any((r) => r != ConnectivityResult.none);
});

/// True when the only active interface is metered mobile data (no wifi/
/// ethernet alongside it) — used to trim the cold-start data fetch (Part B
/// #8). Not a real bandwidth/speed measurement (connectivity_plus reports
/// interface type, not 2G vs 5G) — it's a reasonable proxy: mobile data is
/// far more likely to be both slower and metered than wifi for the
/// Tier-2/3 users this is aimed at, but it isn't a guarantee either way.
final isOnMeteredConnectionProvider = Provider<bool>((ref) {
  final results = ref.watch(connectivityProvider).valueOrNull;
  if (results == null || results.isEmpty) return false;
  final hasWifiOrEthernet =
      results.contains(ConnectivityResult.wifi) || results.contains(ConnectivityResult.ethernet);
  final hasMobile = results.contains(ConnectivityResult.mobile);
  return hasMobile && !hasWifiOrEthernet;
});
