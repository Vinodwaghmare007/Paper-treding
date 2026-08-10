# Translation Glossary — Crypto Paper Trader

Fixes the exact term to use for each core financial concept, in each supported
language, **before** any ARB translation happens. The single most common way a
localized finance app reads as amateurish to a native speaker is inconsistent
terminology for the same concept across screens — one screen says "portfolio"
another says "holdings," one screen says "अलर्ट" another says "सूचना." Every
translator (human or the initial machine draft) must use the term in this
table, not a synonym, even if the synonym is individually "more correct."

## How to read this table

- **EN** is the term as used in the English (base) ARB file.
- **Every non-English column in this table, and every string in every
  `app_<locale>.arb` file, is a machine draft** — produced by an AI
  assistant, not yet read in-context by any human. `translation_status` is
  `"machine_draft"` for all five non-English locales for exactly that
  reason; see "Status tracking" below for how that should change.
- For **Hindi and Marathi**, the person building this app reads both
  languages and can do a real review quickly — that's a fast, low-cost
  next step, but it hasn't happened yet and the status field must not claim
  otherwise until it does.
- For **Tamil, Telugu, and Kannada**, the person building this app cannot
  read any of the three scripts at all and has no way to independently
  verify correctness. These three need an actual native/fluent speaker
  before they can honestly move past `machine_draft` — see "Before public
  launch" below. Use the in-app "Report a translation issue" feature
  (Settings → Report a translation issue) to log corrections against exact
  ARB keys as they're found, for any of the 5 languages.
- **"(loanword)"** means: keep the English term transliterated into the
  target script rather than inventing a native translation. This is
  deliberate, not laziness — Indian financial media and every major trading
  app (Zerodha, Groww, Upstox) already use these exact loanwords in their own
  regional-language products. A native translation of "stop-loss" or
  "leverage" would be unfamiliar and *less* clear to the target reader than
  the loanword they already see on every other finance app.

| Concept | EN | Hindi (hi) | Marathi (mr) | Tamil (ta) | Telugu (te) | Kannada (kn) |
|---|---|---|---|---|---|---|
| Portfolio | Portfolio | पोर्टफोलियो (loanword) | पोर्टफोलिओ (loanword) | போர்ட்ஃபோலியோ (loanword) | పోర్ట్‌ఫోలియో (loanword) | ಪೋರ್ಟ್‌ಫೋಲಿಯೋ (loanword) |
| Balance | Balance | बैलेंस (loanword) | शिल्लक | இருப்பு | బ్యాలెన్స్ (loanword) | ಬ್ಯಾಲೆನ್ಸ್ (loanword) |
| Buy | Buy | खरीदें | खरेदी करा | வாங்கு | కొనుగోలు | ಖರೀದಿಸಿ |
| Sell | Sell | बेचें | विका | விற்பனை | అమ్ము | ಮಾರಾಟ ಮಾಡಿ |
| Profit / Loss | Profit / Loss | लाभ / हानि | नफा / तोटा | லாபம் / நஷ்டம் | లాభం / నష్టం | ಲಾಭ / ನಷ್ಟ |
| Unrealized P&L | Unrealized P&L | अवास्तविक लाभ/हानि | अवास्तविक नफा/तोटा | நிலைநிறுத்தப்படாத லாபம்/நஷ்டம் | సాకారం కాని లాభం/నష్టం | ವಾಸ್ತವಿಕವಾಗಿಲ್ಲದ ಲಾಭ/ನಷ್ಟ |
| Stop-loss | Stop-loss | स्टॉप-लॉस (loanword) | स्टॉप-लॉस (loanword) | ஸ்டாப்-லாஸ் (loanword) | స్టాప్-లాస్ (loanword) | ಸ್ಟಾಪ್-ಲಾಸ್ (loanword) |
| Volatility | Volatility | उतार-चढ़ाव | चढ-उतार | ஏற்ற இறக்கம் | హెచ్చుతగ్గులు | ಏರಿಳಿತ |
| Drawdown | Drawdown | ड्रॉडाउन (loanword) | ड्रॉडाउन (loanword) | டிராடவுன் (loanword) | డ్రాడౌన్ (loanword) | ಡ್ರಾಡೌನ್ (loanword) |
| Simulated / paper trading | Simulated / Paper trading | पेपर ट्रेडिंग (आभासी, असली पैसा नहीं) | पेपर ट्रेडिंग (आभासी, खरे पैसे नाहीत) | பேப்பர் டிரேடிங் (மெய்நிகர், உண்மையான பணம் இல்லை) | పేపర్ ట్రేడింగ్ (వర్చువల్, నిజమైన డబ్బు కాదు) | ಪೇಪರ್ ಟ್ರೇಡಿಂಗ್ (ವರ್ಚುವಲ್, ನಿಜವಾದ ಹಣವಲ್ಲ) |
| Leverage | Leverage | लीवरेज (loanword) | लिव्हरेज (loanword) | லீவரேஜ் (loanword) | లివరేజ్ (loanword) | ಲಿವರೇಜ್ (loanword) |
| Order | Order | ऑर्डर (loanword) | ऑर्डर (loanword) | ஆர்டர் (loanword) | ఆర్డర్ (loanword) | ಆರ್ಡರ್ (loanword) |
| Watchlist | Watchlist | वॉचलिस्ट (loanword) | वॉचलिस्ट (loanword) | கண்காணிப்பு பட்டியல் | పరిశీలన జాబితా | ವೀಕ್ಷಣಾ ಪಟ್ಟಿ |
| Alert | Alert | अलर्ट (loanword) | अलर्ट (loanword) | எச்சரிக்கை | హెచ్చరిక | ಎಚ್ಚರಿಕೆ |

