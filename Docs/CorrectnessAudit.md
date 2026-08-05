# Food, nutrition, and visual correctness audit

Date: 2026-07-15

## 2026-08-04 — Meal-period reachability and AI inventory adjudication

The `WHEN` control no longer depends on a horizontal gesture nested inside the
daily conversation. All seven meal periods are presented in a stable two-row,
four-column grid, so Breakfast through Dinner remain visible, selectable and
accessible on a physical-phone-sized viewport. Compact visual labels do not
change the persisted meal-period values or their full VoiceOver names.

Photo recognition now treats a small multi-label result as incomplete when it
still contains generic dishes, garnish-sized foods, unresolved terms or weak
component confidence. The structured backend performs an independent recovery
pass over the full image. A materially stronger recovery inventory replaces
the weak hypothesis instead of blindly unioning earlier false labels into the
meal. If all AI passes remain sparse, the app preserves the photo and exposes
retry/manual recovery; it does not enable confirmation with misleading totals.
A specific three- or four-food inventory remains editable even when only a
serving or recipe assumption lowers aggregate confidence.

Verification completed:

- 138 deterministic iOS unit/integration tests passed with 0 failures.
- 22 UI tests passed with 0 failures on the iPhone 15 Pro simulator (iOS
  26.5), including direct selection of Evening snack and Dinner without a
  horizontal swipe.
- Backend tests passed (4/4), both JavaScript syntax checks passed, and the
  fixture-contract evaluator completed.
- A live Gemini smoke test using a non-private bundled food asset returned a
  schema-valid three-component inventory through `/v1/meal-parse`; the API key
  remained in the ignored backend environment file.
- The Release simulator build succeeded, then the verified Debug build was
  installed and launched successfully on the iPhone 15 Pro simulator.

Photo interpretation remains probabilistic. Exact portion, hidden oil, sauces
and recipe composition still require review, and production distribution still
requires deployed HTTPS, account authentication, managed secrets, provider
monitoring, nutrition-source licensing and explicit photo-processing consent.

## 2026-08-05 — Partial on-device label could leak into photo review

The reported sprouts-and-eggs screenshot exposed a gap after the structured
provider had not produced a usable inventory: the private Vision classifier
returned one canonical `peanut` label, and the local nutrition path returned an
incomplete but non-empty result. The orchestrator only withheld on-device
results when local nutrition happened to be complete, so the review card could
show a plausible six-kcal peanut row while the rest of the plate was missing.
That was a routing/completeness defect, not evidence that the photo contained
only a peanut.

The image-only fallback now has a final invariant: any on-device candidate is
withheld unless structured vision has already cleared the full inventory and
nutrition gates. The result keeps the prepared photo, exposes a single retry
or manual food-name recovery path, and cannot be confirmed. The review card
also masks component rows and nutrient totals when a stale draft is marked for
inventory recovery, preventing old drafts from presenting the same misleading
partial meal.

Verification added:

- deterministic regression for an unconfigured backend plus a single `peanut`
  candidate (no detected items, no totals, free-text recovery required);
- iOS app and test bundle compile with the Xcode Default toolchain;
- backend tests remain 4/4 and the opt-in bundled-image Gemini smoke returned
  three schema-valid food components.

The live backend is still an explicit development dependency: configure
`DIAFIT_BACKEND_URL` and `DIAFIT_BACKEND_ACCESS_TOKEN` in the user-only Xcode
scheme (or use the stored debug Keychain configuration). Without it, the app
now fails safely instead of claiming to have identified a photo.

The debug configuration store now verifies its Keychain write and uses a
complete-file-protected app-container fallback only when the simulator's
Keychain service is unavailable. This keeps the endpoint available after a
Home-screen relaunch during device testing without moving provider credentials
into the app bundle or any release configuration.

## 2026-08-04 — End-to-end QA closure

The production-style QA pass covered the food and nutrition pipeline, typed
clarifications, photo recovery, meal-period selection, glucose logging,
persistence, diary/day navigation, profile/settings, and critical destructive
actions. The following defects were fixed during the pass:

- Replaced the daily conversation's finite `LazyVStack` with a regular stack to
  prevent a SwiftUI placement-cache/CPU loop when deleting a meal during a
  context-menu transition.
- Normalised mass-specific shorthand before the generic quantity cap, so
  `500 gm` resolves to 500 g and `1 kg` resolves to 1,000 g and scales
  nutrition correctly.
- Added data-driven typed clarification questions for chai, tea, paratha,
  rice, sprouts, cooking fat, coffee, sweetened drinks, and whey instead of
  flattening those questions into non-interactive text.
- Preserved known components when an offline compound note contains an
  unresolved term; the unresolved phrase remains explicit and confirmation is
  blocked until it is clarified.
- Added whole-wheat bread and milk-tea canonical aliases and mapped whole-wheat
  flatbread to roti so compound notes retain all visible foods.
