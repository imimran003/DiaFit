import Foundation

/// A deterministic, provider-independent representation of the language work
/// done before nutrition or visuals are considered. This is intentionally kept
/// separate from `MealAnalysisResult` so every stage can be unit tested without
/// networking, image services, or SwiftUI.
struct FoodUnderstandingTrace: Hashable, Sendable {
    let normalizedInput: String
    let tokens: [String]
    let entities: [FoodEntityCandidate]
    let components: [ParsedFoodComponent]

    var containsSupplement: Bool {
        components.contains { $0.food.category == .supplement }
    }
}

struct FoodEntityCandidate: Hashable, Sendable {
    let canonicalFoodID: String
    let matchedAlias: String
    let tokenStart: Int
    let tokenEnd: Int
    let confidenceScore: Double
}

struct ParsedFoodComponent: Hashable, Sendable {
    let food: IndianFoodDefinition
    let matchedAlias: String
    let quantity: Double
    let servingUnit: ServingUnit
    let quantityWasExplicit: Bool
    let preparationMethod: String?
    let modifiers: [String]
    let supplementProfile: SupplementProductProfile?
    let confidenceScore: Double
}

/// Stages 1–9 of the local food-understanding flow: input normalisation,
/// quantity extraction, entity extraction, compound decomposition, preparation
/// and modifier extraction, canonical alias matching, and supplement detection.
/// It works over catalog metadata rather than switches for individual phrases.
struct FoodUnderstandingPipeline: Sendable {
    let catalog: IndianFoodCatalogService

    init(catalog: IndianFoodCatalogService) {
        self.catalog = catalog
    }

    func parse(_ rawInput: String) -> FoodUnderstandingTrace {
        let normalized = FoodInputNormalizer.normalize(rawInput)
        let candidates = suppressShakeBaseAsStandaloneFood(
            lexiconMatches(in: normalized.tokens),
            tokens: normalized.tokens
        )
        let components = candidates.enumerated().map { index, candidate in
            let food = catalog.food(canonicalID: candidate.canonicalFoodID)!
            let scope = componentScope(
                at: index,
                candidates: candidates,
                tokens: normalized.tokens
            )
            let scopedTokens = Array(normalized.tokens[scope])
            let quantity = QuantityExtractor.extract(
                tokens: normalized.tokens,
                componentStart: candidate.tokenStart,
                componentEnd: candidate.tokenEnd,
                scope: scope,
                food: food
            )
            let modifiers = IngredientModifierExtractor.modifiers(
                // Shake bases and additions describe the supplement recipe as
                // a whole. Other foods must remain within their own span so a
                // sibling's butter, cheese or oil cannot leak across a meal.
                tokens: food.category == .supplement ? normalized.tokens : scopedTokens,
                food: food
            )
            let preparation = PreparationExtractor.method(
                tokens: scopedTokens,
                food: food
            )
            let supplement = SupplementProfileResolver.profile(
                for: food,
                tokens: normalized.tokens,
                quantity: quantity.quantity,
                unit: quantity.unit,
                modifiers: modifiers
            )
            return ParsedFoodComponent(
                food: food,
                matchedAlias: candidate.matchedAlias,
                quantity: quantity.quantity,
                servingUnit: quantity.unit,
                quantityWasExplicit: quantity.wasExplicit,
                preparationMethod: preparation,
                modifiers: modifiers,
                supplementProfile: supplement,
                confidenceScore: candidate.confidenceScore
            )
        }

        FoodLoggingDiagnostics.record("input.normalized", fields: [
            "normalizedInput": normalized.text,
            "inputFingerprint": FoodLoggingDiagnostics.fingerprint(rawInput),
            "tokenCount": String(normalized.tokens.count)
        ])
        FoodLoggingDiagnostics.record("entities.extracted", fields: [
            "entities": candidates.map { "\($0.canonicalFoodID):\($0.matchedAlias)" }.joined(separator: ","),
            "count": String(candidates.count)
        ])
        FoodLoggingDiagnostics.record("components.decomposed", fields: [
            "components": components.map { "\($0.food.canonicalId):\($0.quantity) \($0.servingUnit.rawValue)" }.joined(separator: ",")
        ])

        return FoodUnderstandingTrace(
            normalizedInput: normalized.text,
            tokens: normalized.tokens,
            entities: candidates,
            components: components
        )
    }

