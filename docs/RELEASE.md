# Release Guide

Everything needed to cut a Play Store release build, beyond what's already
automated. Read `docs/MANUAL_QA_CHECKLIST.md` too — this doc is about the
build/signing/store mechanics, that one is about verifying the app itself.

## 1. One-time: generate the release keystore

**Do this yourself, on your own machine, and never share the output.**
Nobody else — including whoever helped write this codebase — should ever
hold your release keystore or its passwords.

```bash
keytool -genkey -v -keystore ~/crypto-paper-trader-release.keystore \
  -keyalg RSA -keysize 2048 -validity 10000 -alias crypto_paper_trader
```

Back up the resulting `.keystore` file and the passwords you set,
somewhere durable and outside this repo (a password manager plus an
encrypted offline backup, not just one laptop's disk). **If you lose this
keystore, you permanently lose the ability to publish updates to whatever
Play Store listing you upload the first release under** — Google cannot
reissue or reset it. This is the single most unforgiving irreversible step
in the whole release process.

Then create `android/key.properties` (already gitignored — see
`android/.gitignore` — never commit it):

```properties
storePassword=<the keystore password>
keyPassword=<the key password>
keyAlias=crypto_paper_trader
storeFile=/absolute/path/to/crypto-paper-trader-release.keystore
```

`android/app/build.gradle.kts` reads this automatically; a release build
falls back to debug signing (and logs a warning) if the file is absent, so
`flutter run --release` still works day-to-day without it.

## 2. Bump the version before every release

`pubspec.yaml`'s `version: X.Y.Z+N` drives both `versionName` (X.Y.Z) and
`versionCode` (N) automatically — no separate Gradle edit needed.
`versionCode` must strictly increase on every Play Store upload, even for
a same-day hotfix.

## 3. Build

```bash
flutter build appbundle --release
```

Play Store wants an `.aab` (App Bundle), not an `.apk` — `appbundle` is
the right target, not `flutter build apk`. Output lands at
`build/app/outputs/bundle/release/app-release.aab`.

## 4. Test the actual release build before uploading anything

R8 minification (`isMinifyEnabled`/`isShrinkResources`, enabled in
`build.gradle.kts`) can break things that work fine in debug — reflection-
based plugin registration is the classic failure mode, and it fails
*silently* (no crash on launch, a specific feature just stops working).
Install the real release build on a device:

```bash
flutter install --release
# or: adb install build/app/outputs/apk/release/app-release.apk (if you
# also build an APK — build/app/outputs/bundle/*.aab isn't directly
# installable via adb)
```

Then walk `docs/MANUAL_QA_CHECKLIST.md` against *that* build — a checklist
pass on a debug build doesn't tell you anything about R8-related
breakage.

## 5. Crashlytics + Analytics

Both are wired up (`main.dart` initializes Crashlytics' error hooks;
`AnalyticsService` fires `sign_up`, `first_trade`, `puzzle_played`,
`backtest_run`, and `forecast_viewed`) but need a couple of things from
you:

- The Crashlytics Gradle plugin (`com.google.firebase.crashlytics`,
  needed to upload mapping/symbol files for de-obfuscated crash reports —
  the pubspec.yaml dependency alone isn't enough) is already wired into
  `android/settings.gradle.kts` and `android/app/build.gradle.kts`,
  cross-checked against the plugin's own example project rather than
  guessed. The pinned plugin version (3.0.2) may be a patch or two behind
  whatever's newest by the time you build — bump it if Gradle complains.
- There's no `subscription_started` event — this app has no subscription
  or paywall feature anywhere in Phases 1-5, so there was nothing to
  attach it to. Add it the day a real subscription flow ships.
- Crashlytics collection is disabled in debug builds (`kDebugMode`) on
  purpose, so a local `flutter run` crash doesn't show up in your
  production crash-free-users metric. Test the *release* build (per
  step 4 above) if you want to confirm reporting actually works.

## 6. Privacy policy hosting

`docs/privacy-policy.html` is written and ready, but two things need your
action before it's actually live:

1. **Replace the placeholder contact.** It currently reads
   `REPLACE_WITH_YOUR_SUPPORT_EMAIL` — a real support address, not that
   placeholder, has to be there before this ships (Play Console's Data
   Safety form and the app itself both link to this page).
2. **Enable GitHub Pages** for this repo: Settings → Pages → Source:
   "Deploy from a branch" → branch `main` (or whichever your default
   branch is), folder `/docs`. Once enabled, the page is at
   `https://vinodwaghmare007.github.io/Paper-treding/privacy-policy.html`
   — which is the URL both `sign_in_screen.dart`'s in-app link and the
   Data Safety form (see the Play Store listing notes) assume. If you use
   a different branch/path, override it at build time:
   `--dart-define=PRIVACY_POLICY_URL=https://your-actual-url`.

Verify the link actually resolves (not a 404) before submitting — this
could not be checked from this sandbox (no ability to enable GitHub Pages
settings or confirm DNS/deploy from here).

## 7. Certificate verification page

`docs/verify.html` (served from the same GitHub Pages setup as the privacy
policy) is what makes an earned certification checkable by a third party —
paste in or link to a `verification_code` and it looks the code up in the
public, unauthenticated-readable `public_certifications` Firestore
collection (see `firestore.rules` and
`functions/src/lib/certifications.ts`).

It needs one thing filled in before it works: `firebaseConfig` near the top
of the `<script>` block currently has `REPLACE_WITH_YOUR_FIREBASE_WEB_API_KEY`
placeholders — swap in your project's actual Web app config from Firebase
Console → Project settings → General → Your apps → Web app (register a Web
app there if you haven't). This is the standard public client config, not a
secret; `public_certifications`'s security rule (`allow read: if true`) is
what actually controls access, the same as every other public doc in this
app (`public_sentiment`, `public_market_weather`, `public_cohort_medians`).

Couldn't be tested end-to-end from this sandbox — no real Firebase project
or ability to load a page against live Firestore here. Once the config is
filled in, sanity-check it against a real earned certificate (Certs tab in
the app → tap a certificate → the code shown there) before relying on it.

## 8. App size (Phase G2 Part C)

A manual audit (no Flutter SDK in this sandbox — see section 11) found:

- **`cupertino_icons` removed from `pubspec.yaml`.** Zero `CupertinoIcons.*`
  references anywhere in `lib/` — this app only ever uses Material icons.
  A genuinely unused dependency, not just an unused *symbol* within a used
  package.
- **`assets/` is already lean**: `tradingview.html` (~10KB) and
  `lightweight-charts.standalone.production.js` (~160KB, the open-source
  "Lightweight Charts" library the TradingView-style chart bridge actually
  needs — not the full TradingView widget, and not further trimmable
  without breaking the chart). No unused/oversized images anywhere in the
  repo.
- **`android/app/build.gradle.kts` already has R8 minification +
  `isShrinkResources` enabled** (from the original release-readiness
  phase) — the biggest lever for app size is already pulled.
- **Split delivery is already the default and needs no gradle change.**
  `flutter build appbundle` produces an `.aab`; Play Console's Dynamic
  Delivery splits that into per-device downloads (ABI, density, language)
  automatically server-side. The `splits { abi { ... } }` gradle block
  some guides mention is for a *different* artifact — a raw multi-APK
  build via `flutter build apk --split-per-abi` — and would be the wrong
  thing to add here since this app ships as an App Bundle.
- Every dependency in `pubspec.yaml` besides `cupertino_icons` is actually
  imported somewhere in `lib/` (checked via `grep -rl "package:<name>/"
  lib/` per dependency) — no other unused Firebase modules or otherwise to
  trim.

**Run this yourself** — the one thing this sandbox genuinely cannot do:

```bash
flutter build appbundle --release --analyze-size
```

This prints an actual per-file/per-dependency size breakdown of the real
built artifact. Everything above is a source-level audit, not a
measurement — treat the `--analyze-size` output as the real numbers, and
re-run it after any dependency changes to confirm they moved the needle
the way you'd expect.

## 9. iOS / TestFlight (Phase G2 Part D)

The `ios/` project is the standard `flutter create` scaffold, essentially
untouched since this app has been built and tested Android-first. Before
it's TestFlight-ready:

- **`ios/Runner/GoogleService-Info.plist` is missing** — the iOS
  equivalent of `android/app/google-services.json`. Every `firebase_*`
  package in `pubspec.yaml` needs it. Download it from Firebase Console →
  Project settings → your iOS app (register one there first if you
  haven't) and drop it into `ios/Runner/`.
- **`Info.plist` updated with only what's actually needed**: a
  `UIBackgroundModes` entry (`remote-notification`) so `firebase_messaging`
  can deliver a price alert push while the app isn't in the foreground.
  Note this is *not* a "usage description" string — unlike camera/location/
  microphone, iOS notification permission has no Info.plist description
  key at all; the system prompt's text is fixed, and the actual permission
  request happens at runtime via `UNUserNotificationCenter` (see
  `notifications_service.dart`). Background push additionally needs the
  "Push Notifications" capability + `aps-environment` entitlement added in
  Xcode's Signing & Capabilities tab — that's an Xcode-generated project
  file change that can't be correctly hand-written outside Xcode itself.
  No camera/photo-library/biometric permission strings were added, because
  nothing in this codebase uses a camera, photo picker, or `local_auth` —
  an unused permission description is itself a plausible App Store review
  flag ("why does an educational trading app want camera access"), not
  just dead configuration. Add the real string the day a feature that
  actually needs it ships.
- **App Store category**: use **Education**, matching the Play Store
  listing's category (see `docs/PLAY_STORE_LISTING.md`) — same reasoning
  as that doc: this is a paper-trading simulator, not a real brokerage,
  and Apple's Finance category review requirements assume real money
  movement. Every App Store screenshot needs the same "SIMULATED —
  Educational only, no real money" framing already required for Play
  Store screenshots; don't crop it out to make a screenshot look cleaner.
- **Run `flutter build ios` and fix whatever it finds** — this sandbox has
  no macOS/Xcode, so this has never actually been built. The most likely
  real issue: `trading_chart_view.dart`'s `JavascriptChannel`/message-
  passing to the embedded chart HTML is exercised constantly on Android in
  this codebase's history but has never been run against iOS's WKWebView,
  which `webview_flutter` uses under the hood on iOS. Test the chart
  screen specifically (does it render, does tapping/zooming call back into
  Dart correctly) before assuming parity with Android.
- **Physical-device testing is required, not optional, for the offline
  mode added in this same phase** — see section 11.

## 10. Growth phase hosting (B2B landing page + tax guide)

Two more static pages join `privacy-policy.html` and `verify.html` on the
same GitHub Pages setup from section 6 — no new hosting config needed,
just the same `/docs` folder:

- `docs/for-academies.html` — the B2B "For Academies" sales landing page.
  Fill in `REPLACE_WITH_YOUR_ACADEMY_SALES_EMAIL` in its `<script>` block
  before linking to it anywhere; the contact form is a `mailto:` link, not
  a server-backed submission (deliberately lightweight — see section 11).
- `docs/india-crypto-tax-guide.html` — the standalone SEO/AI-search page
  for "India crypto tax" style queries, mirroring
  `tax_education_screen.dart`'s in-app content. Have its tax-rule claims
  reviewed before publishing (see section 11) — this is the one piece of
  content on this list where being wrong has real consequences for a
  reader, not just a broken link.

Once GitHub Pages is enabled (section 6), these resolve at
`https://vinodwaghmare007.github.io/Paper-treding/for-academies.html` and
`https://vinodwaghmare007.github.io/Paper-treding/india-crypto-tax-guide.html`
respectively — verify both actually load before pointing any real traffic
at them.

## 11. What this sandbox could not verify for you

No Android SDK, device, or emulator was available in the environment this
was built in — the signing config and ProGuard rules were written and
reviewed carefully (cross-checked against each plugin's actual Android
package names in the local pub cache, not guessed from memory), but
**never actually built**. Treat step 4 above as mandatory, not optional,
the first time you cut a release from this config.

The same applies, more strongly, to this phase's additions:

- **No Flutter/Dart SDK at all** in this sandbox — none of this phase's
  Dart changes (Remote Config coin list, the combined-stream WebSocket
  service, sqflite offline cache, connectivity-aware UI) have been run
  through `flutter analyze`, `flutter test`, or a real build. They were
  written carefully against this codebase's existing, already-verified
  patterns (the combined-stream service mirrors `BinanceWebSocketService`
  almost line-for-line; the sqflite cache mirrors the existing
  `HistoricalDataCache`), and a unit test was written for the new
  WebSocket service alongside the existing one's — but "written carefully"
  is not the same as "passed a build."
- **No macOS/Xcode** — `flutter build ios` has never run.
- **No network access to Binance/CoinGecko/Wikipedia from this sandbox**
  (blocked by the environment's egress proxy) — the 35 coins added to
  `supported_coin.dart` beyond the original 15 were curated from general
  knowledge of long-listed, high-liquidity Binance pairs, not verified
  live against `/exchangeInfo`. Spot-check the full list before shipping;
  see the TODO comment at the top of that file.
- **Offline mode specifically must be tested by toggling airplane mode on
  a real device**, not just by reasoning about the code — this was
  explicitly called out as a requirement for this phase and genuinely
  cannot be substituted with anything this sandbox can do. Check, at
  minimum: the chart screen cold-opened while already offline (should show
  cached candles + the offline banner, never a blank screen or spinner
  that never resolves), a trade attempt while offline (should be disabled
  with the explanatory notice, not silently fail after a tap), and the
  portfolio/orders screens offline (should show last-synced data via
  Firestore's own offline cache plus the generic offline banner).

This phase's Growth-phase additions (org/B2B licensing, referrals, tax
education hub) carry the same "written carefully, never built" caveat as
above, plus:

- The `functions/src/growth/*.ts` additions (`orgs.ts`, `referrals.ts`,
  `computeOrgAggregateStats.ts`) DID get run through `npx tsc --noEmit`
  successfully in this sandbox (Node/npm/TypeScript are available here,
  unlike Flutter) — that only proves they type-check, not that the
  Firestore transaction logic behaves correctly against a real project.
  Before relying on the atomic-seat-limit guarantee, exercise
  `redeemOrgInviteCode` against the Firebase emulator with two concurrent
  redemptions on an org with exactly one open seat, and confirm only one
  succeeds.
- India's crypto tax rules described in `tax_education_screen.dart` and
  `docs/india-crypto-tax-guide.html` (the flat 30% tax under Section
  115BBH, the 1% TDS under Section 194S) were written from general
  training knowledge, not verified against a live, current-year
  government source — no network access to check this from this sandbox.
  Tax law can change; have this content reviewed against the current Income
  Tax Act / CBDT guidance before it goes live, the same way the
  translation content needs a native-speaker pass.
- `docs/for-academies.html`'s contact form has a
  `REPLACE_WITH_YOUR_ACADEMY_SALES_EMAIL` placeholder (same pattern as the
  privacy policy's `REPLACE_WITH_YOUR_SUPPORT_EMAIL`) — it must be filled
  in before this page is worth linking anywhere. The form itself is a
  plain `mailto:` link, not a server-backed submission — deliberately kept
  that lightweight per the "this is a sales tool, don't over-invest
  engineering here" brief; swap it for a real form backend later if lead
  volume justifies it.
- `organizations/{orgId}` docs themselves are still provisioned manually
  via the Admin SDK (no self-serve org creation flow exists, by design —
  see `firestore_paths.dart`'s doc comment) — creating a real org for a
  pilot academy is a manual step, not something this phase automated.

The News Feed's provider-based rewrite (`functions/src/news/*.ts`, second
rewrite of this feature — first CryptoPanic client-side, then RSS
aggregation, now this) is built around a `NewsProvider` interface
specifically so the active data source can change without touching
storage/dedupe/pruning/display at all. Which provider is actually active
today, and why, needs to be understood before this is deployed:

- **CoinGecko's News endpoint could not be verified — at all — and is NOT
  the active provider.** This sandbox has zero outbound network access,
  confirmed by both a direct `curl` through the environment's egress proxy
  (`CONNECT tunnel failed, response 403`) and `WebFetch` (`EGRESS_BLOCKED`)
  against both `api.coingecko.com` and `docs.coingecko.com`. Unlike the
  earlier RSS phase (where the *URLs* were unverified but RSS itself is a
  well-understood, stable format), here the endpoint's very *existence* on
  CoinGecko's public API, its required plan tier, its auth method, and its
  response schema are all unconfirmed — this app's own existing CoinGecko
  usage (`coingecko_source.dart`) only ever calls `/coins/markets`, with no
  API key at all, so "reuses existing API key/infra" does not actually
  hold for a News endpoint either. `coinGeckoNewsProvider.ts` is a
  complete, real implementation (not a stub) written from a best-effort
  guess at the schema, and its own doc comment repeats this warning in
  full — **do not switch `aggregateNews.ts`'s `activeProvider` to it
  without confirming the endpoint against CoinGecko's live docs first.**
- **CryptoPanic is what's actually deployed**, per the spec's own explicit
  fallback instruction for exactly this situation. `cryptoPanicNewsProvider.ts`
  is built against the same `/api/v1/posts/` schema this codebase's
  original (now-retired) client-side CryptoPanic integration used — also
  never exercised against a live response, but at least a schema this
  project has reasoned through more than once, not a fresh guess. Confirm
  it against a real API call before the first production deploy.
- **New prerequisite this phase adds: a `CRYPTOPANIC_API_TOKEN` secret.**
  `aggregateNews.ts` reads it via `defineSecret` (Secret Manager), not an
  env var or `functions.config()` — before deploying, run:
  `firebase functions:secrets:set CRYPTOPANIC_API_TOKEN` (get a free token
  from cryptopanic.com's API settings) and grant the Cloud Functions
  service account access if prompted. Moving this server-side (rather than
  the old client-side `--dart-define`) also means the token no longer
  ships inside the app binary.
- **`npm run test:news` (25 assertions) and `npx tsc --noEmit` both passed**
  in this sandbox — dedupe (`computeNewsItemId`), truncation
  (`truncateSummary`, including the exact 150-char boundary), item mapping
  (`buildNewsItem`), and both providers' response parsing (`parseResponse`,
  against saved sample JSON, not live calls — CoinGecko's sample is
  necessarily built from the same unverified guessed schema, so a passing
  test there proves the parser is internally consistent, not that it's
  correct). None of this exercises `aggregateNews.ts`'s actual Firestore
  writes/prune or the failure-alert bookkeeping (`news_pipeline_status`)
  against a real project or the Firebase emulator.
- **The consecutive-failure alert is log-based, not wired to anything
  yet.** `recordNewsRunFailure` writes to `news_pipeline_status/state` and
  logs a line prefixed `ALERT:` once 3 runs in a row fail. That line does
  nothing on its own — in Google Cloud Console, create a Logging
  log-based metric matching that exact string (Logging → Log-based
  Metrics), then an Alerting policy on that metric, so a silently-broken
  news feed actually reaches someone instead of just sitting in Cloud
  Logging unread.
- **Deploy note**: `aggregateCryptoNews` needs `firebase deploy --only
  functions:aggregateCryptoNews` (or a full functions deploy) like any
  other scheduled function in this codebase — it runs every 25 minutes
  once deployed, no separate Cloud Scheduler setup needed (the
  `onSchedule` trigger provisions that itself, same as
  `aggregateCommunitySentiment`/`computeCohortMedians`).
