# Diafit verification matrix

Status legend: **Pass**, **Fail**, **Gap**, **Blocked**, **Not run**.

## Baseline automated results

| Suite | Device | Result |
| --- | --- | --- |
| Debug build | iPhone 17 Pro / iOS 26.5 | **Pass** |
| Unit + provider-independent integration | iPhone 17 Pro / iOS 26.5 | **Pass — 29/29** |
| UI | iPhone 17 Pro / iOS 26.5 | **Pass — 8/8** |

## Known food regressions

| Input | Entities | Quantity/unit | Nutrition | Visual | Status |
| --- | --- | --- | --- | --- | --- |
| `black coffee` | Black coffee | 1 cup | Plausible curated record | Deterministic | **Pass** |
| `chai and paratha` | Chai + paratha | Defaults pending choices | Unavailable until material choices | Neutral/no salad | **Pass with clarification** |
| `sprouts with 3 boiled eggs` | Sprouts + boiled egg | Sprouts default; eggs 3 whole | Nonblank | Quantity-aware request | **Pass** |
| `whey protein shake` | Generic whey | Default scoop; base ambiguous | Editable generic fallback | Waits for clarification | **Pass** |
| `one scoop whey with water` | Generic whey | 1 scoop, water | Nonblank; water adds zero | No milk/fruit prompt | **Pass** |
| `three eggs with sprouts` | Egg + sprouts | Sprouts becomes `3 wholeEgg` | Incorrect scaling risk | Incorrect structured identity risk | **Fail** |

Audit-branch result after the component-span repair:

| Input | Expected isolation | Result |
| --- | --- | --- |
| `three eggs with sprouts` | Eggs 3 whole; sprouts 1 medium bowl | **Pass** |
| `two scoops whey and banana` | Whey 2 scoops; banana 1 piece | **Pass** |
| `fried eggs with raw sprouts` | Fried applies only to eggs; raw only to sprouts | **Pass** |
| `one and a half scoop whey with water` | Compound number stays 1.5 | **Pass** |

## Flow inventory

| Flow | Baseline state | Coverage | Next evidence |
| --- | --- | --- | --- |
| Launch | Sample diary opens; blank intermediate frame | Manual screenshot | Measure first useful screen and remove flash |
| Onboarding | No onboarding found | **Gap** | Define minimal goals/consent flow |
| Empty day | No empty-day fixture/test | **Gap** | Unit + UI state |
| Text meal entry | Working | UI | Broaden food matrix |
| Compound meal | Working for selected cases | Unit/UI | Span-bound property tests |
| Camera | Sheet exists | Simulator limited | Permission-denial + physical device |
| Photo library | Photos picker exists | Fixture UI only | Real selection + metadata test |
| Nutrition review | Working | UI | Large text and VoiceOver |
| Portion correction | Working in review | UI for sprouts | Repeated-edit monotonicity |
| Clarification | Working for chai/whey | Unit/UI partial | Persistence and duplicate reply handling |
| Confirmation | Durable local archive | Unit + process-relaunch UI | Multi-device migration coverage |
| Edit | Context-menu refine | Same-process UI partial | Totals exactly once + relaunch |
| Delete | Alert and in-memory removal | **Gap** | Totals, images, persistence, cancellation |
| Previous-day edit | Day pages exist | **Gap** | State and totals |
| Day paging | `TabView.page` | **Gap** | Gesture conflicts and retained state |
| Atlas/history | Single-day modal grid | Basic UI | Multi-day semantic zoom |
| Image loading/failure | No runtime generator | **Gap** | Provider mock states and recovery |
| Manual food search | Not found | **Gap** | Product/design decision |
| Recent/saved foods | Suggestion strings only | **Gap** | Domain + persistence |
| Packaged whey | Generic records | Unit partial | Saved product/label/barcode |
| Offline | Local parser works | Implicit | Explicit UI/provider degradation |
| Background/termination | Confirmed meal survives process relaunch | **Pass** | Background task/provider restoration remains |
| Settings | Not found | **Gap** | Privacy, goals, accessibility, data deletion |
| Dark mode | Forced light mode | **Fail** | Adaptive design screenshots |
| Dynamic Type | Mostly fixed fonts | **Gap** | Accessibility sizes |
| Reduce Motion | Atlas close only | **Gap** | App-wide alternatives |

## Boundary/property worklist

- Quantities 0.1…20 remain monotonic and finite.
- Weights 1…2,000 g never overflow or become negative.
- Each component owns its quantity, unit, preparation, additions and exclusions.
- Edits do not multiply cached/scaled nutrients repeatedly.
- Daily totals equal the set of confirmed meals exactly once.
- Midnight and timezone changes keep meals on the intended local day.
- Missing values remain unavailable, never zeroed silently.
- Energy consistency tolerates fibre/incomplete records without accepting implausible category values.

## Device/configuration matrix

| Configuration | Status |
| --- | --- |
| iPhone 17 Pro, light, default text | **Baseline pass** |
| Smaller supported iPhone | **Not run** |
| Large iPhone | **Not run** |
| Dark mode | **Blocked by forced light scheme** |
| Largest Dynamic Type | **Not run** |
| Reduce Motion | **Not run** |
| Reduce Transparency | **Not run** |
| Offline/slow provider | **Not run** |
| Physical iPhone 15 Pro | **Not run; device availability unknown** |
