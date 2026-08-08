# Play Store Listing

Ready-to-paste content for the Play Console listing, plus what needs a
human (screenshots, the actual questionnaire submission, the pre-launch
report) — none of that is possible from this sandbox.

## App title (max 30 characters)

```
Crypto Paper Trader: Sim
```
(24 characters — leaves headroom, and "Sim" makes the "not real trading"
signal show up in search results and the store listing itself, not just
buried in the description.)

## Category

**Education** — not Finance. (Confirmed from the product's own framing
throughout this build: no real money, no real exchange integration, the
whole point is to *learn* trading mechanics risk-free. Finance-category
apps also draw substantially more regulatory/review scrutiny that this
app doesn't need to invite.)

## Short description (max 80 characters)

```
Educational crypto trading simulator. Practice with fake money — no real risk.
```
(79 characters — verify against the live character counter in Play
Console, since exact limits/counting can shift.)

## Full description

Lead sentence is non-negotiable — "Educational. No real money." has to be
the *first* thing a reader sees, not buried under a features list:

```
Educational only — no real money, ever. Crypto Paper Trader is a
risk-free simulator for practicing crypto trading mechanics using live
market data, without a single real rupee, dollar, or satoshi at stake.

WHAT YOU CAN DO
• Trade a live BTC/USDT chart with a simulated ₹1,00,000 starting balance
• See an AI-generated price projection overlay (a statistical estimate,
  not a prediction — full disclaimer shown in-app)
• Build and backtest your own strategy against historical data
• Replay real historical events (bull runs, crashes) at your own pace
• Play a daily chart puzzle and build a streak
• Join skill-matched community chat rooms
• Compare your simulated portfolio to similar traders (anonymized)

BUILT-IN SAFEGUARDS
This app is built to teach good habits, not encourage compulsive trading:
• A "revenge-trading" cooldown pauses new buys after 3 losses in a row
• A high-frequency-trading nudge if you're trading unusually often
• Every dollar figure in the app is clearly marked as simulated

Nothing in this app connects to a real exchange, bank account, or
payment method — there is no way to deposit, withdraw, or risk real
money using this app. All prices are the app's own simulation running
against live public market data feeds, purely for practice.
```

## Screenshots

Every screenshot that shows the trading UI or a dollar figure needs a
**"SIMULATED"** watermark — small, legible, doesn't have to dominate the
image, just has to be unambiguous. This can't be produced here (no device
to actually capture screenshots from), but once you have real screenshots:

```bash
# Example using ImageMagick (brew install imagemagick / apt install imagemagick)
for f in screenshots/*.png; do
  magick "$f" -gravity North -pointsize 36 -fill white -stroke black \
    -strokewidth 2 -annotate +0+20 "SIMULATED — NO REAL MONEY" "$f"
done
```

Adjust `-pointsize`/position per your actual screenshot resolution — test
on one image before batch-processing all of them.

## Content rating questionnaire

Answer accurately, not defensively — the app's actual content:
- **Simulated gambling:** No. There's no chance-based wagering; outcomes
  are driven by real historical/live market data, and the daily puzzle is
  a skill guess, not a bet.
- **Real gambling / real-money wagering:** No — the entire point of the
  app is that no real money is ever involved.
- **User-generated content:** Yes (community chat) — already covered by
  the in-app report-message flow and the server-side rate-limit/
  profanity filtering built into `sendChatMessage`. Disclose the chat
  feature and its moderation (report button, no fully-automated
  moderation beyond a basic filter) accurately in the questionnaire.
- **Real financial transactions:** No.

## Data Safety section

Match this against what `docs/privacy-policy.html` actually describes —
they need to agree with each other, since Google spot-checks listings
against their linked privacy policies.

**Data collected:**
| Data type | Collected? | Purpose | Shared with 3rd parties? |
|---|---|---|---|
| Email address | Yes | Account management | No |
| User IDs | Yes | Account management, app functionality | No |
| App activity (in-app actions, analytics events) | Yes | Analytics | No |
| Crash logs / diagnostics | Yes | Analytics (Crashlytics) | No |
| Financial info | **No** | — | — |
| Location | **No** | — | — |
| Contacts / photos / files | **No** | — | — |

- **Is all user data encrypted in transit?** Yes (standard Firebase
  TLS for all Auth/Firestore/Functions/Analytics traffic).
- **Can users request data deletion?** Yes — in-app (account menu →
  Delete account) per `docs/privacy-policy.html`, calling the
  `deleteAccount` Cloud Function.
- **Is data sold to third parties?** No.
- **Is data used for advertising?** No (no ad SDK is integrated anywhere
  in this app).

If you ever add an ads SDK later, this entire section needs revisiting —
that's the one change that would make several of these "No" answers
wrong.

## Pre-launch report

Play Console runs this automatically once you upload a build to any
track (internal testing is enough to trigger it) — it crawls the app on
a range of real devices and flags crashes, security issues, and
accessibility problems. Fix everything it finds before promoting to
production. This cannot be run from this sandbox (needs an actual Play
Console upload) — treat it as a mandatory step after `docs/RELEASE.md`'s
build process, before the app goes to production.
