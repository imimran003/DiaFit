import SwiftUI

/// Composition lives at the app edge. Production can inject an authenticated
/// remote analysis service here; previews and offline builds remain local.
struct AppDependencies: Sendable {
    let photoAnalysis: PhotoAnalysisOrchestrator
    let mealVisuals: MealVisualGenerationService

    static let local = AppDependencies(
        photoAnalysis: PhotoAnalysisOrchestrator(),
        mealVisuals: .local
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
