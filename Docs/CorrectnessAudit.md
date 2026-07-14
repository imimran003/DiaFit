# Food, nutrition, and visual correctness audit

Date: 2026-07-15

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
