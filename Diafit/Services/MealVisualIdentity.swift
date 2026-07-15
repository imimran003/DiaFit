import CryptoKit
import Foundation

enum MealVisualSource: String, Codable, Hashable, Sendable {
    case originalPhoto
    case generatedEditorial
    case bundledEditorial
    case deterministicPlaceholder
}

enum MealVisualRequestState: String, Codable, Hashable, Sendable {
    /// A provider may run with the structured prompt. Local builds replace this
    /// immediately with a deterministic component composition.
    case queued
    /// A high-impact food detail would materially change the requested image.
    case waitingForClarification
    /// A provider is unavailable; the UI has a truthful, retryable component
    /// composition instead of an unexplained blank image area.
    case deterministicFallback
    /// A validated image is present in the protected local asset cache.
    case ready
    case failed
}

/// The request contract remains useful whether an image is produced by a
/// server, a small local model, a cache, or the deterministic fallback. It is
/// bound to a meal/analysis ID and carries a quantity-sensitive signature.
struct MealVisualRequest: Codable, Hashable, Sendable {
    let mealID: UUID
    let requestID: UUID
    let canonicalComponentIDs: [String]
    let quantitySignature: [String]
    let styleVersion: String
    let prompt: String
    let cacheKey: String
    var state: MealVisualRequestState
    var failureReason: String?
}

struct MealVisualRequestBuilder: Sendable {
    func make(
        mealID: UUID,
        items: [DetectedFoodItem],
        clarificationQuestions: [ClarificationQuestion]
    ) -> MealVisualRequest? {
        guard !items.isEmpty else { return nil }
        let components = items.map(\.canonicalFoodId)
        let signatures = items.map { item in
            let preparation = item.preparationMethod ?? "unspecified"
            return "\(item.canonicalFoodId):\(item.quantity):\(item.servingUnit.rawValue):\(preparation)"
        }.sorted()
        let prompt = structuredPrompt(items: items)
        let needsHighImpactAnswer = clarificationQuestions.contains { $0.impactLevel == .high && $0.answer == nil }
        let state: MealVisualRequestState = needsHighImpactAnswer ? .waitingForClarification : .queued
        let requestID = UUID()
        let cacheKey = sha256([
            "components=" + components.sorted().joined(separator: ","),
            "quantity=" + signatures.joined(separator: ","),
            "style=" + MealVisualIdentityFactory.styleVersion,
            "prompt=" + prompt
        ].joined(separator: "|"))

        FoodLoggingDiagnostics.record("visual.request", fields: [
            "cacheKey": String(cacheKey.prefix(12)),
            "components": components.joined(separator: ","),
            "eligibility": state.rawValue,
            "mealID": mealID.uuidString,
            "requestID": requestID.uuidString
        ])

        return MealVisualRequest(
            mealID: mealID,
            requestID: requestID,
            canonicalComponentIDs: components,
            quantitySignature: signatures,
            styleVersion: MealVisualIdentityFactory.styleVersion,
            prompt: prompt,
            cacheKey: cacheKey,
            state: state,
            failureReason: nil
        )
    }

    private func structuredPrompt(items: [DetectedFoodItem]) -> String {
        let components = items.map(componentDescription).joined(separator: "; ")
        let type = items.count > 1 ? "simple balanced meal" : "single food or drink"
        let hasSprouts = items.contains { $0.category == .sprouts }
        let hasEggs = items.contains { $0.category == .egg || $0.canonicalFoodId.contains("egg") }
        let hasSupplement = items.contains { $0.category == .supplement }
        let sproutConstraint = hasSprouts ? "No salad ingredients unless a sprout salad is explicitly listed." : ""
        let eggConstraint = hasEggs ? "No extra eggs; preserve the stated egg count." : ""
        let shakeConstraint = hasSupplement ? "No fruit unless it is listed as a component; no fake product label." : ""
        return "Meal components: \(components). Meal type: \(type). Style: isolated studio food photography. Background: clean warm-neutral. Composition: show every requested component clearly and preserve stated quantities when visually important. Lighting: soft natural studio lighting. Perspective: slightly elevated. No unrelated foods, no text, no branding, no cutlery obscuring food, no decorative garnish that changes identity. \(sproutConstraint) \(eggConstraint) \(shakeConstraint)"
    }

    private func componentDescription(_ item: DetectedFoodItem) -> String {
        let count = quantityDescription(item)
        switch item.canonicalFoodId {
        case "boiled-egg", "hard-boiled-egg", "soft-boiled-egg":
            return "exactly \(count) peeled \(item.preparationMethod ?? "boiled") eggs"
        case "mixed-sprouts", "moong-sprouts", "chickpea-sprouts", "alfalfa-sprouts", "sprout-salad":
            return "\(count) \(item.servingUnit.singularDisplayName) of \(item.displayName.lowercased()), \(item.preparationMethod ?? "preparation unspecified")"
        default:
            if let supplement = item.supplementProfile {
                let flavour = supplement.flavour.map { "\($0) " } ?? ""
                return "\(count) \(item.servingUnit.singularDisplayName) of \(flavour)\(item.displayName.lowercased()), mixed with \(supplement.base.displayName)"
            }
            return "\(count) \(item.servingUnit.singularDisplayName) of \(item.displayName.lowercased())"
        }
    }

    private func quantityDescription(_ item: DetectedFoodItem) -> String {
        let value = item.quantity
        let words: [Double: String] = [1: "one", 2: "two", 3: "three", 4: "four"]
        return words[value] ?? value.formatted(.number.precision(.fractionLength(0...1)))
    }

    private func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
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
    let assetFileName: String?
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
        let variations = result.detectedItems.map { item in
            "\(item.canonicalFoodId):\(item.quantity):\(item.servingUnit.rawValue):\(item.preparationMethod ?? "unspecified")"
        }.sorted()
        let composition: MealVisualIdentity.Composition = foodIDs.count > 1 ? .combinedMeal : .singleFood
        let generatedAsset = result.generatedVisualAsset.flatMap { asset in
            result.visualRequest?.requestID == asset.requestID && result.visualRequest?.cacheKey == asset.cacheKey
                ? asset
                : nil
        }
        let source: MealVisualSource = generatedAsset != nil
            ? .generatedEditorial
            : (artwork == .neutral ? .deterministicPlaceholder : .bundledEditorial)
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
            createdAt: .now,
            assetFileName: generatedAsset?.fileName
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
/// late completions.
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
