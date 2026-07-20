import SwiftUI

/// Composition lives at the app edge. Production can inject an authenticated
/// remote analysis service here; previews and offline builds remain local.
struct AppDependencies: Sendable {
    let photoAnalysis: PhotoAnalysisOrchestrator
    let mealVisuals: MealVisualGenerationService
    /// Food understanding is optional offline; production injects the
    /// authenticated backend implementation without changing SwiftUI views.
    let foodUnderstanding: (any FoodUnderstandingService)?
    let conversationInputRouter: any ConversationInputRouting
    let foodResolutionRouter: any FoodResolutionRouter
    let textMealAnalysis: HybridMealAnalysisCoordinator
    let normalisation: any FoodNormalisationService
    let nutritionResolution: any NutritionResolutionService
    let recipeCalculation: any RecipeCalculationService
    let clarification: any MealClarificationService
    let userFoodMemory: any UserFoodMemoryRepository
    let packagedFoods: any PackagedFoodRepository

    static let local = makeRuntime()

    private static func makeRuntime(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> AppDependencies {
        let catalog = IndianFoodCatalogService()
        let memory = InMemoryUserFoodMemoryRepository()
        let packaged = InMemoryPackagedFoodRepository()
        let normalisation = HybridFoodNormalisationService(catalog: catalog)
        let nutrition = HybridNutritionResolutionService(catalog: catalog, packaged: packaged)
        let localUnderstanding = LocalStructuredMealUnderstandingService(catalog: catalog)
        let backendConfiguration = arguments.contains("UITestMode")
            ? nil
            : RuntimeBackendConfiguration(environment: environment)
        let backendUnderstanding: BackendFoodUnderstandingService? = backendConfiguration.map {
            BackendFoodUnderstandingService(
                endpoint: $0.endpoint,
                tokenProvider: RuntimeBackendAccessTokenProvider(token: $0.accessToken)
            )
        }
        let understanding: any FoodUnderstandingService = backendUnderstanding ?? localUnderstanding
        let router = DefaultFoodResolutionRouter(
            catalog: catalog,
            normalisation: normalisation,
            understanding: backendUnderstanding,
            nutrition: nutrition,
            memory: memory
        )
        let coordinator = HybridMealAnalysisCoordinator(router: router)
        let photoRemote: (any FoodRecognitionService)? = backendUnderstanding.map {
            StructuredPhotoRecognitionService(understanding: $0, coordinator: coordinator)
        }

        return AppDependencies(
            photoAnalysis: PhotoAnalysisOrchestrator(
                remote: photoRemote,
                onDevice: AppleFoodImageClassificationService(catalog: catalog),
                local: LocalMealAnalysisEngine(catalog: catalog)
            ),
            mealVisuals: .local,
            foodUnderstanding: understanding,
            conversationInputRouter: DefaultConversationInputRouter(),
            foodResolutionRouter: router,
            textMealAnalysis: coordinator,
            normalisation: normalisation,
            nutritionResolution: nutrition,
            recipeCalculation: CatalogRecipeCalculationService(
                resolver: HybridNutritionResolutionService(catalog: catalog, packaged: packaged)
            ),
            clarification: DefaultMealClarificationService(),
            userFoodMemory: memory,
            packagedFoods: packaged
        )
    }
}

/// Development builds receive a backend URL and an app/account token through
/// Xcode launch environment variables. Production authentication can supply the
/// same typed client without embedding OpenAI or nutrition-provider credentials.
struct RuntimeBackendConfiguration: Sendable {
    let endpoint: URL
    let accessToken: String

    init?(environment: [String: String]) {
        guard let rawURL = environment["DIAFIT_BACKEND_URL"],
              let endpoint = URL(string: rawURL),
              let scheme = endpoint.scheme?.lowercased(),
              scheme == "https" || (scheme == "http" && ["127.0.0.1", "localhost"].contains(endpoint.host)),
              let token = environment["DIAFIT_BACKEND_ACCESS_TOKEN"]
                ?? environment["DIAFIT_DEVELOPMENT_TOKEN"],
              token.count >= 8 else { return nil }
        self.endpoint = endpoint
        self.accessToken = token
    }
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
