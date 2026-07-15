import Foundation

// MARK: - Analysis contract

/// A server or on-device recognizer may propose an analysis, but this object is
/// always a hypothesis until the member explicitly confirms it.
struct MealAnalysisResult: Identifiable, Codable, Hashable, Sendable {
    let analysisId: UUID
    var imageReference: MealImageReference
    var imageType: MealImageType
    var detectedItems: [DetectedFoodItem]
    var mealTotals: NutritionValues
    var overallConfidence: ConfidenceLevel
    var assumptions: [String]
    var clarificationQuestions: [ClarificationQuestion]
    var warnings: [String]
    let createdAt: Date
    var recognitionModelVersion: String?
    var nutritionDatabaseVersion: String?
    var glycaemicDatabaseVersion: String?
    var nutritionProvenance: NutritionProvenance
    /// `mealTotals` holds only values approved for display and saving. The raw
    /// provider proposal stays in this report when validation blocks it.
    var nutritionValidation: NutritionValidationReport? = nil
    /// A structured visual request is created as soon as the food pipeline has
    /// enough canonical information. It is intentionally independent of a live
    /// image provider so the app can show a truthful deterministic fallback.
    var visualRequest: MealVisualRequest? = nil

    var id: UUID { analysisId }

    var hasUnsupportedNutrition: Bool {
        nutritionProvenance.kind == .unavailable || mealTotals.isEmpty
    }
}

struct MealImageReference: Codable, Hashable, Sendable {
    /// Never an authentication token or a raw image payload.
    let identifier: String
    let retention: ImageRetention

    static func transient() -> MealImageReference {
        MealImageReference(identifier: "local-" + UUID().uuidString, retention: .sessionOnly)
    }
}

enum MealImageType: String, Codable, Hashable, Sendable {
    case originalPhoto
    case generatedEditorial
    case noImage
}

enum ImageRetention: String, Codable, Hashable, Sendable {
    case sessionOnly
    case memberPermitted
    case deleted
}

enum ConfidenceLevel: String, Codable, CaseIterable, Hashable, Sendable {
    case high
    case medium
    case low
    case unknown

    var displayName: String {
        switch self {
        case .high: return "High confidence"
        case .medium: return "Likely"
        case .low: return "Needs confirmation"
        case .unknown: return "Unknown"
        }
    }
}

struct DetectedFoodItem: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var canonicalFoodId: String
    var displayName: String
    var regionalName: String?
    var category: FoodCategory
    var confidence: ConfidenceLevel
    var alternatives: [AlternativeFoodMatch]
    var quantity: Double
    var servingUnit: ServingUnit
    var estimatedWeightGrams: Double?
    var visibleIngredients: [String]
    var inferredIngredients: [String]
    var possibleIngredients: [String]
    var preparationMethod: String?
    var nutrition: NutritionValues
    var glycaemicInformation: GlycaemicInformation
    var assumptions: [String]
    var warnings: [String]
    var boundingRegion: NormalizedBoundingRegion?
    var nutritionProvenance: NutritionProvenance
    var rawNutrition: NutritionValues? = nil
    var nutritionValidation: NutritionValidationReport? = nil
    /// The alias and parsing confidence make a local estimate inspectable
    /// without retaining the member's entire raw food note on the meal.
    var matchedAlias: String? = nil
    var confidenceScore: Double = 0
    var modifiers: [String] = []
    var supplementProfile: SupplementProductProfile? = nil
}

struct AlternativeFoodMatch: Codable, Hashable, Sendable, Identifiable {
    let canonicalFoodId: String
    let displayName: String
    let confidence: ConfidenceLevel

    var id: String { canonicalFoodId }
}

enum FoodCategory: String, Codable, CaseIterable, Hashable, Sendable {
    case bread
    case rice
    case lentilOrLegume
    case vegetarianCurry
    case nonVegetarian
    case breakfastOrSnack
    case dairyOrSide
    case dessertOrDrink
    case fruitOrVegetable
    case egg
    case sprouts
    case supplement
    case unknown
}

enum DietaryClassification: String, Codable, Hashable, Sendable {
    case vegetarian
    case vegan
    case containsEgg
    case pescatarian
    case nonVegetarian
    case unknown
}

enum ServingUnit: String, Codable, CaseIterable, Hashable, Sendable {
    case grams
    case millilitres
    case teaspoon
    case tablespoon
    case katori
    case smallBowl
    case mediumBowl
    case largeBowl
    case cup
    case ladle
    case piece
    case roti
    case naan
    case paratha
    case poori
    case bhatura
    case dosa
    case idli
    case vada
    case slice
    case glass
    case plate
    case serving
    case wholeEgg
    case scoop