    private func lexiconMatches(in tokens: [String]) -> [FoodEntityCandidate] {
        var candidates: [(food: IndianFoodDefinition, alias: String, start: Int, end: Int)] = []

        for food in catalog.foods {
            for alias in food.aliases {
                let aliasTokens = FoodInputNormalizer.tokens(for: alias)
                guard !aliasTokens.isEmpty, aliasTokens.count <= tokens.count else { continue }
                for start in 0...(tokens.count - aliasTokens.count) {
                    let end = start + aliasTokens.count
                    guard Array(tokens[start..<end]) == aliasTokens else { continue }
                    candidates.append((food, alias, start, end))
                }
            }
        }

        // Prefer the most specific phrase and then retain non-overlapping food
        // spans. Connector words are deliberately not consumed, which lets a
        // phrase contain five independent components joined by with/and/plus.
        let ordered = candidates.sorted {
            let leftLength = $0.end - $0.start
            let rightLength = $1.end - $1.start
            if leftLength != rightLength { return leftLength > rightLength }
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.food.canonicalId < $1.food.canonicalId
        }
        var used = Set<Int>()
        var selected: [FoodEntityCandidate] = []
        for candidate in ordered {
            let span = Set(candidate.start..<candidate.end)
            guard used.isDisjoint(with: span) else { continue }
            used.formUnion(span)
            let tokenLength = candidate.end - candidate.start
            selected.append(FoodEntityCandidate(
                canonicalFoodID: candidate.food.canonicalId,
                matchedAlias: candidate.alias,
                tokenStart: candidate.start,
                tokenEnd: candidate.end,
                confidenceScore: tokenLength > 1 ? 0.94 : 0.82
            ))
        }
        return selected.sorted { $0.tokenStart < $1.tokenStart }
    }

    /// Produces a token range owned by one detected food. Connectors between
    /// entities are boundaries, while connector words inside a matched alias
    /// remain part of that food. This keeps quantities and preparations local
    /// without preventing phrases such as `whey with water` from retaining
    /// trailing recipe detail when no second food follows.
    private func componentScope(
        at index: Int,
        candidates: [FoodEntityCandidate],
        tokens: [String]
    ) -> Range<Int> {
        let candidate = candidates[index]
        var lowerBound = index == 0 ? 0 : candidates[index - 1].tokenEnd
        var upperBound = index == candidates.count - 1 ? tokens.count : candidates[index + 1].tokenStart

        if index > 0,
           lowerBound < candidate.tokenStart,
           let connector = tokens[lowerBound..<candidate.tokenStart]
            .lastIndex(where: FoodConnector.isBoundary) {
            lowerBound = connector + 1
        }

        if index < candidates.count - 1,
           candidate.tokenEnd < upperBound,
           let connector = tokens[candidate.tokenEnd..<upperBound]
            .firstIndex(where: FoodConnector.isBoundary) {
            upperBound = connector
        }

        return lowerBound..<upperBound
    }

    /// Milk is nutrition-bearing, but in a whey phrase it is the selected shake
    /// base rather than a second plate component. Keeping it on the supplement
    /// profile prevents a powder-plus-milk double count while retaining the
    /// explicit base in the editable UI model and visual prompt.
    private func suppressShakeBaseAsStandaloneFood(
        _ candidates: [FoodEntityCandidate],
        tokens: [String]
    ) -> [FoodEntityCandidate] {
        let hasSupplement = candidates.contains { catalog.food(canonicalID: $0.canonicalFoodID)?.category == .supplement }
        guard hasSupplement, tokens.contains("milk") else { return candidates }
        return candidates.filter { $0.canonicalFoodID != "milk" }
    }
}

private struct NormalizedFoodInput: Sendable {
    let text: String
    let tokens: [String]
}

private enum FoodInputNormalizer {
    static func normalize(_ value: String) -> NormalizedFoodInput {
        let tokens = tokens(for: value)
        return NormalizedFoodInput(text: tokens.joined(separator: " "), tokens: tokens)
    }

    static func tokens(for value: String) -> [String] {
        let folded = value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        var result: [String] = []
        var buffer = ""
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "." {
                buffer.unicodeScalars.append(scalar)
            } else if !buffer.isEmpty {
                result.append(buffer)
                buffer = ""
            }
        }
        if !buffer.isEmpty { result.append(buffer) }
        return result
    }
}

private struct ParsedQuantity: Sendable {
    let quantity: Double
    let unit: ServingUnit
    let wasExplicit: Bool
}

private enum QuantityExtractor {
    private static let unitWords: [String: ServingUnit] = [
        "scoop": .scoop, "scoops": .scoop,
        "egg": .wholeEgg, "eggs": .wholeEgg,
        "serving": .serving, "servings": .serving,
        "bowl": .mediumBowl, "bowls": .mediumBowl,
        "cup": .cup, "cups": .cup,
        "glass": .glass, "glasses": .glass,
        "piece": .piece, "pieces": .piece,
        "slice": .slice, "slices": .slice,
        "tablespoon": .tablespoon, "tablespoons": .tablespoon,
        "tbsp": .tablespoon,
        "teaspoon": .teaspoon, "teaspoons": .teaspoon,
        "tsp": .teaspoon,
        "gram": .grams, "grams": .grams, "g": .grams
    ]

