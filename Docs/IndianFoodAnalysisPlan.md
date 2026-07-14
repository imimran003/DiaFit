# Indian food photo logging — integration plan

_Updated 14 July 2026. This document records the intended shape as well as the delivery sequence so the work can continue without replacing the existing diary._

## Baseline audit

Diafit is a native SwiftUI application with an intentionally small architecture:

- `DiaryStore` owns the in-memory daily conversation and provides the natural insertion point for saved meals.
- `DayThreadView` owns the composer, optimistic conversation pacing, and scroll continuity. Camera/photo entry belongs beside the existing composer, not in a second logging screen.
- `Meal`, `MealMomentView`, `FoodArtwork`, and `MealAtlasView` already provide one food identity across the conversation and atlas through matched geometry.
- `LocalNutritionService` is a deterministic text-demo seam, not a production nutrition source. It will remain available for manual/offline fallback but will no longer be the only path.
- The project currently has UI smoke tests, no persistence framework, no networking layer, no media retention, and no runtime provider credentials. The data model and services must therefore make uncertainty and provenance first-class before any provider is connected.

The existing uncommitted material-system work is part of the current visual baseline. It is deliberately preserved. A focused baseline commit is desirable before the next milestone, but the current execution environment cannot write Git metadata; source work continues independently and will be committed once that access is available.

## Product decisions and safeguards

1. A photograph creates an **unconfirmed draft**. It never silently writes meal history.
2. A recognition response is a hypothesis, not evidence. The review card separates visible, inferred, and possible ingredients and exposes alternatives, assumptions, confidence, serving size, and source.
3. Nutrition fields are optional. `Not available` is rendered when a provider cannot support a value; the client does not manufacture glycaemic data.
4. Glycaemic load is calculated only when both available carbohydrate and a sourced glycaemic index exist: `GI × available carbohydrate (g) / 100`.
5. The app gives neutral context only. It does not diagnose, dose insulin, alter medication, or infer health status from a photo.
6. Original photos are transient by default. The capture/import flow removes metadata during preparation, tells the member that a configured service will process the image, and does not persist the original unless an explicit retention option is introduced.
7. Editorial food art is decorative and remains distinct from `originalPhoto` in the analysis model. It is cache-keyed by canonical food, variation, and art direction version when a server implementation is configured.

## Incremental module map

| Requirement | Existing extension point | New module |
| --- | --- | --- |
| Typed analysis and confidence | `Meal`, `ThreadItem`, `DiaryStore` | `Models/MealAnalysisModels.swift` |
| Indian aliases and canonical IDs | `LocalNutritionService` | `Resources/IndianFoodCatalog.json`, `IndianFoodCatalogService` |
| Nutrition and glycaemic provenance | Existing service seam | `FoodAnalysisServices.swift` |
| Camera / library intake | `Composer` in `DayThreadView` | `PhotoMealInput.swift`, `ImagePreparationService` |
| Draft review and corrections | Thread meal card language | `MealAnalysisReviewCard.swift` |
| Explicit confirm, edit, delete | `DiaryStore` | mutation methods and contextual meal controls |
| Secure network provider | no existing code | protocol-first client plus a separately configured backend contract |
| Test fixtures and evaluation | existing XCTest target | deterministic analysis fixtures and service tests |

## Provider and backend boundary

The iOS app will only know typed protocol interfaces. A configured server is responsible for authentication, authorization, secret storage, image/MIME/size validation, schema validation, rate limiting, timeouts, observability without raw photo logging, temporary-object cleanup, retention controls, and provider selection. No API credential is stored in the app.

The app retains a fully usable manual and offline path: typed note recognition, food search, recent/saved foods, editable serving values, and draft retries. If no recognition endpoint is configured, the UI says that photo analysis is unavailable and invites a lightweight dish description; it does not fabricate an image result.

## Delivery order

1. Add models, catalog, normalization, nutrition/portion/glycaemic calculation, and fixtures.
2. Add draft/review/confirmation flows plus photo-library/camera intake and local metadata-stripping compression.
3. Connect the conversation tool states, saved-meal editing/deletion, and the existing atlas identity.
4. Add the backend API contract and development fixture provider, then document privacy/security and provider configuration.
5. Exercise unit/UI flows and record simulator checks when simulator access is available. Accessibility, reduced motion, dark appearance, small screen, slow/offline network, and transition-frame checks remain mandatory release gates.

## Known limitations until a configured backend is supplied

- No photograph can reliably reveal recipe, oil/ghee, sugar, exact weight, or nutrients. The client deliberately asks only high-impact questions after recognition.
- The bundled catalog supports canonical matching and offline estimates with transparent provenance. It is not a replacement for an authenticated authoritative database.
- The current store is in-memory. Draft and confirmed meal persistence will be added behind the same repository boundary; a production deployment must choose encrypted local storage and account-scoped server retention.
