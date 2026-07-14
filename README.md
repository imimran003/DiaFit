# Diafit

Diafit is a deliberately quiet calorie and carbohydrate companion for people managing diabetes. The prototype treats the food log as a day-by-day conversation, then lets the same meals expand into an image-led atlas.

## Run

Open `Diafit.xcodeproj`, select an iOS Simulator, and run the **Diafit** scheme. The project has no third-party dependencies and targets iOS 17 or later. The **DiafitUnitTests** scheme compiles the food-analysis tests independently of the UI tests.

## Product notes

- The sample experience is fully local by default and intentionally does not make medical decisions. Photo selection creates an editable estimate and does not upload or retain the original photo in the default configuration.
- The bundled Indian-food catalog normalizes regional aliases and labels partial recipe values as estimates. Missing nutrition and glycaemic values stay unavailable.
- The `Backend` directory contains a strict, runnable development contract and fixture provider. It has no real provider credentials; production must connect an authenticated server-side vision and nutrition provider.
- Food art uses consistent local studio cutouts only for known sample meals. Analysed free-text meals use a component-labelled neutral visual until a verified image service is configured; an unrelated food is never used as a fallback.

Further decision records live in [Docs/Intent.md](Docs/Intent.md), [Docs/IndianFoodAnalysisPlan.md](Docs/IndianFoodAnalysisPlan.md), [Docs/PhotoAnalysisArchitecture.md](Docs/PhotoAnalysisArchitecture.md), and [Docs/CorrectnessAudit.md](Docs/CorrectnessAudit.md).
