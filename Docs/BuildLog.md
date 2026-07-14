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
