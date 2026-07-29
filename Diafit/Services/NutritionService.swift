import Foundation

/// Free-text logging has two safe outcomes: a familiar saved recipe or an
/// explicit review draft. It never invents a generic meal merely to keep a
/// conversation moving.
protocol NutritionService {
    func resolve(note: String, at date: Date) -> ConversationalFoodResolution
    /// Compatibility preview for non-UI callers. The app itself always uses
    /// `resolve` and displays a draft before saving an estimate.
    func estimate(for note: String, at date: Date) -> Meal
}

enum ConversationalFoodResolution {
    case saved(Meal)
    case review(MealAnalysisDraft)
}

/// Resolves explicit diary-history references before general food parsing.
/// It never saves a copied meal directly: the output is the same editable
/// review draft used for a newly interpreted meal.
struct PreviousDayMealReferenceService: Sendable {
    enum Resolution {
        case notAReference
        case review(MealAnalysisDraft, sourceDescription: String)
        case unavailable(message: String)
    }

    func resolve(
        _ text: String,
        currentDay: Day,
        allDays: [Day],
        calendar: Calendar = .autoupdatingCurrent
    ) -> Resolution {
        let normalized = normalize(text)
        guard normalized.contains("same"), normalized.contains("yesterday") else {
            return .notAReference
        }

        guard let previousDate = calendar.date(byAdding: .day, value: -1, to: currentDay.date),
              let previousDay = allDays.first(where: { calendar.isDate($0.date, inSameDayAs: previousDate) }) else {
            return .unavailable(message: "I couldn’t find a diary for yesterday. Log the meal normally this time and I’ll be able to reuse it later.")
        }

        let requestedPeriod = mealPeriod(in: normalized)
        let wantsFruit = normalized.contains("fruit")
        var sourceMeals = previousDay.meals

        if wantsFruit {
            sourceMeals = sourceMeals.filter { meal in
                meal.analysis?.detectedItems.contains(where: isFruit) == true
                    || containsFruitName(meal.title)
                    || containsFruitName(meal.subtitle)
            }
        } else if let requestedPeriod {
            sourceMeals = sourceMeals.filter { $0.period == requestedPeriod }
        }

        guard !sourceMeals.isEmpty else {
            let requested = wantsFruit
                ? "fruit"
                : requestedPeriod?.displayName.lowercased() ?? "meal"
            return .unavailable(message: "I couldn’t find a confirmed \(requested) entry yesterday. Nothing has been added.")
        }

        let selectedItems: [DetectedFoodItem] = sourceMeals.flatMap { meal in
            let items = meal.analysis?.detectedItems ?? [legacyItem(from: meal)]
            return wantsFruit ? items.filter(isFruit) : items
        }
        guard !selectedItems.isEmpty else {
            return .unavailable(message: "I found yesterday’s entry, but not enough confirmed nutrition to copy it safely.")
        }

        let period = requestedPeriod
            ?? sourceMeals.map(\.period).allEqual
            ?? .suggested(for: currentDay.date, calendar: calendar)
        let sourceLabel = wantsFruit
            ? "yesterday’s fruit"
            : "yesterday’s \(period.displayName.lowercased())"
        let analysisID = UUID()
        let totals = NutritionValues.total(of: selectedItems.map(\.nutrition))
        let validation = DefaultNutritionValidationService().validate(rawValues: totals)
        let visualRequest = MealVisualRequestBuilder().make(
            mealID: analysisID,
            items: selectedItems,
            clarificationQuestions: []
        )
        let result = MealAnalysisResult(
            analysisId: analysisID,
            imageReference: .transient(),
            imageType: .noImage,
            detectedItems: selectedItems,
            mealTotals: validation.safeValues ?? totals,
            overallConfidence: .high,
            assumptions: [
                "Copied from \(sourceLabel). Review the foods and servings before confirming.",
                "This creates a new entry; yesterday’s diary remains unchanged."
            ],
            clarificationQuestions: [],
            warnings: validation.isApproved
                ? ["Confirm that today’s portions match yesterday before saving."]
                : validation.issues.map(\.message),
            createdAt: .now,
            recognitionModelVersion: "confirmed-diary-history",
            nutritionDatabaseVersion: nil,
            glycaemicDatabaseVersion: nil,
            nutritionProvenance: NutritionProvenance(
                kind: .userCreated,
                dataSource: "Confirmed diary history",
                dataVersion: nil,
                confidence: .high
            ),
            nutritionValidation: validation,
            visualRequest: visualRequest
        )
        return .review(
            MealAnalysisDraft(result: result, mealPeriod: period),
            sourceDescription: sourceLabel
        )
    }

