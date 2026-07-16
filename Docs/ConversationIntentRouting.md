# Conversation intent routing

## Purpose

The daily composer accepts both meals and glucose readings. Domain parsers must
not compete to consume the same text. `ConversationInputRouting` is the single
boundary that classifies an entry before either the food-resolution or glucose
flow starts.

## Root cause of the July 2026 regression

The glucose parser previously ran before food analysis and treated the bare word
`sugar` as glucose evidence. It then selected the first number anywhere in the
sentence. A meal such as “sprouts … milk tea without sugar” was consequently
routed to glucose, and its first food quantity became the apparent reading.

The same number-selection behavior made “2-hour post-meal glucose 126” use `2`
instead of `126`.

## Routing contract

`DefaultConversationInputRouter` returns exactly one route:

- `food`: continue through the existing food-understanding pipeline;
- `glucose`: present a parsed glucose draft for confirmation;
- `clarification`: ask one concise question when choosing a domain would be
  unsafe.

Food is the safe default. An input is classified as glucose only when it includes
measurement-shaped evidence such as FBS/PPBS, blood glucose, blood sugar, a
glucose unit, or sugar language tied to fasting, a meal, bedtime, or an explicit
reading expression.

Food language such as `without sugar`, `sugar-free`, `unsweetened`, measured
sugar ingredients, glucose syrup, or glucose tablets is kept in the food route.
An unqualified phrase such as `sugar 120` is deliberately ambiguous and asks the
user whether they mean food or a glucose reading.

## Glucose value extraction

The glucose parser no longer takes the first numeric token. It extracts values
relative to a glucose marker or unit, so timing and food quantities cannot become
the reading. Hyphenated post-meal offsets are parsed independently.

Examples:

- `2-hour post-meal glucose 126` -> reading 126, offset 120 minutes;
- `blood sugar 128 after eating 2 eggs` -> reading 128;
- `tea without sugar, glucose 120` -> reading 120;
- `2 eggs and tea without sugar` -> food;
- `sugar 120` -> clarification.

## Dependency boundary

SwiftUI does not call either domain parser directly. `AppDependencies` injects
`ConversationInputRouting`, and `DayThreadView` acts only on the returned route.
Future conversation domains should extend this boundary rather than adding a new
opportunistic parser to the view.

## Verification

- 68 deterministic unit/integration tests passed with zero failures.
- The exact reported multi-food sentence passed through the simulator UI into
  food analysis and produced a `Mixed sprouts` component.
- `2-hour post-meal glucose 126` opened the glucose review with value `126`,
  Post-meal selected, and the two-hour offset retained.
- Food exclusions, food ingredients, glucose units, timing quantities, unrelated
  food quantities, and deliberately ambiguous sugar language have regression
  coverage.
