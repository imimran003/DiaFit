# Startup and home hierarchy cleanup

Date: 2026-07-16

## Root cause

`DiafitApp` used `SampleDiary.days` as the seed for every app configuration. On a fresh install, `DiaryStore` persisted those three preview days to the live Application Support archive. The home screen was therefore rendering stored demo content, not merely a visual placeholder. The same data supplied the apparent calorie and carbohydrate totals.

The sample fixture contained `Yogurt, berries & seeds`, `Miso salmon plate`, sample agent messages, a glucose checkpoint and sample artwork. No production-only dependency container or fixture JSON was involved.

## Environment policy

- Normal development and production runtime use `RuntimeDiaryDefaults`, which contains one empty current day and no messages, meals, glucose readings, images or nutrition values.
- UI tests start from the same empty runtime shape unless a test explicitly opts into its isolated persistent archive.
- SwiftUI previews use `PreviewDiaryFixtures` directly.
- There is no implicit demo-mode runtime check.

The strings `Yogurt, berries & seeds` and `Miso salmon plate` remain in the dedicated preview fixture. `Miso salmon plate` also remains as an existing explicit food-recognition response when a user asks for salmon and rice; this task did not change food recognition. Neither path inserts a meal at startup.

## Existing-data preservation

Startup never deletes records by title. Older builds did not persist origin metadata, so a title-based migration could erase a legitimate user meal.

`DiaryStartupPolicy` removes an old archive only when its complete structural fingerprint matches the shipped three-day preview fixture: exactly three consecutive days, unchanged goals, unchanged message sequence, unchanged meal fields, unchanged agent copy and unchanged checkpoints. Runtime UUIDs and timestamps are intentionally ignored. Any extra meal, glucose reading, message or edit makes the archive ineligible, and the entire archive is preserved.

If an old preview archive has been mixed with user data, automatic cleanup is intentionally skipped. A future migration can become more selective only after records carry an explicit origin field.

Unreadable archives are never overwritten. A persistence error keeps the original file untouched and disables mutations until retry succeeds.

## Nutrition hierarchy

The selected day exposes a single aggregation path over confirmed `Day.meals`:

- `totalEnergy`
- `totalCarbs`
- `totalProtein`

The header reads these model totals; no metric is calculated in SwiftUI. Add, edit, delete, day switching and archive restoration therefore share the same source of truth and cannot create a second aggregation pass.

Legacy meals store protein as an integer. Structured meal-analysis records preserve unavailable protein as `nil`; the header sums known values and exposes the partial state in its accessibility description rather than inventing protein from calories or silently changing the saved record.

## Home design changes

- Replaced two independent progress capsules with one aligned three-column summary for Calories, Carbohydrates and Protein.
- Added an accessibility-size row layout so values do not clip or wrap unpredictably.
- Removed the instructional “Swipe for days” label and the always-visible suggestion chip carousel.
- Added an intentional empty state with one primary `Add food` action and one quiet camera action.
- Hid the meal-atlas affordance when no meals exist.
- Simplified the composer to one restrained surface and removed its heavy glass/shadow treatment.
- Added semantic type styles and adaptive paper, ink, rule and mist colors; normal dark mode is no longer forcibly disabled.
- Made the existing glucose summary reflow vertically at accessibility sizes.

The Add food action focuses the existing text composer. Camera/photo input remains available through both the empty state and composer. No food is preselected or inserted.

## Verification

Deterministic unit/integration suite:

```sh
xcodebuild -project Diafit.xcodeproj -scheme Diafit \
  -destination 'platform=iOS Simulator,id=CBD8A933-CE89-44B2-85E8-8E3D4F22F038' \
  -derivedDataPath /tmp/DiafitDesignDerived \
  -only-testing:DiafitTests test
```

Focused startup and top-summary UI checks:

```sh
xcodebuild -project Diafit.xcodeproj -scheme Diafit \
  -destination 'platform=iOS Simulator,id=CBD8A933-CE89-44B2-85E8-8E3D4F22F038' \
  -derivedDataPath /tmp/DiafitDesignDerived \
  -only-testing:DiafitUITests/DiafitUITests/testFreshLaunchIsEmptyAndShowsThreeMetricSummary \
  -only-testing:DiafitUITests/DiafitUITests/testAddingAndDeletingMealUpdatesAllTotalsAndRestoresEmptyState \
  test
```

Final results:

- Deterministic unit/integration suite: 64 tests passed, 0 failures.
- Focused startup and nutrition-summary UI suite: 2 tests passed, 0 failures.
- Persistence archive edit/delete/reload coverage passed in the deterministic suite.
- A separate process-relaunch UI run was interrupted after the iOS 26.5 XCTest runner stalled while locating the pre-existing food-confirmation control; the repository-level persistence test remains green.

Simulator visual verification used the available iOS 26.5 devices: iPhone 17e, iPhone 17 Pro and iPhone 17 Pro Max. The configured Xcode installation does not contain an iPhone 15 Pro simulator. Light, dark and accessibility-extra-extra-extra-large content sizes were captured on iPhone 17 Pro.

Screenshot evidence is in `Docs/DesignQA`:

- `before-runtime-seed.png`
- `after-empty-state.png`
- `after-empty-state-dark.png`
- `after-empty-state-largest-type.png`
- `after-empty-state-small.png`
- `after-empty-state-large.png`

## Known limitation

The iOS 26.5 simulator accessibility runtime intermittently reports a legacy `Button` versus modern `PopUpButton` automation-type mismatch for pre-existing clarification choice chips. This affects an unrelated food-recognition UI test; it does not affect the new startup/summary tests or the visible choice controls. The task deliberately leaves food-recognition behavior unchanged.
