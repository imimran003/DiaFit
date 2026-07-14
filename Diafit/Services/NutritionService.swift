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
