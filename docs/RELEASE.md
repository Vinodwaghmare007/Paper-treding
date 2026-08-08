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

## 5. What this sandbox could not verify for you

No Android SDK, device, or emulator was available in the environment this
was built in — the signing config and ProGuard rules were written and
reviewed carefully (cross-checked against each plugin's actual Android
package names in the local pub cache, not guessed from memory), but
**never actually built**. Treat step 4 above as mandatory, not optional,
the first time you cut a release from this config.
