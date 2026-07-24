# Apple Health activity integration

## Scope

Diafit reads four daily aggregate types from HealthKit:

* step count;
* walking and running distance;
* active energy burned;
* basal (resting) energy burned.

It does not write Health data, request clinical records, or transmit these
activity values to the Diafit backend. The HealthKit capability and
`NSHealthShareUsageDescription` are declared by the app target.

## Consent and failure behavior

Health access is opt-in from the home screen. Diafit does not show the system
authorization sheet at first launch. Declining or partially granting access
does not block meals, glucose tracking, or any other local feature.

Apple intentionally does not reveal whether read access to an individual type
was denied. Diafit therefore queries only after the member has completed the
authorization flow and treats missing samples as unavailable data. It never
replaces missing Health values with zero.

## Daily calculations

Queries use the selected day’s local calendar boundary:

```text
day start <= sample < next local day start
```

The displayed values are:

```text
intake = confirmed meal calories for the selected diary day
burned = active energy + resting energy
balance = intake - burned
```

When balance is negative the magnitude is labelled **Deficit**. When positive
it is labelled **Surplus**. Zero is labelled **Balanced**. This is arithmetic
tracking only, not a treatment target or medical conclusion.

Diafit requires both active and resting energy before calculating a balance.
If either is unavailable, it may still show available steps, distance, or
active calories, but the balance remains unavailable with a plain explanation.
This prevents active calories alone from being misrepresented as total daily
energy expenditure.

## Architecture

`HealthActivityProviding` is injected through `AppDependencies`.
`HealthKitActivityService` owns HealthKit permission and aggregate queries.
`HealthActivitySummary` contains optional source values and
`DailyEnergyBalance` performs the pure, testable calculation. SwiftUI does not
query `HKHealthStore` directly.

The UI refreshes when the selected day changes, after a successful connection,
when the member taps refresh, and when the app returns to the foreground.

## Privacy and release checklist

* Health values are not written to analytics or diagnostics.
* Raw Health samples are not persisted in the diary archive.
* The app requests read access only to the four stated activity types.
* App Store privacy answers and HealthKit purpose text require product/legal
  review before release.
* A physical-device test must verify partial permissions, denied permissions,
  no-watch/no-data days, time-zone changes, and source aggregation.

