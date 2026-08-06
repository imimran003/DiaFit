# Privacy and security — Phase 4

Status: **code-level controls implemented; release approval still pending external work** (2026-08-06).

## Data map

- Diary meals, glucose readings, profile fields, confirmed food aliases, branded nutrition labels, and retained meal photos are stored in the app's Application Support container.
- Diary, profile, food-memory, packaged-food, and visual files are written atomically and receive iOS file protection (`completeUntilFirstUserAuthentication`). They are not written to analytics.
- Apple Health remains the source of HealthKit data. Diafit reads the permissions the member grants and does not delete or rewrite HealthKit history.
- A photo or meal description leaves the device only after the member chooses AI recognition. The iOS client sends it to the configured Diafit backend; provider credentials remain server-side.
- Development backend credentials are DEBUG-only and stored in Keychain with a device-only accessibility class. Release builds must use an authenticated production configuration.

## Member controls

- **Export my data** opens the iOS file/share flow and creates a versioned JSON snapshot of profile fields, meals, glucose readings, confirmed food aliases, and packaged nutrition labels.
- Export intentionally excludes internal UUIDs, cache keys, provider URLs, and binary photo bytes. It reports whether a profile photo exists without copying the photo.
- **Delete all local data** removes the diary archive, profile archive, confirmed food memory, packaged-food labels, and retained/generated meal visuals after an explicit destructive confirmation. Apple Health data is not removed because it belongs to Apple Health.
- **Reset profile** remains a narrower action and leaves diary, glucose, and activity data intact.

## Diagnostics and transport

- iOS food diagnostics are DEBUG-only and redact keys that could contain text, prompts, photos, tokens, notes, raw payloads, URLs, or file paths. Values are single-line and bounded.
- Backend audit logs are metadata-only with the same redaction boundary; request bodies, meal text, photo data, prompts, and credentials are never logged.
- The backend applies request size limits, request IDs, `no-store`, content-type hardening, constant-time development-token comparison, and rolling per-principal rate limits.
- Production authentication, TLS termination, secret management, retention, and abuse monitoring must be supplied by deployment infrastructure; the checked-in development bearer token is not a production auth system.

## Release checklist still owned outside this change

1. Deploy the backend behind TLS, real authentication/authorization, managed secrets, rate-limit persistence, and monitored abuse controls.
2. Publish the privacy policy, retention/deletion policy, support URL, and App Store privacy answers.
3. Review the `PrivacyInfo.xcprivacy` declarations against the final provider/data flows and App Store Connect submission.
4. Run a signed Release archive and physical-device security review, including photo payload and metadata stripping tests.

## Verification recorded for this change

- Privacy manifest and Release plist lint clean with `plutil -lint`.
- Swift app type-check, Debug test-bundle build, and Release build pass with the repository's Metal source excluded because this machine does not have the Metal toolchain installed.
- Backend tests and syntax checks pass.
- Simulator execution is still environment-blocked: CoreSimulatorService is refusing connections and no concrete simulator runtime is available. This is not a code-level privacy failure; rerun the UI/security smoke tests on a machine with a healthy simulator or a signed physical device.
