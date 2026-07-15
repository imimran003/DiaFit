# Diafit production audit plan

## Protected baseline

- Baseline branch: `main`
- Baseline commit: `e1c2ab6eb92ee5c0e94b208be4a57cfd0b2ac322`
- Audit branch: `codex/production-audit`
- Baseline worktree: clean and already pushed to `origin/main`
- Primary simulator: iPhone 17 Pro, iOS 26.5, `CBD8A933-CE89-44B2-85E8-8E3D4F22F038`

## Evidence recorded before modification

| Check | Result | Evidence |
| --- | --- | --- |
| Debug build | Passed | `xcodebuild ... -scheme Diafit ... build` |
| Unit/integration suite | 29 passed, 0 failed | `Test-DiafitUnitTests-2026.07.15_11-06-13-+0200.xcresult` |
| UI suite | 8 passed, 0 failed | `Test-Diafit-2026.07.15_11-07-52-+0200.xcresult` |
| Immediate launch frame | Blank white content | `/private/tmp/diafit-baseline-launch.png` |
| Settled launch frame | Existing diary at newest thread tail | `/private/tmp/diafit-baseline-settled.png` |
| Reference recording | 32.35 s, 2940×1846; 12 audit frames extracted | `/private/tmp/diafit-reference-00.png` … `11.png` |

## Work sequence

1. **Baseline and inventory — complete**
   - Map targets, services, state, backend, configuration, tests and release settings.
   - Inventory screens and flows.
   - Record actual design-reference observations.
2. **Correctness — in progress**
   - Add a failing regression for cross-component quantity leakage.
   - Bound quantities, units, preparation methods and modifiers to their component spans.
   - Expand Indian compound-meal and property coverage.

### Correctness evidence recorded

- Red run: 30 tests discovered; the new component-isolation test produced four failures (`3 wholeEgg` on sprouts and `2 scoop` on banana).
- Green run: 31 tests passed after connector-bounded entity scopes were introduced.
- Fractional regression retained: `one and a half scoop whey with water` remains 1.5 scoops.
- Preparation regression added: `fried eggs with raw sprouts` retains `fried` and `raw` independently.
3. **Durability and idempotency**
   - Introduce a repository boundary and versioned on-device persistence.
   - Test relaunch, corruption, edit/delete totals and day boundaries.
4. **Nutrition integrity**
   - Make source, fallback level and assumptions explicit in the domain and UI.
   - Expand category sanity checks and scale/property tests.
5. **Meal visuals**
   - Separate original photos, generated visuals and deterministic placeholders.
   - Add a runtime provider boundary, durable request state and recoverable failures without bundling secrets.
6. **Editorial redesign**
   - Consolidate tokens and remove excess cards, pills, blur and competing colour.
   - Make carbohydrates dominant, preserve day identity and make meal entries easier to scan.
7. **Paging and semantic zoom**
   - Preserve stable identities and state across days.
   - Evolve the single-day modal grid into a multi-day spatial history with a Reduce Motion path.
8. **Accessibility, performance, privacy and release**
   - Verify assistive settings, measure launch/scroll/image costs, add privacy metadata and enumerate external blockers.
9. **Final verification**
   - Run unit, integration, UI, Release and Analyze commands.
   - Verify light/dark, small/large simulator, Dynamic Type and Reduce Motion.
   - Review all diffs, update evidence, commit in focused milestones and push.

## Commit plan

- `audit: record production baseline and architecture`
- `fix: isolate compound meal quantities and modifiers`
- `feat: persist diary with safe migrations`
- `fix: strengthen nutrition integrity and provenance`
- `feat: harden meal visual requests and recovery`
- `design: consolidate premium editorial system`
- `feat: refine day paging and semantic zoom`
- `fix: improve accessibility and reduced-motion behavior`
- `perf: downsample imagery and reduce view invalidation`
- `chore: add privacy and release-readiness safeguards`

## Rules used for decisions

- Deterministic parsing, curated nutrition and validation own persisted values.
- Ambiguous material assumptions remain drafts until confirmed.
- Generated imagery is decorative and cannot establish ingredients or nutrition.
- External provider secrets remain server-side.
- Existing working behavior is retained unless evidence shows that it harms correctness, accessibility, performance or maintainability.
- A green build is necessary but never sufficient evidence of completion.