    static func extract(
        tokens: [String],
        componentStart: Int,
        componentEnd: Int,
        scope: Range<Int>,
        food: IndianFoodDefinition
    ) -> ParsedQuantity {
        let defaultUnit = food.standardServing?.unit ?? .serving
        let defaultQuantity = food.standardServing?.quantity ?? 1
        let prefix = Array(tokens[scope.lowerBound..<componentStart])
        let suffix = Array(tokens[componentEnd..<scope.upperBound])

        if let explicit = explicitQuantity(in: prefix, defaultUnit: defaultUnit, allowsBareNumber: true) {
            return explicit
        }
        // Post-positive quantities are accepted only with a serving unit. This
        // supports `whey 2 scoops` without treating trailing times or prose as
        // the amount of the food.
        if let explicit = explicitQuantity(in: suffix, defaultUnit: defaultUnit, allowsBareNumber: false) {
            return explicit
        }
        return ParsedQuantity(quantity: defaultQuantity, unit: defaultUnit, wasExplicit: false)
    }

    private static func explicitQuantity(
        in context: [String],
        defaultUnit: ServingUnit,
        allowsBareNumber: Bool
    ) -> ParsedQuantity? {
        guard !context.isEmpty else { return nil }
        if let unitIndex = context.lastIndex(where: { unitWords[$0] != nil }) {
            let precedingToken = unitIndex > 0 ? context[unitIndex - 1] : context[unitIndex]
            let quantity = number(in: Array(context[..<unitIndex])) ?? impliedNumber(precedingToken)
            if let quantity {
                return ParsedQuantity(
                    quantity: quantity,
                    unit: unitWords[context[unitIndex]] ?? defaultUnit,
                    wasExplicit: true
                )
            }
        }
        if allowsBareNumber, let quantity = number(in: context) {
            return ParsedQuantity(quantity: quantity, unit: defaultUnit, wasExplicit: true)
        }
        return nil
    }

    private static func impliedNumber(_ token: String) -> Double? {
        switch token {
        case "pair", "couple": return 2
        default: return nil
        }
    }

    private static func number(in tokens: [String]) -> Double? {
        guard !tokens.isEmpty else { return nil }
        let words: [String: Double] = [
            "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4,
            "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
            "half": 0.5, "quarter": 0.25, "pair": 2, "couple": 2
        ]

        if tokens.count >= 4,
           tokens.suffix(4).elementsEqual(["one", "and", "a", "half"]) {
            return 1.5
        }
        if tokens.count >= 3,
           tokens.suffix(3).elementsEqual(["one", "and", "half"]) {
            return 1.5
        }
        for token in tokens.reversed() {
            if let decimal = Double(token), (0.05...100).contains(decimal) { return decimal }
            if let word = words[token] { return word }
        }
        return nil
    }
}

private enum FoodConnector {
    private static let boundaryTokens = Set(["and", "with", "plus"])

    static func isBoundary(_ token: String) -> Bool {
        boundaryTokens.contains(token)
    }
}

private enum PreparationExtractor {
    static func method(tokens: [String], food: IndianFoodDefinition) -> String? {
        if tokens.contains("boiled") { return "boiled" }
        if tokens.contains("poached") { return "poached" }
        if tokens.contains("scrambled") { return "scrambled" }
        if tokens.contains("fried") { return "fried" }
        if tokens.contains("raw") { return "raw" }
        if tokens.contains("cooked") { return "cooked" }
        return food.commonPreparationMethods.first
    }
}

private enum IngredientModifierExtractor {
    static func modifiers(tokens: [String], food: IndianFoodDefinition) -> [String] {
        let known = ["water", "milk", "banana", "chocolate", "vanilla", "unflavoured", "unflavored", "butter", "cheese", "oil"]
        let found = known.filter(tokens.contains)
        guard food.category == .supplement || food.category == .egg || food.category == .sprouts else { return [] }
        return found
    }
}

private enum SupplementProfileResolver {
    static func profile(
        for food: IndianFoodDefinition,
        tokens: [String],
        quantity: Double,
        unit: ServingUnit,
        modifiers: [String]
    ) -> SupplementProductProfile? {
        guard food.category == .supplement else { return nil }
        let base: SupplementBase = modifiers.contains("milk") ? .milk : (modifiers.contains("water") ? .water : .unspecified)
        let flavour = ["chocolate", "vanilla", "unflavoured", "unflavored"].first(where: modifiers.contains)
        return SupplementProductProfile(
            brand: nil,
            productName: food.canonicalName,
            barcode: nil,
            flavour: flavour,
            servingSizeGrams: (food.standardServing?.grams ?? 30) * quantity,
            servingUnit: unit,
            gramsPerScoop: food.standardServing?.unit == .scoop ? food.standardServing?.grams : nil,
            base: base,
            source: food.dataSource ?? "Bundled generic supplement fallback",
            sourceVersion: food.dataVersion,
            isUserConfirmed: false
        )
    }
}
