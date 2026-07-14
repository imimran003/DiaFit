import CryptoKit
import Foundation

enum MealVisualSource: String, Codable, Hashable, Sendable {
    case originalPhoto
    case generatedEditorial
    case bundledEditorial
    case deterministicPlaceholder
}

struct MealVisualIdentity: Codable, Hashable, Sendable {
    enum Composition: String, Codable, Hashable, Sendable {
        case singleFood
        case combinedMeal
    }

    let mealID: UUID
    let requestID: UUID
    let canonicalFoodIDs: [String]
    let preparationVariations: [String]
    let visualStyleVersion: String
    let composition: Composition
    let source: MealVisualSource
    let cacheKey: String
    let createdAt: Date
}

/// Generates a stable identity from structured food information only. Display
/// names and conversational prose are deliberately excluded: neither can safely
/// identify an image across locales or recipe-name edits.
struct MealVisualIdentityFactory: Sendable {
    static let styleVersion = "editorial-cutout-v2"

    func make(mealID: UUID, result: MealAnalysisResult, artwork: Meal.Artwork) -> MealVisualIdentity {
        let foodIDs = result.detectedItems.map(\.canonicalFoodId).sorted()
        // The canonical ID encodes the selected preparation (for example,
        // `black-coffee` versus `coffee-with-milk`). It is intentionally used
        // instead of localised display or method text in the cache identity.
        let variations = result.detectedItems.map(\.canonicalFoodId).sorted()
        let composition: MealVisualIdentity.Composition = foodIDs.count > 1 ? .combinedMeal : .singleFood
        let source: MealVisualSource = artwork == .neutral ? .deterministicPlaceholder : .bundledEditorial
        let requestID = UUID()
        let keyParts = [
            "foods=" + foodIDs.joined(separator: ","),
            "variations=" + variations.joined(separator: ","),
            "style=" + Self.styleVersion,
            "composition=" + composition.rawValue,
            "source=" + source.rawValue
        ]
        let cacheKey = Self.sha256(keyParts.joined(separator: "|"))

        FoodLoggingDiagnostics.record("visual.identity", fields: [
            "cacheKey": String(cacheKey.prefix(12)),
            "components": foodIDs.joined(separator: ","),
            "requestID": requestID.uuidString,
            "source": source.rawValue
        ])

        return MealVisualIdentity(
            mealID: mealID,
            requestID: requestID,
            canonicalFoodIDs: foodIDs,
            preparationVariations: variations,
            visualStyleVersion: Self.styleVersion,
            composition: composition,
            source: source,
            cacheKey: cacheKey,
            createdAt: .now
        )
    }

    /// The generated prompt is an explicit contract for a future image service.
    /// Current local builds use only bundled art or the neutral placeholder.
    func editorialPrompt(for identity: MealVisualIdentity) -> String {
        let components = identity.canonicalFoodIDs
            .map { $0.replacingOccurrences(of: "-", with: " ") }
            .joined(separator: " and ")
        return "Editorial studio food image of exactly \(components). "
            + "Composition: \(identity.composition.rawValue). "
            + "Show every requested component clearly. "
            + "No salad, no unrelated vegetables, no additional dishes, no text, no duplicate food items, no Western breakfast substitutions, and no utensils obscuring the food."
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Guards asynchronous generated-image completion. A response can only apply to
/// the currently active request for the same meal, and deleted meals reject all
/// late completions. The app has no runtime generator yet; this actor provides
/// the safe association boundary before one is connected.
actor MealVisualRequestLedger {
    private struct Pending {
        let mealID: UUID
        let cacheKey: String
    }

    private var pending: [UUID: Pending] = [:]
    private var latestRequestByMeal: [UUID: UUID] = [:]
    private var deletedMeals = Set<UUID>()

    func begin(mealID: UUID, cacheKey: String, requestID: UUID) {
        deletedMeals.remove(mealID)
        pending[requestID] = Pending(mealID: mealID, cacheKey: cacheKey)
        latestRequestByMeal[mealID] = requestID
    }

    func canApply(mealID: UUID, cacheKey: String, requestID: UUID) -> Bool {
        guard !deletedMeals.contains(mealID),
              latestRequestByMeal[mealID] == requestID,
              let request = pending[requestID] else { return false }
        return request.mealID == mealID && request.cacheKey == cacheKey
    }

    func finish(mealID: UUID, cacheKey: String, requestID: UUID) -> Bool {
        let allowed = canApply(mealID: mealID, cacheKey: cacheKey, requestID: requestID)
        pending[requestID] = nil
        return allowed
    }

    func cancel(requestID: UUID) {
        guard let request = pending.removeValue(forKey: requestID) else { return }
        if latestRequestByMeal[request.mealID] == requestID {
            latestRequestByMeal[request.mealID] = nil
        }
    }

    func delete(mealID: UUID) {
        deletedMeals.insert(mealID)
        latestRequestByMeal[mealID] = nil
        pending = pending.filter { $0.value.mealID != mealID }
    }
}
