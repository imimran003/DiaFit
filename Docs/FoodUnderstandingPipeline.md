# Food understanding pipeline

## Baseline reproduction

The July 2026 baseline was built and launched on the iPhone 17 Pro simulator
before this change set. The local trace showed:

| Input | Baseline canonical matches | Baseline nutrition | Baseline visual |
| --- | --- | --- | --- |
| `I had sprouts with 3 boiled eggs` | `boiled-egg` only, quantity 3 | unavailable: the existing egg record had no nutrition and `sprouts` had no record | no request; neutral placeholder after confirmation |
| `whey protein shake` | no items | unavailable | no request; unknown-food review state |

The old path was an alias-only scan. It had no spans, component model, unit-aware
quantity parser, supplement profile, or request created before confirmation.

## Stages

`FoodUnderstandingPipeline` runs synchronously and independently of any remote
service, so the core flow remains testable offline:

1. Unicode/case input normalisation.
2. Tokenisation that preserves decimal quantities.
3. Longest-span alias matching against the curated catalog.
4. Non-overlapping compound-meal decomposition; connector words are never
   consumed, so `with`, `and`, `plus`, `along with`, and comma-separated lists
   can contain multiple foods.
5. Quantity and unit extraction (digits, words, fractions, pair/couple, bowls,
   eggs, scoops, cups, glasses, pieces, slices, tablespoons, teaspoons, grams).
6. Preparation and modifier extraction.
7. Canonical normalisation and confidence scoring.
8. Supplement profile creation, including scoop grams, flavour, and water/milk
   base.
9. Catalog nutrition lookup, recipe/base calculation, category validation,
   clarification generation, structured visual request creation, and review
   persistence.

The parsed result retains the matched alias, confidence score, preparation,
modifiers, and supplement profile. It deliberately does not persist the entire
raw note. DEBUG diagnostics may log normalized food text and stage outputs for
local troubleshooting; they never include photos, credentials, or image payloads
and are compiled out of release builds.

## Curated nutrition and fallback policy

The bundled catalog now contains plain egg preparations, generic/specific
sprouts, milk, banana, oats, generic whey, whey isolate, whey concentrate, and
a ready-to-drink protein drink. Eggs use a standard 50 g large whole egg unless
the user changes the editable serving. Boiled egg records have no oil.

Whey is modelled as a `SupplementProductProfile`, not a recipe. Resolution order
is designed as:

1. scanned or user-confirmed label;
2. saved branded product;
3. exact packaged match;
4. generic isolate;
5. generic concentrate;
6. generic whey fallback;
7. concise clarification.

The local build currently implements steps 4–7. It exposes the generic source
and keeps the values editable. Water is a zero-calorie base; milk is calculated
into the supplement item using the central milk record and is not double counted
as a second component.

Nutrition is never silently blank when the catalog has a generic curated record.
The validator still withholds values for unsupported data, invalid quantities or
weights, macro-energy contradictions, implausible plain beverages, implausible
egg-part energy, and implausible whey protein-per-scoop values.

## Visual request contract

Every non-empty parsed meal creates a `MealVisualRequest` with:

- stable meal/analysis ID;
- request ID;
- canonical component IDs;
- quantity/preparation signature;
- style version;
- structured prompt;
- SHA-256 cache key;
- state and recoverable failure reason.

The prompt derives from components, not prose. For sprouts plus three boiled
eggs it requires mixed sprouts and exactly three peeled boiled eggs, excludes
extra eggs and unrequested salad ingredients, and prevents unrelated dishes. A
whey prompt carries water/milk base and excludes fruit unless it was parsed.

No remote image credential is configured in the local app. A successful parsed
request therefore renders the persisted deterministic component composition
instead of a blank region or an unrelated bundled photo. The component view
visually distinguishes sprouts, exact egg count (up to three displayed), and a
whey shaker. The review card exposes a retry control and clear unavailable copy
if a provider is later attached and fails. `MealVisualRequestLedger` rejects
stale, cross-meal, replacement, and deleted-meal responses; editing re-registers
the new request and deletion cancels its ledger entry.

## Verification

Run all deterministic unit/integration coverage:

```sh
xcodebuild -quiet -project Diafit.xcodeproj -scheme DiafitUnitTests \
  -destination 'platform=iOS Simulator,id=<device-id>' test
```

Run all UI flows:

```sh
xcodebuild -quiet -project Diafit.xcodeproj -scheme Diafit \
  -destination 'platform=iOS Simulator,id=<device-id>' \
  -only-testing:DiafitUITests test
```

The manual matrix to exercise before production provider rollout includes fresh
install, history/default product, empty/populated cache, provider available and
unavailable, slow generation, background/termination, rapid multiple meals,
edit/delete during generation, offline entry, light/dark mode, Dynamic Type,
reduced motion, and compact/large iPhones.

## Production follow-up

The app has a provider-independent core and safe fallback, but it does not ship
a live nutrition database, barcode scanner, account-level saved product store,
or authenticated image provider. Those integrations must use the existing
product and visual request contracts, preserve the validation gate, and be
tested against real label provenance before medical or dosing decisions are ever
made from the diary.
