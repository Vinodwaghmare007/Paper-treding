/// One followed coin on the Markets/Watchlist screen — a thin wrapper
/// around `users/{uid}/watchlist/{symbol}` (see watchlist_repository.dart).
class WatchlistEntry {
  const WatchlistEntry({
    required this.symbol,
    required this.sortOrder,
    required this.addedAt,
  });

  factory WatchlistEntry.fromMap(String symbol, Map<String, dynamic> map) {
    final addedAtRaw = map['added_at'];
    return WatchlistEntry(
      symbol: symbol,
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
      // Duck-typed .toDate() rather than importing cloud_firestore's
      // Timestamp here, matching trader_profile.dart's fromMap — keeps
      // this a plain Dart entity with no Firestore SDK dependency.
      addedAt: addedAtRaw == null ? DateTime.now() : (addedAtRaw as dynamic).toDate() as DateTime,
    );
  }

  final String symbol;
  final int sortOrder;
  final DateTime addedAt;
}
