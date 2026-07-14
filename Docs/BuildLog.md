# Build log

## 2026-07-14 — foundation

- Initialized the repository.
- Established the product intent: conversation first, meal atlas second, nutrition details only when helpful.
- Chose native SwiftUI and no dependencies to keep the interaction model inspectable and portable.
- Added a local sample diary with intentionally illustrative nutrition and glucose values.
- Attempted to produce custom studio food imagery using the available image generator; the service returned HTTP 403. The prototype therefore uses a structured, replaceable local artwork system. Production imagery remains an explicit service boundary.
