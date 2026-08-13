# Photo analysis architecture, privacy, and data decisions

## What is working in this repository

The current iOS build supports a complete **image-first local review path**:

1. The member opens the camera or photo library from the conversation composer.
2. The app validates, orientation-normalizes, resizes (maximum 2048 px), recompresses (maximum 2 MB), and creates a fresh JPEG representation. That representation deliberately drops EXIF metadata, including location metadata.
3. Selecting the photo immediately starts analysis; a description and a second “upload” action are not required. When a schema-constrained backend is configured, its component-aware interpretation owns photo identity. The private `VNClassifyImageRequest` path collects local fallback labels at 0.20 or above and admits only labels that map to the canonical catalog, but it is used only when live interpretation is unavailable. `PhotoAnalysisCompletenessEvaluator` still checks identity, serving conversion, core nutrition, provenance and validation before anything can be confirmed. A final provider-independent dish/count audit runs for high-impact visual ambiguities: paneer in a green leafy gravy is normalized to one palak-paneer serving (never plain paneer plus a curry), and explicit evidence such as “two visible roti layers” overrides a conflicting provider count while preserving an editable clarification.
    The provider must also return visual-coverage evidence: the regions scanned, visible and distinct serving counts, occlusions, and an explicit completeness/confidence value. A high-confidence, contradiction-free inventory can take a single-pass fast path; missing or weak coverage automatically enters independent full-frame verification. Early inventories are canonicalised, merged, and de-duplicated so a normal verification pass does not erase a supported serving. If the full-frame passes still collapse a plate to a generic dish, garnish, or otherwise weak small inventory, a spatially cropped review scans overlapping regions and a final full-frame adjudication is requested. A materially stronger adjudication becomes the corrected inventory rather than being blindly unioned with earlier false labels. This specifically prevents a visually incomplete but nutritionally valid result such as “rice + vegetable soup”, “tomato + soup”, or “peanut” from hiding dal, dry sabzi, stacked rotis, eggs, sprouts, or nuts. A separate inventory-coverage gate runs before nutrition completeness: small generic or garnish-led inventories are never accepted as a complete plate even when their calories and provenance are valid. If the provider still cannot account for the plate, the app withholds confirmation, preserves the photo, and exposes a retryable state instead of saving misleading totals. Conversely, a specific multi-food inventory is retained for review when its lower aggregate confidence comes only from serving or recipe uncertainty. When verification evidence conflicts, the provider-independent audit takes the conservative lower visible count; it also promotes paneer in green leafy gravy to a single palak-paneer dish before canonical nutrition lookup, so a stale “paneer + roti 3” response cannot reach the review UI unchanged.
4. Image recognition proposes food identities only. Canonical records and the nutrition-resolution layer calculate the editable estimate; classifier output is never used as nutrition data. Exact portions, cooking fat, sauces, and hidden ingredients remain reviewable assumptions.
5. The draft appears inside the day thread, exposes components, quantities and serving units, asks only applicable high-impact questions, and recalculates supported values after correction. A compound correction such as “carrots with blueberries” resolves every supported component instead of silently failing an exact-string lookup.
6. Only an explicit confirmation replaces the draft with a logged meal. The resulting meal is immediately available to the existing meal atlas. A confirmed analysis can be reopened for refinement or deleted through an explicit destructive confirmation.

No photo is uploaded by the default app configuration. When an authenticated backend is explicitly configured, the backend may use the optional Gemini or OpenAI structured vision parser; provider keys never enter the iOS binary. Before confirmation, photo bytes remain transient. Confirmation retains the prepared, metadata-stripped photo as a protected local asset referenced by the meal archive; it is excluded from device backup and removed with the meal. It remains visual context, not evidence of ingredients or portion.

Text-only meals may request an editorial food image from the authenticated
`/v1/meal-visual` backend route. The request is quantity-sensitive and bound to
meal, request, cache, and style identifiers. A late or mismatched response is
discarded. Provider credentials stay server-side. Generated visuals are
decorative and never supply nutrition data.

Provider output is deduplicated before nutrition aggregation, and canonical matching checks its English search name, regional name, and original term. This prevents one physical rice serving from being counted twice under alternative preparation labels and preserves regional components such as roti, dal, and dry sabji in a mixed thali. A preparation conflict becomes one editable component with a clarification instead of two calorie entries.

Structured interpretation also carries a coarse typed food category and optional visual quantity evidence. A recognised component is never removed merely because the bundled catalog lacks an exact row: the app creates a provisional identity, labels the resulting category-level nutrition as a curated estimate, and keeps the item editable. If even a safe category cannot be established, the unresolved component still remains visible with an explicit unavailable state. Countable foods such as eggs and stacked breads must include concise visual count evidence; absent evidence lowers confidence and creates a quantity clarification instead of silently defaulting to one.

