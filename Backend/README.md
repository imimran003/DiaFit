# Diafit analysis service

This is a deliberately small server-side boundary for meal understanding and photo analysis. It is runnable without dependencies. The bundled mock provider is useful for iOS integration and contract tests; it is not image recognition and must never be described as such in product copy.

## Run locally

```sh
cp .env.example .env
set -a; source .env; set +a
npm start
```

`GET /health` reports both analysis and meal-parser modes. `POST /v1/meal-analysis` is the legacy photo contract. `POST /v1/meal-parse` accepts text and/or a metadata-stripped JPEG/HEIC/PNG payload and returns schema-validated meal components. Both endpoints require the development bearer token locally. The process never writes image payloads to disk or logs them. It emits a random request ID and a one-way caller hash only.

Set `DIAFIT_MEAL_PARSER_MODE=mock` for deterministic offline parsing, or `openai` in a server environment with `OPENAI_API_KEY`. The OpenAI Responses API call uses strict Structured Outputs (`meal_parse_result`); the schema intentionally contains no nutrition fields. A nutrition service must canonicalise each item and resolve verified nutrition after parsing. `idempotencyKey` can be supplied to safely retry a parse without creating duplicate downstream meal work.

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
- Use the `OpenAIMealParser` provider behind the `/v1/meal-parse` seam. It calls the Responses API with strict JSON schema, validates every field, and retains model/version provenance at the API boundary. Keep canonical matching, nutrition lookup, recipe calculation, and plausibility validation in separate server services; never accept model-generated nutrition as authoritative.
- Query an authoritative nutrition source server-side. The Indian Food Composition Tables 2017 are a useful food-composition reference, but mixed recipes need a provider or ingredient calculation with serving provenance. See the [official IFCT PDF](https://www.nin.res.in/ebooks/IFCT2017_16122024.pdf).
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
