# Diafit analysis service

This is a deliberately small server-side boundary for photo analysis. It is runnable without dependencies, but its only bundled provider is a development fixture provider. That provider is useful for iOS integration and contract tests; it is not image recognition and must never be described as such in product copy.

## Run locally

```sh
cp .env.example .env
set -a; source .env; set +a
npm start
```

`GET /health` reports the active mode. `POST /v1/meal-analysis` requires the development bearer token and accepts only a metadata-stripped JPEG/HEIC/PNG payload encoded as JSON. The process never writes image payloads to disk or logs them. It emits a random request ID and a one-way caller hash only.

## Required production work

- Replace the development token guard with account authentication and authorization verified by a managed identity provider or JWKS.
- Terminate TLS at managed ingress; restrict origins/network access; use managed rate limiting and WAF controls.
- Store vision, image-generation, and nutrition keys only in a managed secret store. Do not put them in Xcode settings, app resources, or `.env.example`.
- Use a vision provider that returns strict JSON, validate that JSON with a schema, and retain the provider/model/version provenance.
- Query an authoritative nutrition source server-side. The Indian Food Composition Tables 2017 are a useful food-composition reference, but mixed recipes need a provider or ingredient calculation with serving provenance. See the [official IFCT PDF](https://www.nin.res.in/ebooks/IFCT2017_16122024.pdf).
- Make retention opt-in, delete temporary objects on timeout, redact sensitive data from logs, establish data-processing agreements, and complete privacy/App Store disclosure review.
- Add load testing, persistent rate limiting, tracing, error budgets, cost limits, retries with idempotency keys, and a dead-letter/error workflow before serving real accounts.

## API contract

The client sends `apiVersion`, `imageReference`, `mimeType`, `imageBase64`, and a short `dishHint`. The server checks MIME, size, field allowlist, auth, rate limit, and timeout before asking a provider. Responses must match the strongly typed `MealAnalysisResult` shape used by the iOS app. Invalid provider output is rejected rather than coerced.

The response treats all food analysis as an estimate. It does not calculate glycaemic load unless a source supplies both GI and available carbohydrate, and it does not provide diagnostic or medication guidance.
