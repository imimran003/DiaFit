import Foundation

struct Day: Identifiable, Hashable {
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

struct Meal: Identifiable, Hashable {
    enum Artwork: String, CaseIterable, Hashable {
        case bowl, toast, berry, pasta, green
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

    enum Confidence: String, Hashable {
        case known = "Saved recipe"
        case estimated = "Estimated"
        case verified = "Verified"
    }
}

struct ThreadItem: Identifiable, Hashable {
    enum Kind: Hashable {
        case agent(text: String, tools: [String])
        case person(text: String)
        case meal(Meal)
        case checkpoint(GlucoseCheckpoint)
    }

    let id: UUID
    let kind: Kind
}

struct GlucoseCheckpoint: Identifiable, Hashable {
    let id: UUID
    let value: Int
    let unit: String
    let label: String
    let note: String
}