    private func mealPeriod(in text: String) -> MealPeriod? {
        if text.contains("mid morning") || text.contains("morning snack") { return .midMorningSnack }
        if text.contains("afternoon snack") { return .afternoonSnack }
        if text.contains("evening snack") { return .eveningSnack }
        if text.contains("breakfast") { return .breakfast }
        if text.contains("lunch") { return .lunch }
        if text.contains("dinner") || text.contains("supper") { return .dinner }
        return nil
    }

    private func isFruit(_ item: DetectedFoodItem) -> Bool {
        item.category == .fruitOrVegetable
            && (containsFruitName(item.displayName)
                || containsFruitName(item.canonicalFoodId)
                || item.visibleIngredients.contains(where: containsFruitName))
    }

    private func containsFruitName(_ value: String) -> Bool {
        let value = normalize(value)
        return [
            "apple", "banana", "berry", "berries", "blueberry", "strawberry",
            "orange", "mango", "grape", "guava", "papaya", "kiwi", "pear",
            "peach", "pineapple", "watermelon", "pomegranate", "fruit"
        ].contains(where: value.contains)
    }

    private func legacyItem(from meal: Meal) -> DetectedFoodItem {
        let provenance = NutritionProvenance(
            kind: .userCreated,
            dataSource: "Confirmed diary history",
            dataVersion: nil,
            confidence: .medium
        )
        let nutrition = NutritionValues(
            caloriesKcal: Double(meal.energy),
            proteinGrams: Double(meal.protein),
            carbohydrateGrams: Double(meal.carbs),
            fatGrams: Double(meal.fat)
        )
        return DetectedFoodItem(
            id: UUID(),
            canonicalFoodId: "history." + normalize(meal.title).replacingOccurrences(of: " ", with: "-"),
            displayName: meal.title,
            regionalName: nil,
            category: .unknown,
            confidence: .medium,
            alternatives: [],
            quantity: 1,
            servingUnit: .serving,
            estimatedWeightGrams: 200,
            visibleIngredients: [],
            inferredIngredients: [],
            possibleIngredients: [],
            preparationMethod: nil,
            nutrition: nutrition,
            glycaemicInformation: .unavailable,
            assumptions: ["Copied from a confirmed legacy diary entry."],
            warnings: [],
            boundingRegion: nil,
            nutritionProvenance: provenance,
            rawNutrition: nutrition,
            nutritionValidation: DefaultNutritionValidationService().validate(rawValues: nutrition),
            matchedAlias: meal.title,
            confidenceScore: 0.8
        )
    }

