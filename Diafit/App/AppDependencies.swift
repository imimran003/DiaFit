import SwiftUI
import Security

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
    let healthActivity: any HealthActivityProviding

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
        let backendConfiguration: RuntimeBackendConfiguration?
        if arguments.contains("UITestMode") {
            backendConfiguration = nil
        } else {
            #if DEBUG
            backendConfiguration = RuntimeBackendConfigurationResolver(
                store: DevelopmentBackendConfigurationStore()
            ).resolve(environment: environment)
            #else
            backendConfiguration = RuntimeBackendConfiguration(environment: environment)
            #endif
        }
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
        let healthActivity: any HealthActivityProviding
        #if DEBUG
        if arguments.contains("UITestHealthActivityFixture") {
            healthActivity = FixtureHealthActivityService.connected
        } else if arguments.contains("UITestMode") {
            healthActivity = FixtureHealthActivityService.disconnected
        } else {
            healthActivity = HealthKitActivityService()
        }
        #else
        healthActivity = HealthKitActivityService()
        #endif

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
            packagedFoods: packaged,
            healthActivity: healthActivity
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
              let token = environment["DIAFIT_BACKEND_ACCESS_TOKEN"]
                ?? environment["DIAFIT_DEVELOPMENT_TOKEN"] else { return nil }
        self.init(rawURL: rawURL, accessToken: token)
    }

    init?(rawURL: String, accessToken: String) {
        guard let endpoint = URL(string: rawURL),
              let scheme = endpoint.scheme?.lowercased(),
              scheme == "https" || (scheme == "http" && ["127.0.0.1", "localhost"].contains(endpoint.host)),
              accessToken.count >= 8 else { return nil }
        self.endpoint = endpoint
        self.accessToken = accessToken
    }
}

#if DEBUG
protocol RuntimeBackendConfigurationStoring: Sendable {
    func load() -> RuntimeBackendConfiguration?
    func save(_ configuration: RuntimeBackendConfiguration)
}

/// Debug device builds may be launched again from the Home Screen, where
/// Xcode's process environment no longer exists. Persist only the temporary
/// app-to-backend credential in Keychain; the Gemini provider key remains on
/// the Mac backend and never enters the app.
struct DevelopmentBackendConfigurationStore: RuntimeBackendConfigurationStoring, Sendable {
    let service: String

    init(service: String = "com.imranahmad.diafit.development-backend") {
        self.service = service
    }

    func load() -> RuntimeBackendConfiguration? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let credential = try? JSONDecoder().decode(Credential.self, from: data) else { return nil }
        return RuntimeBackendConfiguration(rawURL: credential.url, accessToken: credential.token)
    }

    func save(_ configuration: RuntimeBackendConfiguration) {
        let credential = Credential(url: configuration.endpoint.absoluteString, token: configuration.accessToken)
        guard let data = try? JSONEncoder().encode(credential) else { return }
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insertion = baseQuery
            insertion[kSecValueData as String] = data
            insertion[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(insertion as CFDictionary, nil)
        }
    }

    func remove() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "runtime-backend"
        ]
    }

    private struct Credential: Codable {
        let url: String
        let token: String
    }
}

struct RuntimeBackendConfigurationResolver: Sendable {
    let store: any RuntimeBackendConfigurationStoring

    func resolve(environment: [String: String]) -> RuntimeBackendConfiguration? {
        if let configured = RuntimeBackendConfiguration(environment: environment) {
            store.save(configured)
            FoodLoggingDiagnostics.record("backend.configuration", fields: ["source": "launch-environment"])
            return configured
        }
        let stored = store.load()
        FoodLoggingDiagnostics.record("backend.configuration", fields: [
            "source": stored == nil ? "unavailable" : "keychain"
        ])
        return stored
    }
}
#endif

private struct AppDependenciesKey: EnvironmentKey {
    static let defaultValue = AppDependencies.local
}

extension EnvironmentValues {
    var appDependencies: AppDependencies {
        get { self[AppDependenciesKey.self] }
        set { self[AppDependenciesKey.self] = newValue }
    }
}
