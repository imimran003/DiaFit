# Glucose tracking

Diafit treats glucose as a private, informational log rather than a clinical dashboard. The feature is local-first and deliberately keeps the home screen quiet: only the latest fasting and post-meal readings are surfaced, with history behind progressive disclosure.

## Architecture

`GlucoseReading` is a strongly typed, Codable record stored inside the existing `Day`/`ThreadItem` archive. It retains the entered Decimal value and unit for auditability, plus a normalized mg/dL value for summaries and unit conversion. `GlucoseReadingSource` is already modeled for manual, imported and future HealthKit readings.

The service boundaries are:

- `GlucoseReadingRepository` — save, edit, delete and meal-relationship checks through `DiaryStore`.
- `GlucoseHistoryService` — local-day filtering, type filters and summary statistics.
- `GlucoseValidationService` — finite/positive values, valid units, non-negative post-meal offsets and broad technical-range confirmation without diagnosis.
- `GlucoseNaturalLanguageParser` — draft extraction for FBS, PPBS/post-meal, pre-meal, bedtime and other readings. A glucose marker is required so meal quantities such as “2 eggs” never become glucose entries.
- `GlucoseCSVExporter` — export-ready fields without exposing internal IDs.

SwiftUI talks to these boundaries through `GlucoseEntrySheet`, `GlucoseSummaryStrip` and `GlucoseHistoryView`; persistence is never accessed directly by a view.

## Persistence and migration

The archive schema is now version 2. Existing meals, saved foods, images and legacy `GlucoseCheckpoint` items remain decodable. Loading a schema-1 archive upgrades it in memory and persists the next write using schema 2. A missing or deleted related meal is handled as a recoverable save error.

## Interaction

The home summary shows the latest FBS and post-meal values, unit and measured time, plus a single `Log glucose` action. The compact sheet prioritizes Fasting and Post-meal, then reveals timing, meal association, fasting duration and notes contextually. Post-meal readings can be attached to a meal without covering its food image; expanded meal details render a compact glucose row.

Natural-language entries such as `FBS 96`, `PPBS 142`, and `7.2 mmol/L two hours after dinner` open the same editable confirmation sheet. An omitted unit or post-meal timing is visible as a confirmation requirement; no diagnosis or treatment recommendation is generated.

## Privacy and safety

Glucose values are sensitive health information. The feature stores only the fields needed for logging, does not add analytics logging, does not transmit values, and does not add HealthKit entitlements. Values outside a broad technical range are preserved but require a calm “check the number and unit” confirmation. This is tracking and informational only; product/legal review is still required before release, including App Store privacy disclosures and any future export or HealthKit integration.

## Verification

Deterministic tests cover conversion and round trips, natural-language extraction, ordinary-food false positives, validation, repository persistence/edit/delete, history summaries and schema migration. Build with:

```sh
xcodebuild -project Diafit.xcodeproj -scheme Diafit \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/DiafitBuild CODE_SIGNING_ALLOWED=NO build
```

Run the focused tests on an available simulator with the `Diafit` scheme. The simulator service can fail independently of compilation; if CoreSimulatorService is unavailable, the build remains verifiable with `build-for-testing` and the simulator run should be retried after the service recovers.