### Portion and prepared-dish reconciliation

The image pipeline treats provider output as multiple observations of one plate,
not as additive truth. When full-frame and verification passes disagree on a
discrete count, the lower visible bound is retained, the item is marked for
confirmation, and its estimated grams and nutrition scale from that count. A
catalog-specific bread conversion is used even when a provider says `piece`,
so two rotis use two 35 g servings rather than a generic 120 g piece estimate.
Ingredient-only observations are collapsed when a more specific prepared dish
is present: paneer in visible spinach gravy becomes one editable `Palak paneer`
component, never both paneer and palak paneer. Tiny onions, garnishes and papad
fragments are excluded unless a separate serving is explicitly evidenced or a
second pass corroborates them. The bundled palak-paneer record is a traceable,
editable 180 g katori estimate (150 kcal, 8 g protein, 7 g carbohydrate, 10 g
fat and 2.5 g fibre per 100 g); it is not treated as an exact recipe or medical
claim.

The photo picker states this escalation before selection: processing starts on device, and uncertain local results may send a metadata-stripped copy to the configured AI provider. Development use of Gemini's free tier remains subject to Google's quotas and data-use terms; it is not the shipping privacy posture for sensitive health data without a completed consent, retention, and disclosure review.

If automatic recognition cannot clear the completeness gate, the review keeps the photo and presents one recoverable food-name field. Submitting that field now shows an explicit error when unresolved, or removes the blocking identification question and enables confirmation after nutrition validates. The review uses opaque semantic surfaces rather than translucent white overlays so labels, controls and nutrition remain legible in dark mode and under Reduce Transparency.

## Models and services

`MealAnalysisModels.swift` establishes the shared contract:

- `MealAnalysisResult`, `DetectedFoodItem`, `NutritionValues`, `GlycaemicInformation`, and `ClarificationQuestion` are Codable and validate the shape expected from a backend.
- Nutrient fields are optional. `nil` means unavailable, not zero.
- Every nutrition result has `NutritionProvenance`; estimates are labelled as estimates.
- Glycaemic load is only calculated by `GI × available carbohydrate / 100` when both a sourced GI and available carbohydrate are present. The bundled catalog does not claim GI values, so it shows `Not available`.
- An unconfirmed `MealAnalysisDraft` is structurally separate from a confirmed `Meal`.

`FoodAnalysisServices.swift` provides protocol seams for backend recognition, on-device image classification, normalization, nutrition lookup, glycaemic data, portions, draft storage, confirmed logging, image preparation, generated editorial imagery, and conversational tools. Views do not know about provider SDKs or API credentials.

The local catalog is `IndianFoodCatalog.json`, not a UI switch statement. It has canonical IDs and aliases spanning requested breads, rice, lentils, vegetarian and non-vegetarian dishes, snacks, sides, desserts, drinks, and common photo-recognisable foods. `sabudana`, `sabodana`, sago and tapioca-pearl aliases map to a low-confidence, editable sabudana-khichdi recipe record. Catalog identities with no direct nutrition record route through the validated curated category/ingredient fallback; deliberately broad unknowns such as mixed thali remain unavailable instead of receiving a fabricated total.

## Data-source policy

