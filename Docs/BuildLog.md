# Build log

## 2026-07-14 — foundation

- Initialized the repository.
- Established the product intent: conversation first, meal atlas second, nutrition details only when helpful.
- Chose native SwiftUI and no dependencies to keep the interaction model inspectable and portable.
- Added a local sample diary with intentionally illustrative nutrition and glucose values.
- Attempted to produce custom studio food imagery using the available image generator; the service returned HTTP 403. The prototype therefore uses a structured, replaceable local artwork system. Production imagery remains an explicit service boundary.
- Xcode’s automatic Metal toolchain handoff was unavailable despite the component being installed. The target compiles the same source in a small explicit build phase, using the installed toolchain and a derived module cache; this keeps `Daylight.metal` live rather than treating it as decorative source.

## 2026-07-14 — Simulator QA

- Built and installed Diafit on an iPhone 17 Pro simulator (iOS 26.5).
- Added UI smoke coverage for the shared-geometry meal atlas and for the conversational quick-log flow. Both passed in the live simulator.
- Captured and reviewed the atlas and logged-pasta frames from the retained test attachments. The atlas is a uniform, image-first grid and the logged meal reads as a continuous conversation moment.
- Retried the studio-food image generator after the environment upgrade; it still returned HTTP 403. The deterministic food-art fallback remains in use, with the external image integration boundary documented in `Docs/Intent.md`.

## 2026-07-14 — Freeform logging correction

- Replaced the demo-only `Market salad bowl` fallback. Saved prompts still resolve to their familiar recipes, but every other food note now preserves the member’s own description and is transparently marked as an estimate.

## 2026-07-14 — Material system overhaul

- Generated a five-image coherent studio-food series (pasta, yogurt and berries, salmon, eggs on rye, lentil bowl) and converted the chroma-key source into alpha PNG assets with a local Swift utility after the prescribed helper was unavailable.
- Replaced the vector food scenes with those image cutouts on solid pigment stages, hand-drawn paper fibers, and a deliberately small Metal light pass.
- Removed the generic outer card from meal moments, demoted agent bubbles to an editorial rule treatment, and made the atlas reveal a custom masked transition on top of matched food geometry.

## 2026-07-15 — Indian meal analysis foundation

- Audited the existing diary and documented an incremental integration plan before adding new systems. The conversation thread, matched atlas identity, and freeform entry remain intact.
- Added strongly typed, Codable analysis models with optional nutrients, confidence, source/version provenance, alternatives, portions, visible/inferred/possible ingredients, assumptions, warnings, bounding regions, clarification questions, and explicit draft state.
- Added an extensible Indian-food catalog with canonical IDs and aliases across the requested food groups. Bundled values are clearly identified as low-confidence recipe estimates; incomplete values and all unsupported glycaemic values stay unavailable.
- Added a camera/photo-library surface, EXIF-stripping image normalization, in-thread analysis review, correction/recalculation, explicit confirmation, later refinement, and destructive-delete confirmation. The default application does not upload or retain the original photo.
- Added a small server-side contract with strict request/response validation, rate limiting, timeout, redacted logging, health endpoint, `.env.example`, and transparent fixture mode. It has no embedded credentials and does not claim image recognition accuracy.
- Added unit coverage for aliases, group coverage, multi-component parsing, portions, nutrient scaling, glycaemic-load preconditions, unavailable nutrition, and draft-to-confirmed logging. The app and unit-test bundle compile; live simulator test execution remains unavailable in this environment.

## 2026-07-15 — Live Simulator launch check

- Rebuilt, installed, and launched the current Debug app on the booted iPhone 17 Pro simulator (iOS 26.5).
- Captured and inspected the day-thread launch frame. This exposed a loose-PNG name lookup issue: the food stage rendered but its alpha cutout did not.
- Replaced the ambiguous SwiftUI name lookup with a cached explicit bundle-image lookup, rebuilt, reinstalled, and captured a second frame. The salmon studio cutout, conversation hierarchy, nutrition card, and camera-enabled composer all render correctly.

## 2026-07-15 — Food-pipeline correctness repair

- Reproduced the reported `black coffee` and `chai and paratha` failures. Both originated in the legacy generic free-text fallback: it supplied a 470 kcal meal and the unrelated `.bowl` editorial asset.
- Replaced that path with canonical component parsing, explicit beverage/preparation variations, an editable review state, central nutrition validation, and a truthful neutral component visual for free-text meals.
- Added deterministic meal visual identities and a request ledger that rejects stale, cross-meal, cancelled, and deleted async results.
- Added 19 focused analysis/validation/visual tests and simulator UI regressions for black coffee and chai/paratha. XCTest needed a static-rendering test mode because the production Metal artwork intentionally updates at display cadence; the live artwork is unchanged.

## 2026-07-15 — Compound meals and supplements

- Reproduced `sprouts with 3 boiled eggs` and `whey protein shake` before changing implementation. The old alias-only scan missed sprouts and whey, while boiled egg had no curated nutrition and the local build never created a meal visual request.
- Added a staged, provider-independent parser with longest-span alias matching, non-overlapping compound decomposition, word/decimal/fraction quantity parsing, preparation and modifier extraction, confidence scoring, and data-driven egg, sprout, and supplement catalog records.
- Added editable generic whey profiles with scoop grams, flavour, milk/water base, and a safe nutrition fallback. Water adds no calories; milk is calculated once into the shake profile.
- Added category-aware egg and whey validation plus structured, quantity-sensitive visual requests. Parsed meals render a persistent deterministic component composition when no authenticated generator is configured, rather than a blank or unrelated image.
- Added a full regression matrix and iPhone 17 Pro simulator flows for sprouts/three eggs and one-scoop whey/water. The first UI attempt exposed two test automation quirks (offscreen field focus and simulator text replacement); the final flow uses the explicit serving-unit editor and passes.

## 2026-07-15 — Runtime verification resumed

- CoreSimulatorService recovered after relaunching Simulator.app. Diafit was
  installed and launched on the booted iPhone 17 Pro (iOS 26.5).
- The concrete `DiafitUnitTests` scheme executed all 41 tests with 0 failures.
- Runtime verification caught two defects that compilation could not: the
  `boiled-egg` catalog record was incorrectly grouped under breakfast/snack,
  and the edit-visual regression expected nutrition to change before explicit
  confirmation. The record was moved into the egg category and the test now
  verifies visual-request advancement while nutrition remains unchanged.
- The focused UI flows for sprouts with three boiled eggs and one-scoop whey
  with water both passed on the iPhone 17 Pro simulator. A full nine-test UI
  invocation became unstable during repeated relaunches and was stopped; it
  is not reported as a pass.
