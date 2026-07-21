# Hybrid food understanding architecture

The app previously ran free text through `LocalMealAnalysisEngine`, which
scanned `IndianFoodCatalog.json` for exact aliases and immediately scaled the
first local nutrition record. This made the catalog an accidental recognition
boundary: unknown dishes, spelling variants, branded products and recipes could
become an empty draft or an unrelated fallback.

The catalog remains valuable, but it is now one layer in a provider-independent
pipeline:

```text
text/photo -> backend structured meal parse -> canonical match -> nutrition
provider hierarchy -> recipe calculation (when needed) -> validation -> review
-> confirmation -> memory/persistence
```

## Boundaries

* `FoodUnderstandingService` returns `MealParseResult` and `ParsedFoodItem`.
  `BackendFoodUnderstandingService` sends an account token to the backend;
  OpenAI credentials never ship in the iOS target. The parse contract carries
  quantities, preparation, additions, products and confidence, but no trusted
  nutrition values. For photographed packages, `PackagedLabelEvidence`
  contains only clearly visible printed values. A separate
  `AINutritionEstimate` may fill otherwise missing package nutrients when the
  product identity is sufficiently clear. It remains editable, explicitly
  model-derived, and can never override printed evidence or masquerade as a
  verified label.
* AI package estimates must include core energy and macros, state their serving
  assumptions, use finite non-negative values, and pass backend and iOS
  energy-plausibility validation before display.
* `FoodNormalisationService` remains the local catalog seam. The hybrid
  implementation first uses exact canonical aliases, then tolerant token
  matching over aliases, regional names and transliterations. The bundled
  Indian catalog is therefore a canonical alias/verified fallback layer, not a
  complete list of all foods.
* `NutritionResolutionService` separates product labels and verified provider
  records from local curated fallback. Every result carries source, record ID,
  serving amount/unit, grams, assumptions and verification state. Its injected
  provider seams follow the order confirmed label → verified database → local
  canonical record → ingredient calculation → explicitly labelled model
  estimate. Every candidate passes `NutritionValidationService`; rejected
  values become unavailable with a review reason rather than silently reaching
  diary totals.
* `RecipeCalculationService` calculates a dish from independently resolved
  ingredients; the language model may propose ingredients, but does not supply
  their nutrition.
* `NutritionValidationService` is the central gate already used by the local
  engine. It rejects invalid numbers, serving confusion, implausible beverage,
  egg and whey values before totals can be persisted.
* `UserFoodMemoryRepository` and `PackagedFoodRepository` are injected actor
  seams. Confirmed aliases, servings and branded products can be ranked on the
  next parse without retraining a model or storing provider secrets.
* `MealClarificationService` emits only material questions (for example whey
  scoop/base or a high-impact recipe oil amount), leaving low-impact spices out.

The in-memory repositories are deterministic development implementations. A
production account repository should persist the same records behind the
protocol and retain only user-confirmed preferences.

## Completeness gate

`FoodResolutionCompletenessEvaluator` is the non-negotiable boundary between
recognition and a review-ready meal. A canonical ID, display name, quantity, or
serving label alone is not success. Each component must have a valid serving
conversion, calories, carbohydrates, protein, traceable provenance, and a
passing validation report. If a local candidate fails that gate,
`DefaultFoodResolutionRouter` automatically attempts the structured backend
parser before returning a result. If the backend is unavailable, the router
uses an explicitly labelled curated ingredient/category fallback for common
foods; it never forwards a blank nutrition object as a successful resolution.
The lifecycle is exposed through `FoodResolutionState`, including
`requiresAIInterpretation`, `callingBackend`, `calculatingRecipe`,
`clarificationRequired`, `readyForReview`, and explicit unavailable failures.
The local simulator composition uses `LocalStructuredMealUnderstandingService`
when no authenticated backend client is configured, so the same interpretation
stage is still exercised offline; production replaces that adapter with
`BackendFoodUnderstandingService`.

## Deterministic routing additions

`DefaultFoodResolutionRouter` is the application-facing seam for text food
resolution. It checks confirmed memory, exact/local span matches, alias and
transliteration matches, conservative fuzzy matches, then the backend
`FoodUnderstandingService`. Water and volume expressions are handled by the
catalog fast path without an AI request. The router returns separate
interpretation and nutrition routes, so diagnostics can distinguish an AI
interpretation from a curated nutrition fallback.

The local catalog now includes canonical hydration and transliterated rice and
kadhi records. `kadhi chaawal` therefore remains two components, while
`500 ml water` remains one hydration component with a 500 mL serving and zero
calories. Confirming a draft writes canonical identity, serving, preparation,
and product information to the injected user-food memory repository.

## Photographed packaged foods

A package photo is not treated as an ordinary plated recipe. Structured vision
returns product identity, brand/flavour when legible, a count such as one
package, and optional printed-label evidence with a declared basis (per package,
per serving, per 100 grams, or front-of-pack claim). Backend validation rejects
negative, non-finite, malformed, or unsupported evidence before it reaches the
app.

User-confirmed saved products still have priority. For an unknown package, a
valid printed value overrides only that same nutrient in an editable category
fallback. For example, a visible `24.6 g protein` claim preserves 24.6 g protein
but does not cause the model to invent calories or carbohydrate. The review
explains which values came from the visible package, which remain estimated,
and asks for a nutrition-panel photo when complete values are needed. Package,
pot, tub, and container units normalize to one editable serving rather than
causing the recognized product to disappear.
