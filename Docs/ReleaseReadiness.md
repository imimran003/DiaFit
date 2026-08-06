# Release readiness — Phase 5

Status: **code-level release/service hardening implemented; distribution still requires Apple and deployment setup** (2026-08-06).

## What this phase closes

- Production backend configuration fails closed if it would bind to loopback, use the development bearer token, use a mock/disabled meal parser, or omit the identity-provider and selected provider credentials.
- `/v1/*` authentication supports short-lived RS256 access tokens verified against a configured HTTPS JWKS endpoint. The backend retains only a one-way principal hash for rate limiting and diagnostics.
- Production health output exposes only `{ status, apiVersion }`; provider modes and fixture versions remain development-only.
- Node HTTP request, header and keep-alive timeouts are bounded, and production responses include HSTS.
- The repeatable `Tools/verify-release.sh` audit checks privacy metadata, release plist wiring, secret patterns, backend tests, and an unsigned Release build.

## Run the local release audit

```sh
./Tools/verify-release.sh
```

The audit intentionally excludes `Daylight.metal` when the local Xcode installation
does not include Apple's Metal toolchain. A shipping archive must compile the
shader with the complete Xcode installation; this exception is only for the
current development machine's source/build verification.

## Required deployment configuration

Production needs all of the following in the managed deployment environment,
never in the iOS target or Git:

```text
DIAFIT_DEPLOYMENT_ENV=production
DIAFIT_AUTH_MODE=jwks
DIAFIT_AUTH_JWKS_URL=https://identity.example/.well-known/jwks.json
DIAFIT_AUTH_ISSUER=https://identity.example/
DIAFIT_AUTH_AUDIENCE=diafit-api
DIAFIT_MEAL_PARSER_MODE=openai|gemini
OPENAI_API_KEY or GEMINI_API_KEY
```

Select `DIAFIT_NUTRITION_PROVIDER_MODE=usda` only when a managed
`USDA_FDC_API_KEY` is present. The server does not accept model-generated
nutrition as authoritative.

## Still outside the repository

1. Configure the identity provider, TLS ingress, WAF and persistent rate limit.
2. Create the managed provider secret store and production deployment.
3. Validate the App Store privacy answers, support URL, retention policy and
   account deletion policy against the deployed data flows.
4. Configure the Apple Developer signing team, archive/export options and
   TestFlight testers.
5. Run the signed archive and physical-device matrix, including camera/photo
   payloads, HealthKit, backgrounding, memory, thermal and accessibility.
