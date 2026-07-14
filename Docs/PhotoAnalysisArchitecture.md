# Photo analysis architecture, privacy, and data decisions

## What is working in this repository

The current iOS build supports a complete **local review path**:

1. The member opens the camera or photo library from the conversation composer.
2. The app validates, orientation-normalizes, resizes (maximum 2048 px), recompresses (maximum 2 MB), and creates a fresh JPEG representation. That representation deliberately drops EXIF metadata, including location metadata.
3. In this build the prepared photo remains in memory for the review session. The member supplies a short dish description; the local catalog creates a component-based, unconfirmed draft.
4. The draft appears inside the day thread, distinguishes uncertainty, exposes quantities and serving units, asks at most two high-impact questions, and recalculates supported values after correction.
5. Only an explicit confirmation replaces the draft with a logged meal. The resulting meal is immediately available to the existing meal atlas. A confirmed analysis can be reopened for refinement or deleted through an explicit destructive confirmation.

No photo is uploaded by the default app configuration. The in-thread card says so plainly. The original photo is not kept after confirmation; the existing editorial food image remains a decorative timeline treatment, never evidence of the meal or portion.

## Models and services

`MealAnalysisModels.swift` establishes the shared contract:

- `MealAnalysisResult`, `DetectedFoodItem`, `NutritionValues`, `GlycaemicInformation`, and `ClarificationQuestion` are Codable and validate the shape expected from a backend.
- Nutrient fields are optional. `nil` means unavailable, not zero.
- Every nutrition result has `NutritionProvenance`; estimates are labelled as estimates.
- Glycaemic load is only calculated by `GI × available carbohydrate / 100` when both a sourced GI and available carbohydrate are present. The bundled catalog does not claim GI values, so it shows `Not available`.
- An unconfirmed `MealAnalysisDraft` is structurally separate from a confirmed `Meal`.

`FoodAnalysisServices.swift` provides protocol seams for recognition, normalization, nutrition lookup, glycaemic data, portions, draft storage, confirmed logging, image preparation, generated editorial imagery, and conversational tools. Views do not know about provider SDKs or API credentials.

The local catalog is `IndianFoodCatalog.json`, not a UI switch statement. It has canonical IDs and aliases spanning requested breads, rice, lentils, vegetarian and non-vegetarian dishes, snacks, sides, desserts, and drinks. It intentionally contains only a small set of low-confidence bundled recipe estimates. Missing values remain unavailable; partial totals carry a warning rather than appearing complete.

## Data-source policy

The [Indian Food Composition Tables 2017](https://www.nin.res.in/ebooks/IFCT2017_16122024.pdf), published by ICMR–National Institute of Nutrition, are the intended India-specific reference for a production server-side food-composition source. They do not make a photograph reveal a household recipe, cooking fat, or exact weight. Mixed dishes should be calculated from recorded ingredients and serving size or obtained from a documented provider, with source/version retained on every result.

The bundle is not presented as IFCT data and should not be expanded with copied numbers without a licensed, reviewed data-import process. A production nutrition provider should combine authoritative component data, curated recipe definitions, packaged labels, and member-created foods; a model estimate remains an explicit low-confidence fallback.

## Backend contract

`Backend/server.mjs` is a dependency-free runnable contract service, not a production deployment:

- It accepts only JSON with an allowlisted schema, validates MIME/base64/size, rejects malformed requests, applies a bearer-token development guard and rolling rate limit, sets `no-store`, and gives each response a request ID.
- It has `GET /health`, a versioned `POST /v1/meal-analysis`, request timeouts, strict result validation, and redacted audit events. Raw photo bytes and bearer tokens are not logged or written to disk.
- Fixture mode is an explicit development-only provider. It exercises the structural response, mixed-meal fixtures, and low-confidence situations; it is not computer vision and publishes no accuracy claim.
- A future `HTTPFoodRecognitionService` can call an authenticated endpoint with an account-scoped token. It has no provider credential. If that service fails or is absent, the app falls back to the transparent description flow.

Deployments must replace the development bearer guard with real authentication/authorization, managed secret storage, persistent rate limiting, TLS ingress, logging controls, temporary-object cleanup, abuse protection, costs/quotas, and provider observability. See [`Backend/README.md`](../Backend/README.md) for the deployment checklist and `.env.example` for non-secret configuration names.

## Privacy and App Store review checklist

- Camera and photo-library purpose strings are set in the project build settings.
- Before any future upload, the product must state who processes the image, why, how long it is retained, whether it trains any model, and how deletion works. Retention must be opt-in.
- Treat diary, food photos, and diabetes-related history as sensitive. Do not include raw data, tokens, or full meal descriptions in analytics logs.
- Review App Store privacy disclosures for camera/photo access, user content, account identifiers, and any health/fitness data actually collected by the shipping configuration. A privacy manifest and third-party SDK manifests are still required before release.
- The app is educational tracking software, not a medical device. It does not diagnose, give insulin instructions, change medication, or infer clinical status from a meal photo.

## Performance and quality gates

- Image preparation is bounded to 2048 px and 2 MB and runs only after the member chooses a photo. The default flow makes no network request and stores no temporary file.
- The generated food art is already cacheable by stable meal identity; a server-side generated-image service must use a canonical-food/variation/art-style cache key, cancellation, and retry rather than generating on every appearance.
- The app build and the unit-test bundle compile. Simulator run/recording, slow/offline networking, dark appearance, Dynamic Type, reduced-motion, smaller-device, frame-by-frame transition, and thermal/memory checks are still release gates because the current environment cannot access CoreSimulator.