    var singularDisplayName: String {
        switch self {
        case .smallBowl: return "small bowl"
        case .mediumBowl: return "medium bowl"
        case .largeBowl: return "large bowl"
        case .wholeEgg: return "whole egg"
        default: return rawValue
        }
    }
}

struct NormalizedBoundingRegion: Codable, Hashable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

// MARK: - Nutrients and glycaemic evidence

/// Every nutrient is optional. Nil means the source could not support a value,
/// not zero. This distinction is deliberately carried all the way to the UI.
struct NutritionValues: Codable, Hashable, Sendable {
    var caloriesKcal: Double?
    var proteinGrams: Double?
    var carbohydrateGrams: Double?
    var availableCarbohydrateGrams: Double?
    var fatGrams: Double?
    var saturatedFatGrams: Double?
    var fibreGrams: Double?
    var totalSugarGrams: Double?
    var addedSugarGrams: Double?
    var sodiumMilligrams: Double?
    var cholesterolMilligrams: Double?

    static let unavailable = NutritionValues()

    init(
        caloriesKcal: Double? = nil,
        proteinGrams: Double? = nil,
        carbohydrateGrams: Double? = nil,
        availableCarbohydrateGrams: Double? = nil,
        fatGrams: Double? = nil,
        saturatedFatGrams: Double? = nil,
        fibreGrams: Double? = nil,
        totalSugarGrams: Double? = nil,
        addedSugarGrams: Double? = nil,
        sodiumMilligrams: Double? = nil,
        cholesterolMilligrams: Double? = nil
    ) {
        self.caloriesKcal = caloriesKcal
        self.proteinGrams = proteinGrams
        self.carbohydrateGrams = carbohydrateGrams
        self.availableCarbohydrateGrams = availableCarbohydrateGrams
        self.fatGrams = fatGrams
        self.saturatedFatGrams = saturatedFatGrams
        self.fibreGrams = fibreGrams
        self.totalSugarGrams = totalSugarGrams
        self.addedSugarGrams = addedSugarGrams
        self.sodiumMilligrams = sodiumMilligrams
        self.cholesterolMilligrams = cholesterolMilligrams
    }

    var isEmpty: Bool {
        caloriesKcal == nil && proteinGrams == nil && carbohydrateGrams == nil && fatGrams == nil && fibreGrams == nil
    }

    func scaled(by multiplier: Double) -> NutritionValues {
        NutritionValues(
            caloriesKcal: caloriesKcal.map { $0 * multiplier },
            proteinGrams: proteinGrams.map { $0 * multiplier },
            carbohydrateGrams: carbohydrateGrams.map { $0 * multiplier },
            availableCarbohydrateGrams: availableCarbohydrateGrams.map { $0 * multiplier },
            fatGrams: fatGrams.map { $0 * multiplier },
            saturatedFatGrams: saturatedFatGrams.map { $0 * multiplier },
            fibreGrams: fibreGrams.map { $0 * multiplier },
            totalSugarGrams: totalSugarGrams.map { $0 * multiplier },
            addedSugarGrams: addedSugarGrams.map { $0 * multiplier },
            sodiumMilligrams: sodiumMilligrams.map { $0 * multiplier },
            cholesterolMilligrams: cholesterolMilligrams.map { $0 * multiplier }
        )
    }

    static func total(of values: [NutritionValues]) -> NutritionValues {
        func total(_ keyPath: KeyPath<NutritionValues, Double?>) -> Double? {
            let known = values.compactMap { $0[keyPath: keyPath] }
            return known.isEmpty ? nil : known.reduce(0, +)
        }

        return NutritionValues(
            caloriesKcal: total(\.caloriesKcal),
            proteinGrams: total(\.proteinGrams),
            carbohydrateGrams: total(\.carbohydrateGrams),
            availableCarbohydrateGrams: total(\.availableCarbohydrateGrams),
            fatGrams: total(\.fatGrams),
            saturatedFatGrams: total(\.saturatedFatGrams),
            fibreGrams: total(\.fibreGrams),
            totalSugarGrams: total(\.totalSugarGrams),
            addedSugarGrams: total(\.addedSugarGrams),
            sodiumMilligrams: total(\.sodiumMilligrams),
            cholesterolMilligrams: total(\.cholesterolMilligrams)
        )
    }
}

