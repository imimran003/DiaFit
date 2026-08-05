# Diafit analysis service

This is a deliberately small server-side boundary for meal understanding and photo analysis. It is runnable without dependencies. The bundled mock provider is useful for iOS integration and contract tests; it is not image recognition and must never be described as such in product copy.

## Run locally

```sh
cp .env.example .env
set -a; source .env; set +a
npm start
```

`GET /health` reports both analysis and meal-parser modes. `POST /v1/meal-analysis` is the legacy photo contract. `POST /v1/meal-parse` accepts text and/or a metadata-stripped JPEG/HEIC/PNG payload and returns schema-validated meal components. Both endpoints require the development bearer token locally. The process never writes image payloads to disk or logs them. It emits a random request ID and a one-way caller hash only.

Set `DIAFIT_MEAL_PARSER_MODE=mock` for deterministic offline parsing, `gemini` with a server-only `GEMINI_API_KEY`, or `openai` with a server-only `OPENAI_API_KEY`. Gemini uses `generateContent` with inline image data and a strict response JSON schema; OpenAI uses the Responses API with strict Structured Outputs (`meal_parse_result`). The shared schema intentionally contains no nutrition fields. A nutrition service canonicalises each item and resolves verified nutrition after parsing. `idempotencyKey` can be supplied to safely retry a parse without creating duplicate downstream meal work.

Image parses also include a strict `visualCoverage` contract. The provider must
report the regions scanned, visible/distinct serving counts, occlusions, and
whether the inventory is complete. The iOS client will not take the one-pass
fast path when that evidence is missing, contradictory, or low confidence; it
returns a recoverable review instead of presenting a salient garnish as the
whole meal. Provider transport retries are bounded by
`MEAL_PARSE_PROVIDER_ATTEMPTS` (1–3, default 2) and
`MEAL_PARSE_RETRY_BASE_MS` (default 250 ms), and stop when the route aborts.

The Gemini free tier is suitable for development and personal testing, subject to Google's current quotas and data-use terms. It is not an unlimited production service. Keep the key out of the iOS target and Git, and obtain explicit consent before uploading a meal photo. For a local free-tier run, copy `.env.example` to the ignored `.env`, set `DIAFIT_MEAL_PARSER_MODE=gemini`, and add `GEMINI_API_KEY` there.

`POST /v1/nutrition-lookup` is the server-owned verified nutrition boundary. It
accepts a canonical food name and an optional gram amount and returns only a
complete, provenance-bearing record or an explicit unavailable response. Set
`DIAFIT_NUTRITION_PROVIDER_MODE=usda` and provide `USDA_FDC_API_KEY` in the
backend's secret environment to enable the FoodData Central adapter. The key is
never sent to iOS. Results retain the FDC record ID, provider, data version,
serving grams, and confidence. If the provider is disabled, unreachable, or
incomplete, the app keeps its editable curated fallback rather than treating a
blank result as success.

`POST /v1/meal-visual` is the optional provider-independent visual endpoint for
text-only meals. Set `DIAFIT_MEAL_VISUAL_MODE=gemini` to enable it. It uses
`GEMINI_IMAGE_MODEL` and returns a validated, association-bound image payload;
the provider key never enters the app. Gemini image generation currently has
no free API tier, so this mode is deliberately disabled by default. Uploaded
meal photos do not use this endpoint: after confirmation, the prepared,
metadata-stripped photo is kept only in protected local app storage.

An opt-in live smoke test is available after the backend starts. Set `LIVE_FOOD_IMAGE_PATH` to a local JPEG or PNG and run `npm run test:live-photo`. It prints only structured food identities and confidence; it never prints the image or provider credential. Deterministic CI continues to use the mock provider. The local HTTPS tunnel used for device testing is temporary: restart it and update the user-only Xcode scheme whenever its URL changes.

For an Xcode-launched simulator build, pass the backend origin as
`DIAFIT_BACKEND_URL` and the development/account bearer token as
`DIAFIT_BACKEND_ACCESS_TOKEN`. `http://127.0.0.1` is accepted only for local
development; physical devices and production deployments require HTTPS. These
are app-to-backend credentials, never an OpenAI key. An installed phone build
cannot use the Mac's loopback address.

Run `npm run evaluate:food-resolution` for the checked-in 165-input development evaluation suite. It reports parser detection, compound decomposition, blank-result and fallback metrics; nutrition accuracy still requires the provider-backed integration suite.

## Required production work

- Replace the development token guard with account authentication and authorization verified by a managed identity provider or JWKS.
- Terminate TLS at managed ingress; restrict origins/network access; use managed rate limiting and WAF controls.
- Store vision, image-generation, and nutrition keys only in a managed secret store. Do not put them in Xcode settings, app resources, or `.env.example`.
- Use `GeminiMealParser` or `OpenAIMealParser` behind the `/v1/meal-parse` seam. Both send images only from the backend, request strict JSON, validate every field, and retain model/version provenance at the API boundary. Keep canonical matching, nutrition lookup, recipe calculation, and plausibility validation in separate server services; never accept model-generated nutrition as authoritative.
- Query an authoritative nutrition source server-side. FoodData Central exposes food-search and food-detail endpoints and requires a server-side API key; retain the returned record ID with each result. See the [official FoodData Central API specification](https://fdc.nal.usda.gov/api-spec/fdc_api.html) and [official data documentation](https://fdc.nal.usda.gov/data-documentation/). The Indian Food Composition Tables 2017 are a useful food-composition reference, but mixed recipes need a provider or ingredient calculation with serving provenance. See the [official IFCT PDF](https://www.nin.res.in/ebooks/IFCT2017_16122024.pdf).
- Make retention opt-in, delete temporary objects on timeout, redact sensitive data from logs, establish data-processing agreements, and complete privacy/App Store disclosure review.
- Add load testing, persistent rate limiting, tracing, error budgets, cost limits, retries with idempotency keys, and a dead-letter/error workflow before serving real accounts.

## API contract

The hybrid parser client sends `apiVersion`, optional `text`, optional
`imageReference`, optional `mimeType`/`imageBase64`, and an optional
`idempotencyKey` to `POST /v1/meal-parse`. The server checks the field
allowlist, image MIME/size, auth, rate limit, timeout, and idempotency before
asking a provider. Responses must match the strict `MealParseResult` schema;
invalid provider output is rejected rather than coerced. The legacy
`POST /v1/meal-analysis` photo contract remains available for the existing
photo flow while it is migrated to the same provider hierarchy.

The response treats all food analysis as an estimate. It does not calculate glycaemic load unless a source supplies both GI and available carbohydrate, and it does not provide diagnostic or medication guidance.

Nutrition provider responses are not model nutrition. A model may identify a
food or suggest recipe ingredients, but only a provider, a user-confirmed label,
or a curated/calculated fallback may supply values used by the app. The iOS
client sends only canonical names and serving grams to the nutrition endpoint.
