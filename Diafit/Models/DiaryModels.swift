import Foundation

struct Day: Identifiable, Codable, Hashable {
    let id: UUID
    let date: Date
    var messages: [ThreadItem]
    var energyGoal: Int
    var carbohydrateGoal: Int

    var meals: [Meal] {
        messages.compactMap { item in
            if case .meal(let meal) = item.kind { meal } else { nil }
        }
    }

    var totalEnergy: Int { meals.reduce(0) { $0 + $1.energy } }
    var totalCarbs: Int { meals.reduce(0) { $0 + $1.carbs } }
}

struct Meal: Identifiable, Codable, Hashable {
    enum Artwork: String, Codable, CaseIterable, Hashable {
        case bowl, toast, berry, pasta, green, neutral
    }

    let id: UUID
    var title: String
    var subtitle: String
    var mealType: String
    var time: Date
    var energy: Int
    var carbs: Int
    var protein: Int
    var fat: Int
    var artwork: Artwork
    var confidence: Confidence
    /// Present for meals that came through the explicit analysis-and-confirm flow.
    /// Legacy diary entries intentionally remain valid without it.
    var analysis: MealAnalysisResult? = nil
    /// This is independent from `artwork`: it records where the visual came
    /// from and which structured meal it belongs to.
    var visualIdentity: MealVisualIdentity? = nil

    enum Confidence: String, Codable, Hashable {
        case known = "Saved recipe"
        case estimated = "Estimated"
        case verified = "Verified"
    }
}

struct ThreadItem: Identifiable, Codable, Hashable {
    enum Kind: Codable, Hashable {
        case agent(text: String, tools: [String])
        case person(text: String)
        case meal(Meal)
        case mealAnalysis(MealAnalysisDraft)
        case checkpoint(GlucoseCheckpoint)
    }

    let id: UUID
    var kind: Kind
}

struct GlucoseCheckpoint: Identifiable, Codable, Hashable {
    let id: UUID
    let value: Int
    let unit: String
    let label: String
    let note: String
}
