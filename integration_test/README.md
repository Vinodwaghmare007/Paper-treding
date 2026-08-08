# Integration tests

These need a real Firestore/Auth emulator and a connected device (or
browser + chromedriver) — they can't run under plain `flutter test`, and
this sandbox has neither an Android/iOS device nor a configured web+
chromedriver toolchain, so they're written and reviewed but not executed
here. Everything else in `test/` (unit + widget tests) runs today via
plain `flutter test` and needs neither of those.

## `trade_flow_test.dart`

Exercises `ExecuteTradeUseCase` against a real Firestore + Auth emulator:
a full buy → sell → balance/P&L flow, a concurrency test proving two
racing buys that together would overdraw the account can't both succeed,
and a rejected-buy state-untouched check.

```bash
# 1. Start the emulators (from repo root)
cd functions && npx firebase emulators:start --only firestore,auth --project demo-test

# 2. In another terminal, with a device/emulator attached
flutter test integration_test/trade_flow_test.dart -d <device-id>
```

If the emulator isn't reachable at `localhost`, override the host:

```bash
flutter test integration_test/trade_flow_test.dart -d <device-id> \
  --dart-define=FIREBASE_EMULATOR_HOST=10.0.2.2   # Android emulator's alias for the host machine
```

## CI wiring

In CI, wrap the emulator start/stop around the test run instead of two
terminals, e.g.:

```bash
cd functions && npx firebase emulators:exec --only firestore,auth --project demo-test \
  "cd .. && flutter test integration_test/trade_flow_test.dart -d <ci-device-id>"
```
