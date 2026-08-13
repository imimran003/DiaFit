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
    let dailyReviewReminder: any DailyReviewReminderScheduling

    static let local = makeRuntime()

    private static func makeRuntime(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> AppDependencies {
        let catalog = IndianFoodCatalogService()
        // UI tests and previews must stay isolated. Normal runtime uses
        // protected, versioned local repositories so confirmed aliases and
        // branded nutrition labels survive relaunches and app updates.
        let memory: any UserFoodMemoryRepository
        let packaged: any PackagedFoodRepository
        let usesEphemeralFoodMemory = arguments.contains("UITestMode")
            || environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        if usesEphemeralFoodMemory {
            memory = InMemoryUserFoodMemoryRepository()
            packaged = InMemoryPackagedFoodRepository()
        } else {
            memory = FileUserFoodMemoryRepository()
            packaged = FilePackagedFoodRepository()
        }
        let normalisation = HybridFoodNormalisationService(catalog: catalog)
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
        let verifiedNutrition: (any VerifiedNutritionProvider)? = backendConfiguration.map {
            BackendVerifiedNutritionProvider(
                endpoint: $0.endpoint,
                tokenProvider: RuntimeBackendAccessTokenProvider(token: $0.accessToken)
            )
        }
        let nutrition = HybridNutritionResolutionService(
            catalog: catalog,
            packaged: packaged,
            verifiedProvider: verifiedNutrition
        )
        let localUnderstanding = LocalStructuredMealUnderstandingService(catalog: catalog)
        let backendUnderstanding: BackendFoodUnderstandingService? = backendConfiguration.map {
            BackendFoodUnderstandingService(
                endpoint: $0.endpoint,
                tokenProvider: RuntimeBackendAccessTokenProvider(token: $0.accessToken)
            )
        }
        let mealVisuals: MealVisualGenerationService
        if let backendConfiguration {
            mealVisuals = MealVisualGenerationService(
                generator: BackendMealVisualGenerator(
                    endpoint: backendConfiguration.endpoint,
                    tokenProvider: RuntimeBackendAccessTokenProvider(token: backendConfiguration.accessToken)
                ),
                assets: .live(),
                ledger: MealVisualRuntime.ledger
            )
        } else {
            mealVisuals = .local
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
            // Cap hosted verification at three provider passes: primary
            // inventory, a focused dish/count audit when needed, and one
            // spatial review for genuinely sparse plates. This preserves the
            // quality gates while keeping a sleeping free-tier service from
            // consuming the entire end-to-end photo timeout.
            StructuredPhotoRecognitionService(
                understanding: $0,
                coordinator: coordinator,
                catalog: catalog,
                maximumProviderPasses: 3
            )
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
            mealVisuals: mealVisuals,
            foodUnderstanding: understanding,
            conversationInputRouter: DefaultConversationInputRouter(),
            foodResolutionRouter: router,
            textMealAnalysis: coordinator,
            normalisation: normalisation,
            nutritionResolution: nutrition,
            recipeCalculation: CatalogRecipeCalculationService(
                resolver: nutrition
            ),
            clarification: DefaultMealClarificationService(),
            userFoodMemory: memory,
            packagedFoods: packaged,
            healthActivity: healthActivity,
            dailyReviewReminder: LocalDailyReviewReminderScheduler()
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
              Self.isAllowed(endpoint),
              accessToken.count >= 8 else { return nil }
        self.endpoint = endpoint
        self.accessToken = accessToken
    }

    private static func isAllowed(_ endpoint: URL) -> Bool {
        guard let scheme = endpoint.scheme?.lowercased(),
              let host = endpoint.host?.lowercased() else { return false }
        if scheme == "https" { return true }
        guard scheme == "http" else { return false }
        if ["127.0.0.1", "localhost"].contains(host) { return true }
        #if DEBUG
        // A physical development device may use the authenticated backend on
        // the developer's Mac over the same private Bonjour network. Release
        // builds still require HTTPS.
        return host.hasSuffix(".local")
        #else
        return false
        #endif
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
        if let keychainCredential = loadKeychainCredential() {
            return RuntimeBackendConfiguration(rawURL: keychainCredential.url, accessToken: keychainCredential.token)
        }
        // The simulator test host can expose a temporarily unavailable
        // Keychain service even though the app container is healthy. Keep a
        // development-only, data-protected fallback so a configured photo-AI
        // endpoint is not silently forgotten on the next Home-screen launch.
        // Release builds never construct this store.
        guard let data = try? Data(contentsOf: fallbackURL),
              let credential = try? JSONDecoder().decode(Credential.self, from: data) else { return nil }
        return RuntimeBackendConfiguration(rawURL: credential.url, accessToken: credential.token)
    }

    private func loadKeychainCredential() -> Credential? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let credential = try? JSONDecoder().decode(Credential.self, from: data) else { return nil }
        return credential
    }

    func save(_ configuration: RuntimeBackendConfiguration) {
        let credential = Credential(url: configuration.endpoint.absoluteString, token: configuration.accessToken)
        guard let data = try? JSONEncoder().encode(credential) else { return }
        let attributes = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        guard updateStatus != errSecSuccess else { return }

        // `SecItemUpdate` can return a different failure than
        // `errSecItemNotFound` when the app is first launched in a simulator
        // or after a development entitlement changes. Treat every non-success
        // as an insert-or-replace path; otherwise a valid launch environment
        // is silently lost and the next Home-screen launch falls back to the
        // incomplete on-device photo classifier.
        var insertion = baseQuery
        insertion[kSecValueData as String] = data
        insertion[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(insertion as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            SecItemDelete(baseQuery as CFDictionary)
            _ = SecItemAdd(insertion as CFDictionary, nil)
        }

        // Verify the write. If the simulator or a development entitlement
        // prevents Keychain persistence, retain the same temporary credential
        // in a protected app-container file rather than making the next photo
        // analysis silently fall back to a single Vision label.
        if loadKeychainCredential() == nil {
            try? FileManager.default.createDirectory(
                at: fallbackDirectory,
                withIntermediateDirectories: true
            )
            try? data.write(to: fallbackURL, options: .completeFileProtection)
        } else {
            try? FileManager.default.removeItem(at: fallbackURL)
        }
    }

    func remove() {
        SecItemDelete(baseQuery as CFDictionary)
        try? FileManager.default.removeItem(at: fallbackURL)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "runtime-backend"
        ]
    }

    private var fallbackDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Diafit/Development", isDirectory: true)
    }

    private var fallbackURL: URL {
        let safeService = service.map { character in
            character.isLetter || character.isNumber || character == "." || character == "-" || character == "_"
                ? String(character)
                : "_"
        }.joined()
        return fallbackDirectory.appendingPathComponent("backend-\(safeService).json")
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
