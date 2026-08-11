/// Pure bucketing logic for "2h ago"-style labels — kept Flutter/l10n-free
/// so it's directly unit-testable; news_feed_screen.dart turns the result
/// into a localized string via AppLocalizations.
enum RelativeTimeUnit { justNow, minutes, hours, days }

class RelativeTime {
  const RelativeTime(this.unit, this.magnitude);

  final RelativeTimeUnit unit;

  /// Meaningless for [RelativeTimeUnit.justNow]; the number of
  /// minutes/hours/days otherwise.
  final int magnitude;
}

/// Buckets the gap between [from] and [now] into whichever unit reads most
/// naturally — under a minute is "just now", under an hour is minutes,
/// under a day is hours, otherwise days (uncapped; a 20-day-old item, were
/// one ever to survive that long, reads as "20d ago" rather than switching
/// units again — the 14-day prune on the backend means this in practice
/// never exceeds ~14).
RelativeTime computeRelativeTime(DateTime from, DateTime now) {
  final diff = now.difference(from);
  if (diff.inMinutes < 1) return const RelativeTime(RelativeTimeUnit.justNow, 0);
  if (diff.inMinutes < 60) return RelativeTime(RelativeTimeUnit.minutes, diff.inMinutes);
  if (diff.inHours < 24) return RelativeTime(RelativeTimeUnit.hours, diff.inHours);
  return RelativeTime(RelativeTimeUnit.days, diff.inDays);
}