## Rules

1. **Never mix a loanword and a native translation for the same concept
   across screens.** If `stop-loss` is a loanword in Hindi on the trade
   sheet, it stays a loanword in the glossary term, the settings screen, and
   every error message — not "स्टॉप-लॉस" in one place and
   "हानि-रोकथाम" in another.
2. **Coin symbols, ticker pairs, and proper nouns are never translated in
   any language:** `BTC`, `ETH`, `BTCUSDT`, `Binance`, `TradingView`,
   `CoinGecko`. Mark these interpolated values with `placeholders` in the
   ARB entry (see `app_en.arb`'s `@` metadata blocks) so `flutter gen-l10n`
   never tries to translate them — they're arguments substituted into the
   message, not translatable text.
3. **Disclaimer and consent text is never approximate.** Every ARB key that
   carries legal/compliance meaning (onboarding consent, the
   "educational simulation, no real money" banner, the AI forecast
   disclaimer, the What-If/DCA "not financial advice" footers) is listed in
   `docs/translation_glossary_disclaimers.md`-equivalent status inside each
   ARB file's `@key` `description` — search any ARB file for
   `"disclaimer": true` in a key's metadata to find every one of these. They
   require native review before public launch **without exception**, even
   though the rest of the machine draft can ship with a visible
   "machine_draft" status while native review is pending.

## Status tracking

Each `app_<locale>.arb` file (except `app_en.arb`, which is the template) has
a top-level `"@@translation_status"` field:

- `"machine_draft"` — not yet reviewed by a native/fluent speaker of that
  language. **Currently true for all five non-English locales** (Hindi,
  Marathi, Tamil, Telugu, Kannada) — none has had an in-context human review
  yet.
- `"native_reviewed"` — a native speaker has read every string in context in
  the app and confirmed it reads naturally and correctly. Nothing has this
  status yet. For Hindi and Marathi, the developer can do this review
  personally; for Tamil/Telugu/Kannada, see "Before public launch" below.

## Before public launch

**Tamil, Telugu, and Kannada must be reviewed by a native speaker before
this app is publicly launched to users who select those languages.** The
`machine_draft` status is honest, not a formality — do not flip it to
`native_reviewed` without an actual review happening. Two practical options,
cheapest first:

1. **Hire a freelance reviewer** for a few hours on a platform like Upwork
   or a local college's language department — reading ~150 short UI strings
   in context (the app itself, not a spreadsheet) takes an afternoon, and
   costs far less than the reputational cost of a visibly broken disclaimer
   or a financial term that reads as nonsense to a native speaker.
2. **Recruit a beta tester from each language community** — someone willing
   to actually use the app for a week and report anything that reads oddly,
   via the in-app "Report a translation issue" option. Slower than a
   dedicated review pass, but free, and surfaces real usage-context issues a
   spreadsheet review might miss.

Either way, track corrections through the in-app report mechanism (writes to
Firestore `translation_reports/{reportId}` — see
`lib/features/settings/translation_report_sheet.dart`) rather than emailed
screenshots, so every correction has the exact ARB key, locale, and screen
context attached.

## Font rendering

Devanagari (Hindi, Marathi), Tamil, Telugu, and Kannada each need glyphs
Flutter's default Material font (Roboto) doesn't include. No font family is
bundled in `pubspec.yaml` for this — not a decision to skip it, but a
constraint of the environment this was built in, which can't fetch or embed
real `.ttf` binaries. Declaring a `fonts:` block that points at asset files
which don't exist on disk would fail `flutter pub get`/every build outright,
which is strictly worse than relying on the fallback below.

**Why it mostly already works anyway:** every Android device sold in India
ships Noto Sans (covering all four of these scripts) in its own system-level
font-fallback chain. When a glyph isn't in the app's font, Android
transparently substitutes from an installed system font — so Hindi/Marathi/
Tamil/Telugu/Kannada text renders correctly today even with zero
font-related code changes, on essentially every real device. This is a
fallback safety net, not a first-class rendering path — line height,
letter-spacing, and weight matching against Roboto aren't guaranteed to look
as polished as an app-bundled font would.

**To bundle Noto Sans properly** (recommended before public launch, not
required for correctness): download the relevant weights from
[Google Fonts](https://fonts.google.com/noto) — `NotoSansDevanagari`,
`NotoSansTamil`, `NotoSansTelugu`, `NotoSansKannada` — into
`assets/fonts/`, then add **one `fonts:` entry per script** (not one merged
family — a `family:`'s font list is weight/style variants of a *single*
typeface, not a place to merge different scripts' glyph sets):

```yaml
flutter:
  fonts:
    - family: NotoSansDevanagari
      fonts:
        - asset: assets/fonts/NotoSansDevanagari-Regular.ttf
    - family: NotoSansTamil
      fonts:
        - asset: assets/fonts/NotoSansTamil-Regular.ttf
    - family: NotoSansTelugu
      fonts:
        - asset: assets/fonts/NotoSansTelugu-Regular.ttf
    - family: NotoSansKannada
      fonts:
        - asset: assets/fonts/NotoSansKannada-Regular.ttf
```

Then wire them as **fallbacks**, not replacements, on the app's `ThemeData`
so Roboto still renders Latin/English text (Noto Sans's Latin glyphs look
different from Roboto's) and only the target-script glyphs fall through:

```dart
ThemeData(
  fontFamilyFallback: const [
    'NotoSansDevanagari',
    'NotoSansTamil',
    'NotoSansTelugu',
    'NotoSansKannada',
  ],
  // ...existing theme config
)
```

## Testing across locales

`test/features/onboarding/language_onboarding_screen_test.dart` pumps the
first-run language picker — the one screen guaranteed to be seen in every
locale before a user has even chosen one — at a small phone width (320dp)
in all 6 languages and asserts no layout-overflow exception and that every
language's own-script name actually renders. This is the highest-value
single screen to cover since it doesn't require mocking Firebase, unlike
most other screens in this app; extending the same pattern to Settings,
sign-in, and the ticker screen is recommended follow-up work once a
Firebase-auth test-mocking setup exists for widget tests (see the "Known
sandbox limitation" note in the project's session history — no such helper
exists yet).
