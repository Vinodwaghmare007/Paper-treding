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

## 8. What this sandbox could not verify for you

No Android SDK, device, or emulator was available in the environment this
was built in — the signing config and ProGuard rules were written and
reviewed carefully (cross-checked against each plugin's actual Android
package names in the local pub cache, not guessed from memory), but
**never actually built**. Treat step 4 above as mandatory, not optional,
the first time you cut a release from this config.
