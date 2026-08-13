# Manual QA Checklist — Pre-Release

Do not submit to the Play Store until every box below is checked on a real
device. This list was produced alongside a code-level audit (see notes
under each item for what's already fixed vs. what still needs a human with
a device/TalkBack).

## 1. Disclaimers

- [x] **Onboarding** — `sign_in_screen.dart` shows "Educational simulator
      — no real funds involved." directly under the app name, above the
      sign-in form. Verify it renders before any input field on first launch.
- [x] **Forecast toggle** — the AI Forecast card shows the backend's
      disclaimer text ("This is a mathematical projection based on
      historical price patterns. It is not financial advice and carries no
      guarantee of accuracy.") whenever a forecast is loaded
      (`ticker_screen.dart`'s `_ForecastToggle`). Verify it's visible
      without needing to scroll, right after toggling the switch on.
- [x] **Backtester results** — now shows "Simulated against historical
      data — past performance on this window is not a guarantee of future
      results." directly under the "Results" heading (added in this pass;
      previously had zero disclaimer language). Verify it's visible
      without scrolling past the P&L/win-rate tiles.
- [ ] **Manual check**: read every disclaimer string out loud — is any of
      them ambiguous, or could a reasonable reader think real money is at
      stake? (Nothing flagged in the code audit, but this is a judgment
      call worth a second pair of eyes.)

## 2. "SIMULATED" / "Educational — No Real Money" coverage

- [x] **Home screen footer** — `SimulatedFooter` (new) is now permanently
      docked above the bottom nav bar in `HomeShell`, which wraps *every*
      signed-in tab (Chart, Portfolio, Orders, Backtest, Replay, Chat,
      News, Puzzle, What-If) in one `Scaffold` — so this single widget
      covers "every screen that shows a dollar figure" without needing to
      duplicate text into each screen individually. Verify it's visible
      (not clipped) on at least one small-screen device (e.g. a phone with
      a tall aspect ratio and gesture nav bar eating into safe area).
- [x] **Daily Puzzle (pre-auth)** — the one screen reachable *outside*
      HomeShell (pushed directly from the sign-in screen for "no login
      required to play") doesn't get the shared footer, so it has its own
      "Practice only — no real trades or money." line in its header.
- [ ] **App icon splash** — native Android splash
      (`android/app/src/main/res/drawable/launch_background.xml`) is a
      plain background/logo with no text, which is normal splash-screen
      practice (a paragraph of legal text on a splash screen would itself
      be a UX smell). The very next screen the user sees is the sign-in
      screen, which does carry the disclaimer. Confirm on a real device
      that there's no gap where dollar figures or trading UI are visible
      *before* that disclaimer has rendered.
- [ ] **Manual check**: scroll through every screen once more on a device
      and confirm nothing shows a $ figure with the footer scrolled out of
      view or otherwise hidden behind a keyboard/modal.

## 3. External links

- [x] **Audited every `launchUrl`/hardcoded URL in `lib/`.** The only
      user-facing external navigation is `news_feed_screen.dart` opening
      whatever `source_url` the backend's RSS aggregation (see
      docs/RELEASE.md) wrote onto a `news_items` doc, in an in-app
      browser tab — that's the original publisher's own page, not an
      affiliate/referral link.
      `forecast_api_source.dart`'s URLs are just the backend's own API base
      URL (a build-time config value, never shown to the user). No
      exchange sign-up/referral links, no "trade real crypto" prompts,
      anywhere in the app.
- [ ] **Manual check**: re-run this audit (`grep -rn "launchUrl\|https://" lib/`)
      any time the news feed or share-card copy changes, since a future
      change could introduce one without anyone noticing.

## 4. Accessibility

- [x] **Tap targets** — audited every custom `InkWell`/`GestureDetector`
      and every `IconButton` with an overridden `constraints`. Found and
      fixed three real sub-44dp targets: the chat report-message icon
      (`community_chat_screen.dart`, was a bare 14px `InkWell`), and the
      dismiss buttons on the high-frequency-trading banner
      (`high_frequency_banner.dart`, was using an *unconstrained*
      `BoxConstraints()` that shrank the tap area to the icon itself).
      Both now guarantee a 44x44 minimum via `IconButton`'s `constraints`.
- [x] **Screen-reader labels** — added missing `tooltip`s (which Flutter
      surfaces as the accessible name) to icon-only buttons that had none:
      chat send button, backtester's "remove condition" button, Market
      Replay's exit and play/pause buttons, and the high-frequency banner's
      dismiss button.
- [x] **Color contrast — quantified, not guessed.** Computed WCAG relative
      luminance for this theme's `Colors.white38` against both background
      tones (`#131722`, `#1E222D`): **≈3.5:1**, below the 4.5:1 AA minimum
      for normal text (`Colors.white54` and above pass comfortably, at
      ≈5.6:1+). Fixed the three *safety-relevant* strings added in this
      pass (the SIMULATED footer, the backtester disclaimer, the puzzle
      disclaimer) to `white70`.
  - [ ] **Not yet fixed — needs a design decision, not a blind find-replace**:
        `Colors.white38`/`white24`/`white12` are used **33 times across 13
        files** for de-emphasized text that predates this pass (timestamps,
        helper hints, secondary labels — e.g. "No holdings yet", chat
        message timestamps, order history sub-labels). Every one of these
        technically fails AA at normal text sizes on this theme's dark
        backgrounds. This wasn't bulk-fixed here because (a) it's 13 files
        of visual-only change with no device available in this environment
        to confirm the result still looks intentional, and (b) some of
        these really are meant to be de-emphasized relative to primary
        text, so the right fix is probably introducing a proper contrast-
        checked "tertiary text" color token (e.g. one fixed `white65`-ish
        value used everywhere instead of three different raw opacities)
        rather than a mechanical find-replace. Run
        `grep -rn "Colors.white38\|Colors.white24\|Colors.white12" lib/`
        to see the full list before deciding.
- [ ] **TalkBack pass on core flows** — needs a real Android device, not
      done here. At minimum, walk through with TalkBack on:
  - [ ] Sign in / sign up
  - [ ] Open the Buy sheet, enter a quantity, submit
  - [ ] Trigger the revenge-blocker (3 losing sells) and confirm the
        hard-lock sheet's content is announced and the countdown doesn't
        spam announcements every second
  - [ ] Play the daily puzzle end-to-end
  - [ ] Send a chat message and report someone else's message
  - [ ] Confirm every `Icon`-only control that isn't already covered above
        is announced with a sensible label (this pass fixed the ones found
        by code review; TalkBack may surface others that only show up at
        runtime, e.g. from third-party widgets like `SegmentedButton` or
        `DropdownMenuItem`)

## 5. Functional edge cases (see also automated coverage)

- [x] **Rapid double-tap on Buy/Sell** — `trade_sheet.dart` already
      disables the submit button for the duration of the in-flight call
      (`_submitting` guard), so a UI-level double-tap can't fire two
      requests. Independently, `ExecuteTradeUseCase.buy/sell` use a real
      Firestore `runTransaction`, which is where the actual money-safety
      guarantee lives — verified with a real Firestore-emulator
      integration test in `integration_test/trade_flow_test.dart` (two
      concurrent buys that together would overdraw the account: exactly
      one succeeds, balance never goes negative). That test needs a
      device/CI runner to execute — see `integration_test/README.md`.
- [x] **WebSocket disconnect/reconnect** — covered by a real, executed
      test suite (`test/data/sources/binance_websocket_service_test.dart`)
      against a fake channel: stream errors and server-closed connections
      both trigger the backoff-based reconnect, malformed frames are
      skipped without killing the stream, and `dispose()` stops further
      reconnect attempts. The connection-status badge
      (`ticker_screen.dart`'s `_ConnectionBadge`) is what tells the user
      the feed isn't live during a drop — the last-known price stays on
      screen (a better UX than blanking it), but always next to a badge
      reading CONNECTING/RECONNECTING/OFFLINE. **Manual check**: physically
      disable network on a device mid-session and confirm the badge
      updates and the app doesn't crash or freeze.
- [x] **Firestore offline mode** — found and fixed a real bug:
      `TradeSheet._submit` only caught `TradeRejected`, so a Firestore
      transaction failure while offline (transactions need a live
      round-trip, unlike a plain queued write) would have propagated as an
      unhandled exception with no user-facing message. Now caught and
      shown as "Couldn't reach the server — check your connection and try
      again." — covered by `test/features/trade/trade_offline_error_test.dart`.
      **Manual check**: put a device in airplane mode, attempt a trade,
      confirm the message appears and no order was written once back
      online (check Order History doesn't gain a phantom entry).
- [ ] **Manual check**: kill the app mid-trade (force-stop, not just
      backgrounding) right after tapping Confirm, then relaunch — confirm
      the account ends up in a consistent state (either the trade fully
      happened or it didn't; no partial state).