The [Indian Food Composition Tables 2017](https://www.nin.res.in/ebooks/IFCT2017_16122024.pdf), published by ICMR–National Institute of Nutrition, are the intended India-specific reference for a production server-side food-composition source. They do not make a photograph reveal a household recipe, cooking fat, or exact weight. Mixed dishes should be calculated from recorded ingredients and serving size or obtained from a documented provider, with source/version retained on every result.

The bundle is not presented as IFCT data and should not be expanded with copied numbers without a licensed, reviewed data-import process. A production nutrition provider should combine authoritative component data, curated recipe definitions, packaged labels, and member-created foods; a model estimate remains an explicit low-confidence fallback.

## Backend contract

`Backend/server.mjs` is a dependency-free runnable contract service, not a production deployment:

- It accepts only JSON with an allowlisted schema, validates MIME/base64/size, rejects malformed requests, applies a bearer-token development guard and rolling rate limit, sets `no-store`, and gives each response a request ID.
- It has `GET /health`, a versioned `POST /v1/meal-analysis`, request timeouts, strict result validation, and redacted audit events. Raw photo bytes and bearer tokens are not logged or written to disk.
- Fixture mode is an explicit development-only provider. It exercises the structural response, mixed-meal fixtures, and low-confidence situations; it is not computer vision and publishes no accuracy claim.
- `BackendFoodUnderstandingService` calls `/v1/meal-parse`; `StructuredPhotoRecognitionService` converts its schema-constrained food identities into canonical matches and validated nutrition. The runtime constructs this path only when `DIAFIT_BACKEND_URL` and `DIAFIT_BACKEND_ACCESS_TOKEN` (or the legacy local `DIAFIT_DEVELOPMENT_TOKEN`) are supplied through the Xcode launch environment. In DEBUG builds, a configured launch stores only that temporary backend URL and app-to-backend access token in the device Keychain using `AfterFirstUnlockThisDeviceOnly`; if a simulator Keychain service is temporarily unavailable, the same debug-only credential is written to an app-container file with complete file protection and is verified on the next launch. This lets a developer reopen the installed app from the Home Screen without silently losing live recognition. A later configured launch replaces stale tunnel details. Release builds do not use this development persistence path and must obtain an authenticated backend session through the production account flow.
- The phone bounds a structured vision request to 20 seconds for an image (10
  seconds for text) while the backend provider deadline remains configurable.
  The backend retries transient provider responses at most once by default;
  the client also retries one transient upload/network interruption with the
  same idempotency key. This ordering is
  intentional: the backend must finish or reject the request before the phone
  considers private on-device recovery. Response metadata is decoded through a
  separate envelope and must echo the exact prepared-image reference; a late
  response for another photo is rejected before it can reach the review. The
  independent spatial pass receives its own transient reference. Development
  diagnostics record only status, byte count, component count, and a safe
  coding path—never photo bytes or meal text.
- Prepared JPEGs are capped at 1.9 MB. Base64 expansion therefore remains under
  the backend's 2.8 MB JSON-body limit; accepted device photos cannot cross the
  transport boundary and then fail solely because of encoding overhead.
- Gemini and OpenAI provider credentials always remain on the Mac or deployed backend and never enter the iOS binary or device Keychain. If a configured live service fails, the app may retain supported on-device canonical suggestions, but it marks the result low confidence and requires an explicit confirmation that the food names match the photo. It must not present local fallback labels as a successful live-AI result.

Deployments must replace the development bearer guard with real authentication/authorization, managed secret storage, persistent rate limiting, TLS ingress, logging controls, temporary-object cleanup, abuse protection, costs/quotas, and provider observability. See [`Backend/README.md`](../Backend/README.md) for the deployment checklist and `.env.example` for non-secret configuration names.

## Privacy and App Store review checklist

- Camera and photo-library purpose strings are set in the project build settings.
- Before any future upload, the product must state who processes the image, why, how long it is retained, whether it trains any model, and how deletion works. Retention must be opt-in.
- Treat diary, food photos, and diabetes-related history as sensitive. Do not include raw data, tokens, or full meal descriptions in analytics logs.
- Review App Store privacy disclosures for camera/photo access, user content, account identifiers, and any health/fitness data actually collected by the shipping configuration. A privacy manifest and third-party SDK manifests are still required before release.
- The app is educational tracking software, not a medical device. It does not diagnose, give insulin instructions, change medication, or infer clinical status from a meal photo.

## Performance and quality gates

- Image preparation is bounded to 2048 px and 2 MB and runs only after the member chooses a photo. The default flow makes no network request and stores no temporary file. Vision work runs off the main actor, while the thread shows explicit identifying and nutrition-resolution progress.
- The whole-image on-device classifier is a privacy-preserving candidate generator, not a component detector or portion-measurement system. A 0.20 collection threshold retains potentially useful catalog labels, but an image-only meal is never considered complete from these labels—even one high-confidence label cannot prove that no other food is present. Structured vision owns automatic photo inventory; when it is unavailable, the photo is preserved and the member is asked for a food name rather than being shown a confident-looking partial meal. Deterministic tests verify that both a single generic “vegetable soup” result and multiple “rice + soup” labels are withheld after backend failure.
- This invariant is enforced after every fallback path, including incomplete local nutrition. A classifier label such as “Peanut” can have valid calories while still omitting the eggs, sprouts, or other piles in the photograph; it is therefore withheld before the review model is built. The review UI also hides partial labels and totals in stale drafts, leaving one retry/manual-correction state. A configured backend must be reachable for automatic photo inventory; the local path never pretends to be AI recognition.
- The generated food art is already cacheable by stable meal identity; a server-side generated-image service must use a canonical-food/variation/art-style cache key, cancellation, and retry rather than generating on every appearance.
- Production Swift sources typecheck against the iOS simulator SDK. Focused image-only resolution, backend fallback, compound correction, and one-tap UI regressions are maintained alongside the broader deterministic suite. Slow/offline networking, dark appearance, Dynamic Type, reduced-motion, smaller-device, frame-by-frame transition, and thermal/memory checks remain release gates.