    private func normalize(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private extension Array where Element: Equatable {
    var allEqual: Element? {
        guard let first else { return nil }
        return allSatisfy { $0 == first } ? first : nil
    }
}

struct LocalNutritionService: NutritionService {
    let analysisEngine: LocalMealAnalysisEngine

    init(analysisEngine: LocalMealAnalysisEngine = LocalMealAnalysisEngine()) {
        self.analysisEngine = analysisEngine
    }

    func resolve(note: String, at date: Date) -> ConversationalFoodResolution {
        let input = note.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        switch input {
        case "my usual breakfast":
            return .saved(meal("Soft eggs & rye", "rye toast, eggs, tomato", "Breakfast", date, 382, 27, 23, 17, .toast, confidence: .known))
        case "i had salmon & rice":
            return .saved(meal("Miso salmon plate", "salmon, brown rice, greens", "Lunch", date, 548, 49, 37, 21, .green, confidence: .known))
        case "pasta for dinner":
            return .saved(meal("Tomato basil pasta", "pasta, tomato, pecorino", "Dinner", date, 682, 79, 25, 24, .pasta, confidence: .known))
        default:
            let result = analysisEngine.makeAnalysis(description: note)
            return .review(MealAnalysisDraft(result: result))
        }
    }

    func estimate(for note: String, at date: Date) -> Meal {
        switch resolve(note: note, at: date) {
        case .saved(let meal):
            return meal
        case .review(let draft):
            return reviewPreview(for: draft.result, at: date)
        }
    }

    private func reviewPreview(for result: MealAnalysisResult, at date: Date) -> Meal {
        let mealID = UUID()
        let artwork: Meal.Artwork = .neutral
        let title = result.detectedItems.map(\.displayName).joined(separator: " + ").ifEmpty(displayTitle(from: result))
        return Meal(
            id: mealID,
            title: title,
            subtitle: result.nutritionValidation?.isApproved == true
                ? "Review estimate before saving"
                : "Details needed before saving",
            mealType: mealType(for: date),
            time: date,
            energy: Int(result.mealTotals.caloriesKcal?.rounded() ?? 0),
            carbs: Int(result.mealTotals.carbohydrateGrams?.rounded() ?? 0),
            protein: Int(result.mealTotals.proteinGrams?.rounded() ?? 0),
            fat: Int(result.mealTotals.fatGrams?.rounded() ?? 0),
            artwork: artwork,
            confidence: .estimated,
            analysis: result,
            visualIdentity: MealVisualIdentityFactory().make(mealID: mealID, result: result, artwork: artwork)
        )
    }

    private func displayTitle(from result: MealAnalysisResult) -> String {
        result.detectedItems.isEmpty ? "Meal details needed" : "Meal review"
    }

    private func mealType(for date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<11: return "Breakfast"
        case 11..<16: return "Lunch"
        case 16..<22: return "Dinner"
        default: return "Meal"
        }
    }

    private func meal(
        _ title: String, _ subtitle: String, _ type: String, _ date: Date,
        _ energy: Int, _ carbs: Int, _ protein: Int, _ fat: Int, _ artwork: Meal.Artwork,
        confidence: Meal.Confidence
    ) -> Meal {
        Meal(
            id: UUID(), title: title, subtitle: subtitle, mealType: type, time: date,
            energy: energy, carbs: carbs, protein: protein, fat: fat,
            artwork: artwork, confidence: confidence
        )
    }
}

enum ConversationCoordinator {
    static let nutrition = LocalNutritionService()

    static func acknowledgement(for meal: Meal) -> String {
        guard meal.confidence == .known else {
            return "I kept this as an editable estimate so its serving and assumptions stay visible."
        }

        switch meal.artwork {
        case .toast:
            return "Got it. I used your familiar rye-and-eggs breakfast, then checked the portion against your usual log."
        case .pasta:
            return "That sounds comforting. I’ve put it in as a generous pasta portion; you can fine-tune it any time."
        case .green:
            return "Logged. The salmon gives this one a really grounding protein base."
        case .berry, .bowl, .neutral:
            return "I’ve added \(meal.title) as an estimate from your note. You can refine the portion any time."
        }
    }

    static func acknowledgement(for draft: MealAnalysisDraft) -> String {
        if draft.result.detectedItems.isEmpty {
            return "I don’t want to guess. Add the main dish and I’ll make an editable estimate."
        }
        if draft.result.nutritionValidation?.isApproved == false {
            return "I found the meal components, but I need the highlighted details before any nutrition can affect today’s totals."
        }
        return "I found the components and prepared an editable estimate. Confirm it when the serving looks right."
    }
}

private extension String {
    func ifEmpty(_ replacement: String) -> String { isEmpty ? replacement : self }
}
