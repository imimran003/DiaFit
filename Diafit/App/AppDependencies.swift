import SwiftUI

/// Composition lives at the app edge. Production can inject an authenticated
/// remote analysis service here; previews and offline builds remain local.
struct AppDependencies: Sendable {
    let photoAnalysis: PhotoAnalysisOrchestrator
    let mealVisuals: MealVisualGenerationService
    /// Food understanding is optional offline; production injects the
    /// authenticated backend implementation without changing SwiftUI views.
    let foodUnderstanding: (any FoodUnderstandingService)?
    let foodResolutionRouter: any FoodResolutionRouter
    let textMealAnalysis: HybridMealAnalysisCoordinator
    let normalisation: any FoodNormalisationService
    let nutritionResolution: any NutritionResolutionService
    let recipeCalculation: any RecipeCalculationService
    let clarification: any MealClarificationService
    let userFoodMemory: any UserFoodMemoryRepository
    let packagedFoods: any PackagedFoodRepository

    static let local = AppDependencies(
        photoAnalysis: PhotoAnalysisOrchestrator(),
        mealVisuals: .local,
        foodUnderstanding: nil,
        foodResolutionRouter: DefaultFoodResolutionRouter(),
        textMealAnalysis: HybridMealAnalysisCoordinator(),
        normalisation: HybridFoodNormalisationService(),
        nutritionResolution: HybridNutritionResolutionService(),
        recipeCalculation: CatalogRecipeCalculationService(),
        clarification: DefaultMealClarificationService(),
        userFoodMemory: InMemoryUserFoodMemoryRepository(),
        packagedFoods: InMemoryPackagedFoodRepository()
    )
}

private struct AppDependenciesKey: EnvironmentKey {
    static let defaultValue = AppDependencies.local
}

extension EnvironmentValues {
    var appDependencies: AppDependencies {
        get { self[AppDependenciesKey.self] }
        set { self[AppDependenciesKey.self] = newValue }
    }
}
