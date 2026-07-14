import Foundation

protocol NutritionService {
    func estimate(for note: String, at date: Date) -> Meal
}

/// A deterministic stand-in for a server-backed food parser.
/// The app intentionally keeps this seam tiny: production can swap this for an
/// authenticated service that records provenance and confidence per nutrient.
struct LocalNutritionService: NutritionService {
    func estimate(for note: String, at date: Date) -> Meal {
        let input = note.lowercased()

        if input.contains("pasta") || input.contains("noodle") {
            return meal("Tomato basil pasta", "pasta, tomato, pecorino", "Dinner", date, 682, 79, 25, 24, .pasta)
        }
        if input.contains("toast") || input.contains("egg") {
            return meal("Soft eggs & rye", "rye toast, eggs, tomato", "Breakfast", date, 382, 27, 23, 17, .toast)
        }
        if input.contains("yogurt") || input.contains("berry") {
            return meal("Yogurt, berries & seeds", "Greek yogurt, blueberries, chia", "Breakfast", date, 318, 24, 24, 13, .berry)
        }
        if input.contains("salmon") || input.contains("rice") {
            return meal("Miso salmon plate", "salmon, brown rice, greens", "Lunch", date, 548, 49, 37, 21, .green)
        }
        return meal("Market salad bowl", "grains, vegetables, lemon", "Meal", date, 462, 43, 19, 20, .bowl)
    }

    private func meal(
        _ title: String, _ subtitle: String, _ type: String, _ date: Date,
        _ energy: Int, _ carbs: Int, _ protein: Int, _ fat: Int, _ artwork: Meal.Artwork
    ) -> Meal {
        Meal(
            id: UUID(), title: title, subtitle: subtitle, mealType: type, time: date,
            energy: energy, carbs: carbs, protein: protein, fat: fat,
            artwork: artwork, confidence: .estimated
        )
    }
}

enum ConversationCoordinator {
    static let nutrition = LocalNutritionService()

    static func acknowledgement(for meal: Meal) -> String {
        switch meal.artwork {
        case .toast:
            "Got it. I used your familiar rye-and-eggs breakfast, then checked the portion against your usual log."
        case .pasta:
            "That sounds comforting. I’ve put it in as a generous pasta portion; you can fine-tune it any time."
        case .green:
            "Logged. The salmon gives this one a really grounding protein base."
        case .berry:
            "Logged—bright, filling, and nicely balanced for a first meal."
        case .bowl:
            "I’ve added that as a vegetable-forward bowl and kept the estimate appropriately gentle."
        }
    }
}
