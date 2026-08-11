import 'package:firebase_analytics/firebase_analytics.dart';

/// Typed wrapper around Firebase Analytics — one named method per event
/// this app actually fires, rather than callers passing raw event-name
/// strings around. Every event here answers "which feature actually drove
/// someone to come back," per the product ask.
///
/// `subscription_started` from that same ask is deliberately not
/// implemented: there is no subscription/paywall feature anywhere in this
/// app (Phases 1-5 are entirely free — paper trading, forecasts,
/// backtesting, community features). Wiring up an event for a purchase
/// flow that doesn't exist would just be a dead call site nobody could
/// ever trigger; add it here the day a real subscription feature ships.
class AnalyticsService {
  AnalyticsService({FirebaseAnalytics? analytics})
      : _analytics = analytics ?? FirebaseAnalytics.instance;

  final FirebaseAnalytics _analytics;

  /// A brand-new account was created — email/password sign-up or a
  /// user's first-ever Google sign-in. Never fires on a returning user's
  /// sign-in (see AuthRepository._ensureUserDocument, which only calls
  /// this the one time it creates the users/{uid} doc).
  Future<void> logSignUp({required String method}) {
    return _analytics.logSignUp(signUpMethod: method);
  }

  /// This device's first-ever successfully executed BUY or SELL. Tracked
  /// on-device (see FirstTradeTracker) rather than server-side — an
  /// approximation ("first trade on this install"), not a hard guarantee
  /// against a user who trades once, reinstalls, and trades again, which
  /// is an acceptable trade-off for an engagement-funnel signal.
  Future<void> logFirstTrade({required String orderType}) {
    return _analytics.logEvent(
      name: 'first_trade',
      parameters: {'order_type': orderType},
    );
  }

  /// A daily puzzle guess was successfully submitted and scored.
  Future<void> logPuzzlePlayed({required bool correct}) {
    return _analytics.logEvent(
      name: 'puzzle_played',
      parameters: {'correct': correct},
    );
  }

  /// A backtest finished running (not just configured/started) and
  /// produced a result.
  Future<void> logBacktestRun({required int closedTrades}) {
    return _analytics.logEvent(
      name: 'backtest_run',
      parameters: {'closed_trades': closedTrades},
    );
  }

  /// The AI forecast overlay was switched on and a forecast actually
  /// loaded (not just the toggle tapped — a failed fetch doesn't count as
  /// "viewed").
  Future<void> logForecastViewed() {
    return _analytics.logEvent(name: 'forecast_viewed');
  }

  /// A referral or org-invite code entered at sign-up was successfully
  /// redeemed. [type] is `'org_invite'` or `'referral'` — see
  /// AuthRepository._redeemInviteOrReferralCode, which tries both server
  /// side since a code's shape doesn't reveal which kind it is.
  Future<void> logInviteCodeRedeemed({required String type}) {
    return _analytics.logEvent(
      name: 'invite_code_redeemed',
      parameters: {'type': type},
    );
  }
}