struct NutritionProvenance: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Hashable, Sendable {
        case verifiedDatabase
        case curatedRecipeEstimate
        case packagedLabel
        case userCreated
        case modelFallback
        case unavailable
    }

    var kind: Kind
    var dataSource: String
    var dataVersion: String?
    var confidence: ConfidenceLevel

    static let unavailable = NutritionProvenance(
        kind: .unavailable,
        dataSource: "No supported nutrition source",
        dataVersion: nil,
        confidence: .unknown
    )
}

enum SupplementBase: String, Codable, CaseIterable, Hashable, Sendable {
    case water
    case milk
    case unspecified

    var displayName: String {
        switch self {
        case .water: return "water"
        case .milk: return "milk"
        case .unspecified: return "base not specified"
        }
    }
}

/// Packaged supplements are represented as products, never as restaurant
/// recipes. A saved account-level product can replace this generic profile in a
/// future provider without changing the analysis or review contracts.
struct SupplementProductProfile: Codable, Hashable, Sendable {
    var brand: String?
    var productName: String
    var barcode: String?
    var flavour: String?
    var servingSizeGrams: Double
    var servingUnit: ServingUnit
    var gramsPerScoop: Double?
    var base: SupplementBase
    var source: String
    var sourceVersion: String?
    var isUserConfirmed: Bool
}

struct GlycaemicInformation: Codable, Hashable, Sendable {
    var glycaemicIndex: Double?
    var glycaemicIndexSource: String?
    var glycaemicLoad: Double?
    var confidence: ConfidenceLevel
    var unavailableReason: String?

    static let unavailable = GlycaemicInformation(
        glycaemicIndex: nil,
        glycaemicIndexSource: nil,
        glycaemicLoad: nil,
        confidence: .unknown,
        unavailableReason: "Not available for this preparation"
    )

    /// GL is valid only when both a sourced GI and available carbohydrate are present.
    static func calculate(index: Double?, source: String?, availableCarbohydrate: Double?) -> GlycaemicInformation {
        guard let index, let source, let availableCarbohydrate else { return .unavailable }
        return GlycaemicInformation(
            glycaemicIndex: index,
            glycaemicIndexSource: source,
            glycaemicLoad: index * availableCarbohydrate / 100,
            confidence: .medium,
            unavailableReason: nil
        )
    }
}

// MARK: - Member review

struct ClarificationQuestion: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var relatedFoodItemId: UUID?
    var question: String
    var answerType: ClarificationAnswerType
    var options: [String]
    var impactLevel: ClarificationImpact
    var answer: String?
}

enum ClarificationAnswerType: String, Codable, Hashable, Sendable {
    case singleChoice
    case quantity
    case freeText
    case yesNo
}

enum ClarificationImpact: String, Codable, Hashable, Sendable {
    case high
    case medium
    case low
}

struct MealAnalysisDraft: Identifiable, Codable, Hashable {
    let id: UUID
    var result: MealAnalysisResult
    /// Kept only while the review sheet is onscreen unless a member explicitly opts in to retention.
    var transientImageData: Data?
    var state: State

    enum State: Codable, Hashable {
        case preparing
        case ready
        case failed(message: String)
    }

    init(result: MealAnalysisResult, transientImageData: Data? = nil, state: State = .ready) {
        self.id = result.analysisId
        self.result = result
        self.transientImageData = transientImageData
        self.state = state
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case result
        case state
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        result = try container.decode(MealAnalysisResult.self, forKey: .result)
        state = try container.decodeIfPresent(State.self, forKey: .state) ?? .ready
        // Raw member photos are deliberately session-only. A restored draft
        // retains its structured analysis but never silently persists bytes.
        transientImageData = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(result, forKey: .result)
        try container.encode(state, forKey: .state)
    }
}

// MARK: - Catalog records

struct IndianFoodDefinition: Codable, Hashable, Sendable, Identifiable {
    let canonicalId: String
    let canonicalName: String
    let regionalNames: [String]
    let englishName: String
    let transliterations: [String]
    let aliases: [String]
    let category: FoodCategory
    let dietaryClassification: DietaryClassification
    let commonIngredients: [String]
    let possibleAllergens: [String]
    let commonPreparationMethods: [String]
    let nutritionPer100Grams: NutritionValues?
    let standardServing: StandardServing?
    let glycaemicIndex: Double?
    let glycaemicIndexSource: String?
    let dataSource: String?
    let dataVersion: String?
    let confidence: ConfidenceLevel
    let revision: String?

    var id: String { canonicalId }
}

struct StandardServing: Codable, Hashable, Sendable {
    let quantity: Double
    let unit: ServingUnit
    let grams: Double?
}
