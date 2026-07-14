# Diafit

Diafit is a deliberately quiet calorie and carbohydrate companion for people managing diabetes. The prototype treats the food log as a day-by-day conversation, then lets the same meals expand into an image-led atlas.

## Run

Open `Diafit.xcodeproj`, select an iOS Simulator, and run the **Diafit** scheme. The project has no third-party dependencies and targets iOS 17 or later.

## Product notes

- The sample experience is fully local and intentionally does not make medical decisions. Nutrition and glucose values are illustrative.
- `NutritionService` and `FoodImageRendering` are clear integration seams for a backend. Keep API keys and health data off-device only behind an authenticated service.
- The art direction is code-drawn in this prototype because the current image-generation service was unavailable during creation. It is structured so generated images can replace the art without changing the UI.

Further decision records live in [Docs/Intent.md](Docs/Intent.md).