- Added stable render identity for draft-to-saved meal transitions, preventing
  the review editor from remaining onscreen after confirmation or an edited
  serving.
- Updated sparse-photo correction copy and made an explicit manual correction
  raise confidence so the user can recover safely without bypassing nutrition
  validation.

Verification completed:

- 136 deterministic XCTest cases passed (0 failures).
- 21 UI tests passed on the iPhone 15 Pro simulator (iOS 26.5), including
  fresh empty state, food entry, quantity editing, compound meals, whey,
  glucose flows, meal periods, photo recovery, persistence, diary navigation,
  and meal deletion.
- Backend Node tests passed (4/4), syntax/contract checks passed, and the
  fixture evaluator completed.
- Release simulator build succeeded and the app installed/launched on the
  iPhone 15 Pro simulator.

The deterministic evaluator is parser-only: food detection and compound
decomposition were 83.6% over 165 fixtures. Its 40.6% blank/fallback rate is
inflated by intentionally unresolved and invalid cases; it does not measure
nutrition-provider resolution. A live photo/provider call was not made because
the supplied photos are private and external upload requires explicit consent.
Real HealthKit data and physical-device signing were also outside this local
simulator pass. Production release still requires authenticated provider
credentials, privacy/consent review, real-device QA, and a nutrition-provider
integration run.

## Observed failures and root causes

`chai and paratha` was not an image-generation race or a cache collision. The legacy conversational path sent every unmatched note through `NutritionService.estimate(for:)`, whose generic fallback assigned a full meal's nutrients and the `.bowl` bundled editorial image. The bowl asset could read as a salad, despite neither component being a salad.

`black coffee` followed that same unmatched fallback and inherited its 470 kcal total. No component-specific food record or plausibility gate sat between the fallback and the diary.

## Corrected flow

`DayThreadView` now calls `NutritionService.resolve(note:at:)`. Familiar sample meals may save directly; all other text passes through `LocalMealAnalysisEngine`, canonical matching, portion scaling, and `NutritionValidationService`. Ambiguous or incomplete meals create an editable review and do not update daily totals until confirmation.

The local catalog separates canonical food, preparation variation, serving, confidence, and provenance. In particular, black coffee is an explicit unsweetened beverage record; plain coffee, chai, tea, and paratha request only the high-impact clarification needed to distinguish their variants.

No arbitrary meal is mapped to a photographic food asset. Analysed meals use `.neutral`, a component-labelled graphic, until a future verified visual service is connected.

## Nutrition guardrails

`NutritionValidationService` preserves provider/raw values in its report but only exposes safe values when all checks pass. It rejects non-finite or negative nutrients, unusable quantities/weights, empty results, material energy-versus-macronutrient mismatches (4/4/9 kcal/g), and implausible plain-beverage energy. Quantities are constrained to 0.1...20 servings and weights to 1...2,000 g. Incomplete components or failed validation require review and are excluded from saved totals.

Development diagnostics log stable input fingerprints, canonical IDs, validation state, and visual request/cache IDs. They do not log source images, credentials, or raw personal meal text.

## Deterministic visual identity

`MealVisualIdentity` stores meal/request IDs, canonical food IDs, preparation variations, composition, source, style version, timestamp, and a SHA-256 derived cache key. `MealVisualRequestLedger` rejects stale, cross-meal, cancelled, and deleted task results. Future generated imagery must use this identity and its structured prompt rather than conversational display text.

## Regression coverage

`DiafitTests/FoodAnalysisTests.swift` covers black coffee, chai/paratha, beverage variants, ambiguous notes, Indian multi-component fixtures, serving scaling, guard rejection, serialization, daily recalculation, deterministic visual keys, and stale/deleted image requests. The pre-fix regressions failed against the former generic 470-kcal `.bowl` fallback; the focused suite now contains 19 passing tests.

`DiafitUITests/DiafitUITests.swift` covers black-coffee review, chai/paratha clarification and confirmation, review rendering, quick logging, the atlas transition, and the photo-review safety state. Simulator automation dismisses the keyboard before tapping the composer send control because the iOS 26.5 runtime reports an incorrect bottom-safe-area button frame while the keyboard is open.

## Manual matrix for production integration

Before replacing fixture services, test fresh/existing diaries, empty/populated visual cache, offline and provider failures, cancelled/backgrounded/terminated requests, rapid multi-meal input, prior-day edits, light/dark appearance, Dynamic Type, reduced motion/transparency, and small/large phones. Verify that failed nutrition or visual requests retain the editable draft and never mutate daily totals or another meal.

## Remaining production work

The app intentionally has no authenticated nutrition or image-generation provider configured. Nutrition entries are curated local estimates, not clinical guidance. A production backend must supply authoritative provenance, consented history access, secure key handling, visual-match validation, explicit wrong-image recovery, telemetry review, accessibility/device QA, and clinical/regulatory review.
