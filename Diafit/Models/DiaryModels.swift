import Foundation

enum MealPeriod: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case breakfast
    case midMorningSnack
    case lunch
    case afternoonSnack
    case dinner
    case eveningSnack
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .breakfast: return "Breakfast"
        case .midMorningSnack: return "Mid-morning snack"
        case .lunch: return "Lunch"
        case .afternoonSnack: return "Afternoon snack"
        case .dinner: return "Dinner"
        case .eveningSnack: return "Evening snack"
        case .other: return "Other"
        }
    }

    var compactName: String {
        switch self {
        case .midMorningSnack: return "Mid-morning"
        case .afternoonSnack: return "Afternoon"
        case .eveningSnack: return "Evening"
        default: return displayName
        }
    }

    init(legacyLabel: String) {
        let normalized = legacyLabel
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
        if normalized.contains("breakfast") {
            self = .breakfast
        } else if normalized.contains("mid morning") || normalized.contains("morning snack") {
            self = .midMorningSnack
        } else if normalized.contains("lunch") {
            self = .lunch
        } else if normalized.contains("afternoon") {
            self = .afternoonSnack
        } else if normalized.contains("dinner") {
            self = .dinner
        } else if normalized.contains("evening") || normalized == "snack" {
            self = .eveningSnack
        } else {
            self = .other
        }
    }

    static func suggested(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> MealPeriod {
        switch calendar.component(.hour, from: date) {
        case 5..<10: return .breakfast
        case 10..<12: return .midMorningSnack
        case 12..<16: return .lunch
        case 16..<18: return .afternoonSnack
        case 18..<22: return .dinner
        case 22...23: return .eveningSnack
        default: return .other
        }
    }
}

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

    var glucoseReadings: [GlucoseReading] {
        messages.compactMap { item in
            if case .glucose(let reading) = item.kind { return reading }
            return nil
        }
        .sorted { $0.measuredAt < $1.measuredAt }
    }

    var latestFastingReading: GlucoseReading? {
        glucoseReadings.last { $0.type == .fasting }
    }

    var latestPostMealReading: GlucoseReading? {
        glucoseReadings.last { $0.type == .postMeal }
    }

    var totalEnergy: Int { meals.reduce(0) { $0 + $1.energy } }
    var totalCarbs: Int { meals.reduce(0) { $0 + $1.carbs } }
    var totalProtein: Int { meals.reduce(0) { $0 + $1.protein } }

    var fiberIntake: LoggedFiberIntake {
        let estimates = meals.map { meal -> (value: Double?, isComplete: Bool) in
            guard let analysis = meal.analysis else { return (nil, false) }
            let foods = analysis.detectedItems.filter { $0.category != .hydration }
            let allItemsKnown = foods.allSatisfy { item in
                item.nutrition.fibreGrams != nil || item.canonicalFoodId == "chai-with-milk"
            }
            // Older confirmed chai entries predate the catalog's explicit
            // zero. Only this ingredient-defined, fiber-free drink gets a
            // retroactive value; other missing nutrient data stays unknown.
            let savedChaiOnly = !foods.isEmpty
                && foods.allSatisfy { $0.canonicalFoodId == "chai-with-milk" }
            let value = analysis.mealTotals.fibreGrams ?? (savedChaiOnly ? 0 : nil)
            return (value, value != nil && allItemsKnown)
        }
        let known = estimates.compactMap { $0.value }
        return LoggedFiberIntake(
            knownGrams: known.reduce(0, +),
            hasEstimate: !known.isEmpty || meals.isEmpty,
            isComplete: estimates.allSatisfy { $0.isComplete }
        )
    }

    /// Meals saved by the structured review flow retain unavailable protein as
    /// `nil` in their analysis result. The headline can still show the sum of
    /// known values while callers keep that partial-data state available.
    var proteinTotalIsComplete: Bool {
        !meals.contains { meal in
            guard let analysis = meal.analysis else { return false }
            return analysis.mealTotals.proteinGrams == nil
        }
    }

    var proteinGoalStatus: ProteinGoalStatus {
        if totalProtein >= DailyProteinTarget.grams { return .met }
        return proteinTotalIsComplete ? .below : .incomplete
    }
}

enum DailyProteinTarget {
    static let grams = 100
}

enum ProteinGoalStatus: Equatable {
    case met
    case below
    case incomplete

    var accessibilityDescription: String {
        switch self {
        case .met: "100 gram daily protein goal met"
        case .below: "below the 100 gram daily protein goal"
        case .incomplete: "protein total is partial; some meal data is unavailable"
        }
    }
}

struct LoggedFiberIntake: Equatable {
    let knownGrams: Double
    let hasEstimate: Bool
    let isComplete: Bool

    func status(targetGrams: Int?) -> FiberGoalStatus {
        guard let targetGrams else { return .targetUnavailable }
        if hasEstimate && knownGrams >= Double(targetGrams) { return .met }
        return isComplete ? .below : .incomplete
    }
}

enum FiberGoalStatus: Equatable {
    case met
    case below
    case incomplete
    case targetUnavailable
}

enum DailyFiberTarget {
    /// U.S. dietary reference intake (adequate intake) for adult men.
    /// https://odphp.health.gov/sites/default/files/2019-09/14-Appendix-E-2.pdf
    static func gramsForMen(age: Int?) -> Int? {
        guard let age, age >= 19 else { return nil }
        return age >= 51 ? 30 : 38
    }
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

    /// `mealType` remains encoded for compatibility with every existing diary
    /// archive. New code uses this typed bridge, so old meals migrate without
    /// rewriting or losing member data.
    var period: MealPeriod {
        get { MealPeriod(legacyLabel: mealType) }
        set { mealType = newValue.displayName }
    }

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
        case glucose(GlucoseReading)
        case checkpoint(GlucoseCheckpoint)
    }

    let id: UUID
    var kind: Kind

    /// SwiftUI must receive a new view identity when a review draft is
    /// replaced by its confirmed meal. Keeping only the thread item's UUID
    /// lets a stateful review card survive that enum-case change, leaving the
    /// old editor on screen even though the diary has already been updated.
    /// The identity remains stable for ordinary edits and changes only at the
    /// semantic boundary between a draft and a saved item.
    var renderIdentity: String {
        switch kind {
        case .mealAnalysis(let draft):
            return "\(id.uuidString)-analysis-\(draft.id.uuidString)"
        case .meal(let meal):
            return "\(id.uuidString)-meal-\(meal.id.uuidString)"
        case .agent:
            return "\(id.uuidString)-agent"
        case .person:
            return "\(id.uuidString)-person"
        case .glucose(let reading):
            return "\(id.uuidString)-glucose-\(reading.id.uuidString)"
        case .checkpoint(let checkpoint):
            return "\(id.uuidString)-checkpoint-\(checkpoint.id.uuidString)"
        }
    }
}

struct GlucoseCheckpoint: Identifiable, Codable, Hashable {
    let id: UUID
    let value: Int
    let unit: String
    let label: String
    let note: String
}
