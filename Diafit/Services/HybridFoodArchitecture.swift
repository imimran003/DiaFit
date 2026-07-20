import Foundation

// MARK: - AI meal understanding

/// The output of the language model is deliberately a description of food,
/// never a nutrition answer.  Nutrition is resolved by the services below.
struct MealParseResult: Codable, Hashable, Sendable {
    var detectedItems: [ParsedFoodItem]
    var unresolvedItems: [String]
    var mealDescription: String
    var clarificationQuestions: [String]
    var confidence: Double
}

struct ParsedFoodItem: Codable, Hashable, Sendable {
    var originalText: String
    var canonicalSearchName: String
    var regionalName: String?
    var quantity: Double?
    var unit: String?
    var estimatedGrams: Double?
    var preparationMethod: String?
    var additions: [String]
    var exclusions: [String]
    var brand: String?
    var productName: String?
    var flavour: String?
    var servingSize: String?
    var confidence: Double
    var requiresClarification: Bool

    init(originalText: String, canonicalSearchName: String, regionalName: String? = nil,
         quantity: Double? = nil, unit: String? = nil, estimatedGrams: Double? = nil,
         preparationMethod: String? = nil, additions: [String] = [], exclusions: [String] = [],
         brand: String? = nil, productName: String? = nil, flavour: String? = nil,
         servingSize: String? = nil, confidence: Double = 0, requiresClarification: Bool = false) {
        self.originalText = originalText
        self.canonicalSearchName = canonicalSearchName
        self.regionalName = regionalName
        self.quantity = quantity
        self.unit = unit
        self.estimatedGrams = estimatedGrams
        self.preparationMethod = preparationMethod
        self.additions = additions
        self.exclusions = exclusions
        self.brand = brand
        self.productName = productName
        self.flavour = flavour
        self.servingSize = servingSize
        self.confidence = confidence
        self.requiresClarification = requiresClarification
    }
}

protocol FoodUnderstandingService: Sendable {
    func parse(text: String, image: PreparedFoodImage?) async throws -> MealParseResult
}

/// Offline development implementation of the same structured boundary. It is
/// deliberately used only when a backend client is not configured; production
/// composition should inject `BackendFoodUnderstandingService` here. Keeping
/// this adapter non-optional means an incomplete local record still traverses
/// the interpretation stage instead of silently ending in the local parser.
struct LocalStructuredMealUnderstandingService: FoodUnderstandingService, Sendable {
    let catalog: IndianFoodCatalogService

    init(catalog: IndianFoodCatalogService = IndianFoodCatalogService()) {
        self.catalog = catalog
    }

    func parse(text: String, image: PreparedFoodImage? = nil) async throws -> MealParseResult {
        let trace = FoodUnderstandingPipeline(catalog: catalog).parse(text)
        let items = trace.components.map { component in
            ParsedFoodItem(
                originalText: component.matchedAlias,
                canonicalSearchName: component.food.englishName,
                regionalName: component.food.regionalNames.first,
                quantity: component.quantity,
                unit: component.servingUnit.rawValue,
                preparationMethod: component.preparationMethod,
                additions: component.modifiers,
                confidence: component.confidenceScore,
                requiresClarification: false
            )
        }
        return MealParseResult(
            detectedItems: items,
            unresolvedItems: items.isEmpty ? [text] : [],
            mealDescription: text,
            clarificationQuestions: [],
            confidence: items.map(\.confidence).min() ?? 0.1
        )
    }
}

/// A backend client is intentionally the only OpenAI-facing implementation.
/// The iOS target receives an account token; it never contains a provider key.
struct BackendFoodUnderstandingService: FoodUnderstandingService, Sendable {
    let endpoint: URL
    let tokenProvider: BackendAccessTokenProvider
    let session: URLSession

    init(endpoint: URL, tokenProvider: BackendAccessTokenProvider, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.tokenProvider = tokenProvider
        self.session = session
    }

    func parse(text: String, image: PreparedFoodImage? = nil) async throws -> MealParseResult {
        let token = try await tokenProvider.accessToken()
        // Versioned backend route; the service may be backed by OpenAI,
        // fixtures, or another provider without changing this client.
        var request = URLRequest(url: endpoint.appending(path: "v1/meal-parse"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(UnderstandingRequest(
            apiVersion: "v1", text: text,
            imageReference: image?.imageReference.identifier,
            imageBase64: image?.data.base64EncodedString(), mimeType: image?.mimeType
        ))
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw FoodAnalysisError.endpointUnavailable
        }
        do { return try JSONDecoder().decode(MealParseResult.self, from: data) }
        catch { throw FoodAnalysisError.malformedProviderResponse }
    }

    /// Kept beside the client so the backend contract can be generated and
    /// reviewed without placing an untyped prompt or schema in a view.
    static let strictJSONSchema = """
    {"type":"object","additionalProperties":false,"required":["detectedItems","unresolvedItems","mealDescription","clarificationQuestions","confidence"],"properties":{"detectedItems":{"type":"array","items":{"type":"object","additionalProperties":false,"required":["originalText","canonicalSearchName","additions","exclusions","confidence","requiresClarification"],"properties":{"originalText":{"type":"string"},"canonicalSearchName":{"type":"string"},"regionalName":{"type":["string","null"]},"quantity":{"type":["number","null"]},"unit":{"type":["string","null"]},"estimatedGrams":{"type":["number","null"]},"preparationMethod":{"type":["string","null"]},"additions":{"type":"array","items":{"type":"string"}},"exclusions":{"type":"array","items":{"type":"string"}},"brand":{"type":["string","null"]},"productName":{"type":["string","null"]},"flavour":{"type":["string","null"]},"servingSize":{"type":["string","null"]},"confidence":{"type":"number"},"requiresClarification":{"type":"boolean"}}}},"unresolvedItems":{"type":"array","items":{"type":"string"}},"mealDescription":{"type":"string"},"clarificationQuestions":{"type":"array","items":{"type":"string"}},"confidence":{"type":"number"}}}
    """

    private struct UnderstandingRequest: Encodable {
        let apiVersion: String
        let text: String
        let imageReference: String?
        let imageBase64: String?
        let mimeType: String?
    }
}

// MARK: - Canonical normalisation and user memory

struct CanonicalFoodMatch: Hashable, Sendable {
    let food: IndianFoodDefinition
    let matchedAlias: String
    let confidence: Double
    let source: String
}

extension FoodNormalisationService {
    func match(_ item: ParsedFoodItem) -> CanonicalFoodMatch? {
        guard let food = normalise(item.canonicalSearchName) else { return nil }
        return CanonicalFoodMatch(food: food, matchedAlias: item.canonicalSearchName,
                                  confidence: item.confidence, source: "local-canonical-catalog")
    }
}

/// Local catalog remains useful for aliases, regional names, and verified
/// fallbacks.  Matching is tolerant of punctuation, transliteration and small
/// spelling errors, so an exact file row is not required for every user phrase.
struct HybridFoodNormalisationService: FoodNormalisationService, Sendable {
    let catalog: IndianFoodCatalogService

    init(catalog: IndianFoodCatalogService = IndianFoodCatalogService()) { self.catalog = catalog }

    func normalise(_ query: String) -> IndianFoodDefinition? {
        if let exact = catalog.normalise(query) { return exact }
        let queryTokens = Set(tokens(query))
        guard !queryTokens.isEmpty else { return nil }
        return catalog.foods.map { food in
            let candidates = [food.canonicalName, food.englishName] + food.aliases + food.regionalNames + food.transliterations
            let score = candidates.map { similarity(queryTokens, Set(tokens($0))) }.max() ?? 0
            return (food, score)
        }.filter { $0.1 >= 0.62 }.max { $0.1 < $1.1 }?.0
    }

    /// Confirmed member aliases outrank fuzzy catalog matches while retaining
    /// the catalog as the source of canonical metadata.
    func match(_ item: ParsedFoodItem, memory: UserFoodMemoryRepository?) async -> CanonicalFoodMatch? {
        if let memory, let remembered = await memory.rankedMatches(for: item.canonicalSearchName).first,
           let food = catalog.food(canonicalID: remembered.canonicalFoodID) {
            return CanonicalFoodMatch(food: food, matchedAlias: remembered.alias, confidence: 0.99, source: "user-confirmed-memory")
        }
        return match(item)
    }

    func matches(in description: String) -> [IndianFoodDefinition] {
        var result: [IndianFoodDefinition] = []
        let separated = [" with ", " and ", " plus ", " along with ", " served with ", " together with "]
            .reduce(description) { partial, connector in
                partial.replacingOccurrences(of: connector, with: ",", options: [.caseInsensitive, .diacriticInsensitive])
            }
        for phrase in separated.split(whereSeparator: { ",;+".contains($0) }) {
            if let food = normalise(String(phrase)), !result.contains(where: { $0.id == food.id }) { result.append(food) }
        }
        let catalogMatches = catalog.matches(in: description)
        for food in catalogMatches where !result.contains(where: { $0.id == food.id }) { result.append(food) }
        return result
    }

    private func tokens(_ value: String) -> [String] {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    private func similarity(_ lhs: Set<String>, _ rhs: Set<String>) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        let overlap = Double(lhs.intersection(rhs).count) / Double(max(lhs.count, rhs.count))
        return overlap == 0 ? 0 : overlap + (lhs == rhs ? 0.2 : 0)
    }
}

struct UserFoodMemory: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    var alias: String
    var canonicalFoodID: String
    var servingGrams: Double?
    var servingUnit: String?
    var preparation: String?
    var productID: String?
    var lastConfirmedAt: Date
}

protocol UserFoodMemoryRepository: Sendable {
    func rankedMatches(for query: String) async -> [UserFoodMemory]
    func save(_ memory: UserFoodMemory) async
}

actor InMemoryUserFoodMemoryRepository: UserFoodMemoryRepository {
    private var records: [UserFoodMemory] = []
    func rankedMatches(for query: String) async -> [UserFoodMemory] {
        let key = query.lowercased()
        return records.filter { $0.alias.lowercased().contains(key) || key.contains($0.alias.lowercased()) }
            .sorted { $0.lastConfirmedAt > $1.lastConfirmedAt }
    }
    func save(_ memory: UserFoodMemory) async {
        records.removeAll { $0.alias.caseInsensitiveCompare(memory.alias) == .orderedSame }
        records.append(memory)
    }
}

// MARK: - Verified nutrition and packaged products

struct PackagedFoodRecord: Codable, Hashable, Sendable, Identifiable {
    let id: String
    var brand: String
    var productName: String
    var barcode: String?
    var flavour: String?
    var gramsPerScoop: Double?
    var servingGrams: Double
    var nutritionPerServing: NutritionValues
    var nutritionPer100Grams: NutritionValues?
    var source: String
    var sourceVersion: String?
    var userConfirmed: Bool
}

protocol PackagedFoodRepository: Sendable {
    func find(brand: String?, productName: String?, barcode: String?, flavour: String?) async -> PackagedFoodRecord?
    func save(_ record: PackagedFoodRecord) async
}

actor InMemoryPackagedFoodRepository: PackagedFoodRepository {
    private var records: [PackagedFoodRecord] = []
    func find(brand: String?, productName: String?, barcode: String?, flavour: String?) async -> PackagedFoodRecord? {
        records.first { record in
            if let barcode, !barcode.isEmpty { return record.barcode == barcode }
            let query = [brand, productName, flavour].compactMap { $0?.lowercased() }.joined(separator: " ")
            return !query.isEmpty && query.contains(record.productName.lowercased())
        }
    }
    func save(_ record: PackagedFoodRecord) async {
        records.removeAll { $0.id == record.id }
        records.append(record)
    }
}

struct NutritionResolution: Sendable {
    let lookup: NutritionLookup
    let sourceRecordID: String?
    let servingAmount: Double
    let servingUnit: String
    let estimatedGrams: Double?
    let assumptions: [String]
    let verified: Bool
}

/// Remote nutrition databases implement this seam. They return sourced
/// records only; model output is never accepted through this protocol.
protocol VerifiedNutritionProvider: Sendable {
    var identifier: String { get }
    func lookup(canonicalSearchName: String, estimatedGrams: Double?) async throws -> NutritionLookup?
}

protocol ModelNutritionEstimateProvider: Sendable {
    func estimate(for item: ParsedFoodItem, estimatedGrams: Double?) async throws -> NutritionLookup?
}

protocol NutritionResolutionService: Sendable {
    func resolve(item: ParsedFoodItem, canonical: CanonicalFoodMatch?) async -> NutritionResolution
}

/// Provider hierarchy adapter. The existing catalog lookup remains a safe
/// offline fallback; remote providers and labels can be injected later.
struct HybridNutritionResolutionService: NutritionResolutionService, Sendable {
    let catalog: IndianFoodCatalogService
    let portions: StandardPortionEstimationService
    let packaged: PackagedFoodRepository?
    let verifiedProvider: (any VerifiedNutritionProvider)?
    let modelProvider: (any ModelNutritionEstimateProvider)?
    let validation: any NutritionValidationService

    init(catalog: IndianFoodCatalogService = IndianFoodCatalogService(),
         portions: StandardPortionEstimationService = .init(),
         packaged: PackagedFoodRepository? = nil,
         verifiedProvider: (any VerifiedNutritionProvider)? = nil,
         modelProvider: (any ModelNutritionEstimateProvider)? = nil,
         validation: any NutritionValidationService = DefaultNutritionValidationService()) {
        self.catalog = catalog
        self.portions = portions
        self.packaged = packaged
        self.verifiedProvider = verifiedProvider
        self.modelProvider = modelProvider
        self.validation = validation
    }

    func resolve(item: ParsedFoodItem, canonical: CanonicalFoodMatch?) async -> NutritionResolution {
        let amount = item.quantity ?? 1
        let unit = item.unit ?? "serving"
        if let packaged, let product = await packaged.find(brand: item.brand, productName: item.productName, barcode: nil, flavour: item.flavour) {
            return validatedResolution(
                values: product.nutritionPerServing.scaled(by: amount),
                provenance: NutritionProvenance(kind: .packagedLabel, dataSource: product.source, dataVersion: product.sourceVersion, confidence: .high),
                sourceRecordID: product.id, servingAmount: amount, servingUnit: unit,
                estimatedGrams: product.servingGrams * amount,
                assumptions: ["Using the confirmed packaged serving label."]
            )
        }

        if let verifiedProvider {
            if let lookup = try? await verifiedProvider.lookup(canonicalSearchName: item.canonicalSearchName, estimatedGrams: item.estimatedGrams) {
                return validatedResolution(values: lookup.values, provenance: lookup.provenance,
                                           sourceRecordID: lookup.provenance.dataSource,
                                           servingAmount: amount, servingUnit: unit,
                                           estimatedGrams: item.estimatedGrams,
                                           assumptions: ["Nutrition matched by verified provider \(verifiedProvider.identifier)."])
            }
        }

        guard let canonical else {
            return await modelFallback(item: item, amount: amount, unit: unit,
                                       estimatedGrams: item.estimatedGrams,
                                       assumptions: ["No verified canonical food match was available."])
        }
        let serving = ServingUnit(rawValue: unit) ?? canonical.food.standardServing?.unit ?? .serving
        let grams = item.estimatedGrams ?? portions.estimatedWeight(quantity: amount, unit: serving, food: canonical.food)
        let lookup = CatalogNutritionLookupService().nutrition(for: canonical.food, estimatedWeightGrams: grams)
        if !lookup.values.isEmpty {
            let local = validatedResolution(values: lookup.values, provenance: lookup.provenance,
                                            sourceRecordID: canonical.food.canonicalId,
                                            servingAmount: amount, servingUnit: serving.rawValue,
                                            estimatedGrams: grams,
                                            assumptions: ["Using the local canonical fallback until a verified provider record is available."])
            if local.verified { return local }
        }
        return await modelFallback(item: item, amount: amount, unit: serving.rawValue,
                                   estimatedGrams: grams,
                                   assumptions: ["The local canonical record needs a provider-backed estimate."])
    }

    private func modelFallback(item: ParsedFoodItem, amount: Double, unit: String,
                               estimatedGrams: Double?, assumptions: [String]) async -> NutritionResolution {
        guard let modelProvider else {
            return NutritionResolution(lookup: NutritionLookup(values: .unavailable, provenance: .unavailable), sourceRecordID: nil,
                                       servingAmount: amount, servingUnit: unit, estimatedGrams: estimatedGrams,
                                       assumptions: assumptions + ["No reliable nutrition estimate is available; review the serving details."], verified: false)
        }
        guard let lookup = try? await modelProvider.estimate(for: item, estimatedGrams: estimatedGrams) else {
            return NutritionResolution(lookup: NutritionLookup(values: .unavailable, provenance: .unavailable), sourceRecordID: nil,
                                       servingAmount: amount, servingUnit: unit, estimatedGrams: estimatedGrams,
                                       assumptions: assumptions + ["No reliable nutrition estimate is available; review the serving details."], verified: false)
        }
        return validatedResolution(values: lookup.values,
                                   provenance: NutritionProvenance(kind: .modelFallback,
                                                                  dataSource: lookup.provenance.dataSource,
                                                                  dataVersion: lookup.provenance.dataVersion,
                                                                  confidence: .low),
                                   sourceRecordID: lookup.provenance.dataSource,
                                   servingAmount: amount, servingUnit: unit,
                                   estimatedGrams: estimatedGrams,
                                   assumptions: assumptions + ["Model estimate — editable fallback, not a verified database value."])
    }

    private func validatedResolution(values: NutritionValues, provenance: NutritionProvenance,
                                     sourceRecordID: String?, servingAmount: Double, servingUnit: String,
                                     estimatedGrams: Double?, assumptions: [String]) -> NutritionResolution {
        let serving = ServingUnit(rawValue: servingUnit)
        let report = validation.validate(rawValues: values, canonicalFoodID: sourceRecordID,
                                         quantity: servingAmount, servingUnit: serving,
                                         estimatedWeightGrams: estimatedGrams)
        let safeValues = report.safeValues ?? .unavailable
        let resolvedAssumptions = assumptions + report.issues.map(\.message)
        return NutritionResolution(
            lookup: NutritionLookup(values: safeValues, provenance: report.isApproved ? provenance : .unavailable),
            sourceRecordID: report.isApproved ? sourceRecordID : nil,
            servingAmount: servingAmount, servingUnit: servingUnit,
            estimatedGrams: estimatedGrams, assumptions: resolvedAssumptions,
            verified: report.isApproved && !safeValues.isEmpty
        )
    }
}

/// Last-resort, traceable nutrition for a recognised food after the backend
/// interpretation path has been attempted. This is intentionally a curated
/// ingredient/category estimate, never a language-model nutrition answer.
struct CuratedNutritionFallbackService: Sendable {
    let catalog: IndianFoodCatalogService
    let portions: StandardPortionEstimationService
    let validation: any NutritionValidationService

    init(catalog: IndianFoodCatalogService = IndianFoodCatalogService(),
         portions: StandardPortionEstimationService = .init(),
         validation: any NutritionValidationService = DefaultNutritionValidationService()) {
        self.catalog = catalog
        self.portions = portions
        self.validation = validation
    }

    func resolve(item: ParsedFoodItem, canonical: CanonicalFoodMatch?) -> NutritionResolution {
        guard let canonical else {
            return unavailable(item: item, assumptions: ["No canonical food identity was available for the curated fallback."])
        }
        guard canonical.food.category != .unknown else {
            return unavailable(item: item, assumptions: ["The food category is too broad for a safe curated estimate."])
        }
        let amount = item.quantity ?? 1
        let servingUnit = ServingUnit(rawValue: item.unit ?? "") ?? canonical.food.standardServing?.unit ?? .serving
        let grams = item.estimatedGrams
            ?? portions.estimatedWeight(quantity: amount, unit: servingUnit, food: canonical.food)
            ?? canonical.food.standardServing?.grams
            ?? 200

        let values: NutritionValues
        let assumptions: [String]
        let ingredientFoods = canonical.food.commonIngredients.compactMap(ingredientFood)
            .filter { $0.nutritionPer100Grams != nil }
        if !ingredientFoods.isEmpty {
            let gramsPerIngredient = grams / Double(ingredientFoods.count)
            values = NutritionValues.total(of: ingredientFoods.map { food in
                food.nutritionPer100Grams?.scaled(by: gramsPerIngredient / 100) ?? .unavailable
            })
            assumptions = [
                "Calculated from curated ingredient records for \(canonical.food.canonicalName).",
                "Ingredient weights are distributed evenly because the recipe ratio was not provided."
            ]
        } else {
            values = genericValues(for: canonical.food.category, grams: grams)
            assumptions = [
                "Using a curated generic \(canonical.food.category.rawValue) estimate because no complete food record was available.",
                "Serving size is editable before confirmation."
            ]
        }

        let report = validation.validate(rawValues: values, canonicalFoodID: canonical.food.canonicalId,
                                         quantity: amount, servingUnit: servingUnit, estimatedWeightGrams: grams)
        let safe = report.safeValues ?? .unavailable
        return NutritionResolution(
            lookup: NutritionLookup(
                values: safe,
                provenance: report.isApproved
                    ? NutritionProvenance(kind: .curatedRecipeEstimate, dataSource: "Diafit curated fallback", dataVersion: catalog.version, confidence: .low)
                    : .unavailable
            ),
            sourceRecordID: report.isApproved ? canonical.food.canonicalId : nil,
            servingAmount: amount,
            servingUnit: servingUnit.rawValue,
            estimatedGrams: grams,
            assumptions: assumptions + report.issues.map(\.message),
            verified: report.isApproved && !safe.isEmpty
        )
    }

    private func unavailable(item: ParsedFoodItem, assumptions: [String]) -> NutritionResolution {
        NutritionResolution(lookup: NutritionLookup(values: .unavailable, provenance: .unavailable),
                             sourceRecordID: nil, servingAmount: item.quantity ?? 1,
                             servingUnit: item.unit ?? "serving", estimatedGrams: item.estimatedGrams,
                             assumptions: assumptions, verified: false)
    }

    private func ingredientFood(_ ingredient: String) -> IndianFoodDefinition? {
        if let exact = catalog.normalise(ingredient) { return exact }
        let normalized = ingredient.lowercased()
        if normalized.contains("lentil") || normalized.contains("pea") || normalized.contains("dal") {
            return catalog.foods.first { $0.category == .lentilOrLegume && $0.nutritionPer100Grams != nil }
        }
        if normalized.contains("rice") {
            return catalog.foods.first { $0.category == .rice && $0.nutritionPer100Grams != nil }
        }
        return nil
    }

    private func genericValues(for category: FoodCategory, grams: Double) -> NutritionValues {
        let per100: NutritionValues
        switch category {
        case .rice: per100 = NutritionValues(caloriesKcal: 130, proteinGrams: 2.4, carbohydrateGrams: 28, fatGrams: 0.3, fibreGrams: 0.4)
        case .lentilOrLegume: per100 = NutritionValues(caloriesKcal: 120, proteinGrams: 8, carbohydrateGrams: 20, fatGrams: 1.5, fibreGrams: 6)
        case .bread: per100 = NutritionValues(caloriesKcal: 280, proteinGrams: 8, carbohydrateGrams: 45, fatGrams: 8, fibreGrams: 3)
        case .dairyOrSide: per100 = NutritionValues(caloriesKcal: 90, proteinGrams: 4, carbohydrateGrams: 8, fatGrams: 4, fibreGrams: 1)
        case .dessertOrDrink: per100 = NutritionValues(caloriesKcal: 65, proteinGrams: 2, carbohydrateGrams: 10, fatGrams: 2, fibreGrams: 0)
        case .supplement: per100 = NutritionValues(caloriesKcal: 380, proteinGrams: 75, carbohydrateGrams: 10, fatGrams: 6, fibreGrams: 1)
        default: per100 = NutritionValues(caloriesKcal: 140, proteinGrams: 5, carbohydrateGrams: 18, fatGrams: 5, fibreGrams: 3)
        }
        return per100.scaled(by: grams / 100)
    }
}

// MARK: - Recipe calculation and clarification

struct RecipeIngredient: Hashable, Sendable {
    var canonicalSearchName: String
    var quantity: Double
    var unit: String
}

protocol RecipeCalculationService: Sendable {
    func calculate(ingredients: [RecipeIngredient]) async -> NutritionResolution
}

struct CatalogRecipeCalculationService: RecipeCalculationService, Sendable {
    let resolver: HybridNutritionResolutionService
    init(resolver: HybridNutritionResolutionService = .init()) { self.resolver = resolver }
    func calculate(ingredients: [RecipeIngredient]) async -> NutritionResolution {
        var values: [NutritionValues] = []
        var assumptions: [String] = []
        for ingredient in ingredients {
            let parsed = ParsedFoodItem(originalText: ingredient.canonicalSearchName, canonicalSearchName: ingredient.canonicalSearchName, quantity: ingredient.quantity, unit: ingredient.unit)
            let canonical = resolver.catalog.normalise(ingredient.canonicalSearchName).map { CanonicalFoodMatch(food: $0, matchedAlias: ingredient.canonicalSearchName, confidence: 0.8, source: "local-canonical-catalog") }
            let result = await resolver.resolve(item: parsed, canonical: canonical)
            values.append(result.lookup.values); assumptions.append(contentsOf: result.assumptions)
        }
        let total = NutritionValues.total(of: values)
        return NutritionResolution(lookup: NutritionLookup(values: total, provenance: NutritionProvenance(kind: .curatedRecipeEstimate, dataSource: "ingredient calculation", dataVersion: resolver.catalog.version, confidence: .medium)), sourceRecordID: nil, servingAmount: 1, servingUnit: "recipe", estimatedGrams: nil, assumptions: assumptions, verified: !total.isEmpty)
    }
}

protocol MealClarificationService: Sendable {
    func questions(for parse: MealParseResult, matches: [CanonicalFoodMatch]) -> [String]
}

struct DefaultMealClarificationService: MealClarificationService, Sendable {
    func questions(for parse: MealParseResult, matches: [CanonicalFoodMatch]) -> [String] {
        var questions = parse.clarificationQuestions
        if parse.detectedItems.contains(where: { $0.canonicalSearchName.localizedCaseInsensitiveContains("whey") && $0.unit == nil }) {
            questions.append("How many scoops, and was it mixed with water or milk?")
        }
        if matches.count < parse.detectedItems.count { questions.append("What food or packaged product should I use for the unmatched item?") }
        return Array(NSOrderedSet(array: questions)) as? [String] ?? questions
    }
}

// MARK: - Resolution routing

enum FoodInterpretationRoute: String, Codable, Hashable, Sendable {
    case userSavedFood
    case userSavedRecipe
    case exactLocal
    case localAlias
    case localTransliteration
    case localFuzzy
    case openAI
    case clarificationRequired
    case unavailable
}

enum FoodNutritionRoute: String, Codable, Hashable, Sendable {
    case packagedLabel
    case userSavedFood
    case verifiedProvider
    case curatedLocal
    case recipeCalculated
    case modelEstimate
    case clarificationRequired
    case unavailable
}

/// Explicit lifecycle states keep a recognised name from being mistaken for a
/// nutrition resolution. A local catalog hit can still require interpretation,
/// recipe calculation, or a provider-backed retry.
enum FoodResolutionState: Equatable, Sendable {
    case inputReceived
    case checkingUserFoods
    case checkingLocalData
    case localCandidateFound
    case evaluatingCompleteness
    case requiresAIInterpretation
    case callingBackend
    case interpretingFood
    case resolvingNutrition
    case calculatingRecipe
    case validatingNutrition
    case clarificationRequired
    case readyForReview
    case unavailable(ResolutionFailure)
}

enum ResolutionFailure: String, Equatable, Sendable {
    case backendUnavailable
    case malformedAIResponse
    case nutritionProviderUnavailable
    case incompleteNutrition
    case invalidNutrition
    case unknownFood
}

struct FoodResolutionCompletenessReport: Equatable, Sendable {
    let isComplete: Bool
    let missingRequirements: [String]

    static let complete = FoodResolutionCompletenessReport(isComplete: true, missingRequirements: [])
}

/// The central gate used after every candidate nutrition lookup. Display names,
/// IDs, quantities, and serving labels are not sufficient for a successful
/// resolution; core nutrients and traceable provenance must also be present.
struct FoodResolutionCompletenessEvaluator: Sendable {
    func evaluate(_ item: FoodResolutionItem) -> FoodResolutionCompletenessReport {
        var missing: [String] = []
        if item.canonical == nil { missing.append("canonical food identity") }

        let parsed = item.parsedItem
        guard let quantity = parsed.quantity, quantity.isFinite, quantity > 0 else {
            missing.append("quantity")
            return FoodResolutionCompletenessReport(isComplete: false, missingRequirements: missing)
        }
        if parsed.unit?.isEmpty != false { missing.append("serving unit") }
        if let grams = item.nutrition.estimatedGrams {
            if !grams.isFinite || grams <= 0 { missing.append("serving conversion") }
        } else {
            missing.append("serving conversion")
        }

        let values = item.nutrition.lookup.values
        if values.caloriesKcal == nil { missing.append("calories") }
        if values.carbohydrateGrams == nil { missing.append("carbohydrates") }
        if values.proteinGrams == nil { missing.append("protein") }
        if item.nutrition.lookup.provenance.kind == .unavailable { missing.append("nutrition source") }
        if !item.nutrition.verified { missing.append("nutrition validation") }

        return FoodResolutionCompletenessReport(
            isComplete: missing.isEmpty,
            missingRequirements: Array(NSOrderedSet(array: missing)) as? [String] ?? missing
        )
    }

    func evaluate(_ items: [FoodResolutionItem]) -> FoodResolutionCompletenessReport {
        guard !items.isEmpty else {
            return FoodResolutionCompletenessReport(isComplete: false, missingRequirements: ["food component"])
        }
        let reports = items.map(evaluate)
        let missing = reports.flatMap(\.missingRequirements)
        return FoodResolutionCompletenessReport(
            isComplete: reports.allSatisfy(\.isComplete),
            missingRequirements: Array(NSOrderedSet(array: missing)) as? [String] ?? missing
        )
    }
}

struct FoodResolutionItem: Sendable {
    let parsedItem: ParsedFoodItem
    let canonical: CanonicalFoodMatch?
    let nutrition: NutritionResolution
    let interpretationRoute: FoodInterpretationRoute
    let nutritionRoute: FoodNutritionRoute
}

struct FoodResolutionResult: Sendable {
    let originalInput: String
    let normalizedInput: String
    let items: [FoodResolutionItem]
    let unresolvedTerms: [String]
    let clarificationQuestions: [String]
    let overallConfidence: Double
    let state: FoodResolutionState

    var hasUsableNutrition: Bool { !items.isEmpty && items.allSatisfy { !$0.nutrition.lookup.values.isEmpty } }
    var requiresClarification: Bool { !clarificationQuestions.isEmpty || !unresolvedTerms.isEmpty || !hasUsableNutrition }
}

protocol FoodResolutionRouter: Sendable {
    func resolve(text: String) async -> FoodResolutionResult
    func resolve(parse: MealParseResult, originalInput: String) async -> FoodResolutionResult
}

/// Routes deterministic, user-confirmed and catalog matches before falling
/// through to structured backend interpretation. The router is deliberately
/// independent of SwiftUI and can be exercised with mock providers.
struct DefaultFoodResolutionRouter: FoodResolutionRouter, Sendable {
    let catalog: IndianFoodCatalogService
    let normalisation: HybridFoodNormalisationService
    let understanding: (any FoodUnderstandingService)?
    let nutrition: any NutritionResolutionService
    let clarification: any MealClarificationService
    let memory: (any UserFoodMemoryRepository)?

    init(catalog: IndianFoodCatalogService = IndianFoodCatalogService(),
         normalisation: HybridFoodNormalisationService? = nil,
         understanding: (any FoodUnderstandingService)? = nil,
         nutrition: any NutritionResolutionService = HybridNutritionResolutionService(),
         clarification: any MealClarificationService = DefaultMealClarificationService(),
         memory: (any UserFoodMemoryRepository)? = nil,
         fallback: CuratedNutritionFallbackService? = nil) {
        self.catalog = catalog
        self.normalisation = normalisation ?? HybridFoodNormalisationService(catalog: catalog)
        self.understanding = understanding
        self.nutrition = nutrition
        self.clarification = clarification
        self.memory = memory
        self.fallback = fallback ?? CuratedNutritionFallbackService(catalog: catalog)
    }

    let fallback: CuratedNutritionFallbackService
    let completeness = FoodResolutionCompletenessEvaluator()

    func resolve(parse: MealParseResult, originalInput: String) async -> FoodResolutionResult {
        let normalized = normalize(originalInput)
        let resolved = await resolveAI(parse).map { completeWithCuratedFallback($0) }
        let matches = resolved.compactMap(\.canonical)
        let questions = clarification.questions(for: parse, matches: matches)
            + localQuestions(for: resolved, input: normalized)
        let unresolved = parse.unresolvedItems
            + resolved.filter { $0.canonical == nil }.map { $0.parsedItem.originalText }
        return result(
            text: originalInput,
            normalized: normalized,
            items: resolved,
            unresolved: Array(Set(unresolved)),
            extraQuestions: questions,
            attemptedAI: true
        )
    }

    func resolve(text: String) async -> FoodResolutionResult {
        let normalized = normalize(text)
        guard !normalized.isEmpty else {
            return FoodResolutionResult(originalInput: text, normalizedInput: normalized, items: [], unresolvedTerms: [], clarificationQuestions: ["What did you eat or drink?"], overallConfidence: 0, state: .clarificationRequired)
        }

        if let memory, let remembered = await memory.rankedMatches(for: normalized).first,
           let food = catalog.food(canonicalID: remembered.canonicalFoodID) {
            let parsed = ParsedFoodItem(originalText: text, canonicalSearchName: food.englishName,
                                        regionalName: remembered.alias, quantity: remembered.servingGrams.map { _ in 1 },
                                        unit: remembered.servingUnit ?? food.standardServing?.unit.rawValue ?? "serving",
                                        estimatedGrams: remembered.servingGrams, preparationMethod: remembered.preparation)
            let match = CanonicalFoodMatch(food: food, matchedAlias: remembered.alias, confidence: 0.99, source: "user-confirmed-memory")
            let nutrition = await self.nutrition.resolve(item: parsed, canonical: match)
            return result(text: text, normalized: normalized, items: [resolvedItem(parsed, match, nutrition, .userSavedFood)], unresolved: [], extraQuestions: [], attemptedAI: false)
        }

        let trace = FoodUnderstandingPipeline(catalog: catalog).parse(text)
        if !trace.components.isEmpty, trace.components.allSatisfy({ $0.confidenceScore >= 0.8 }) {
            let resolved = await resolveLocal(trace.components)
            let completeness = completeness.evaluate(resolved)
            if completeness.isComplete {
                let questions = localQuestions(for: resolved, input: normalized)
                return result(text: text, normalized: normalized, items: resolved, unresolved: [], extraQuestions: questions, attemptedAI: false)
            }
            FoodLoggingDiagnostics.record("resolution.completeness", fields: [
                "status": "requires-ai",
                "missing": completeness.missingRequirements.joined(separator: ",")
            ])
            if let understanding {
                return await resolveIncompleteLocal(text: text, normalized: normalized, local: resolved, understanding: understanding)
            }
            let fallbackItems = resolved.map { completeWithCuratedFallback($0) }
            return result(text: text, normalized: normalized, items: fallbackItems, unresolved: [],
                          extraQuestions: localQuestions(for: fallbackItems, input: normalized), attemptedAI: true)
        }

        // A broad alias/fuzzy pass catches transliterations and phrases that
        // the span parser cannot safely attach quantities to. It is only used
        // when every selected match clears the conservative 0.78 threshold.
        let fuzzyMatches = normalisation.matches(in: text)
        if !fuzzyMatches.isEmpty {
            let resolved = await resolveMatches(fuzzyMatches, input: text, route: .localFuzzy)
            let completeness = completeness.evaluate(resolved)
            if resolved.allSatisfy({ ($0.canonical?.confidence ?? 0) >= 0.78 }) && completeness.isComplete {
                return result(text: text, normalized: normalized, items: resolved, unresolved: [], extraQuestions: localQuestions(for: resolved, input: normalized))
            }
        }

        if let understanding {
            do {
                let parse = try await understanding.parse(text: text, image: nil)
                let resolved = await resolveAI(parse)
                let matches = resolved.compactMap(\.canonical)
                let questions = clarification.questions(for: parse, matches: matches) + localQuestions(for: resolved, input: normalized)
                let unresolved = parse.unresolvedItems + resolved.filter { $0.canonical == nil }.map { $0.parsedItem.originalText }
                let completed = resolved.map { completeWithCuratedFallback($0) }
                return result(text: text, normalized: normalized, items: completed, unresolved: Array(Set(unresolved)), extraQuestions: questions, attemptedAI: true)
            } catch {
                FoodLoggingDiagnostics.record("resolution.ai", fields: ["status": "unavailable", "reason": "provider-error"])
            }
        }

        return FoodResolutionResult(originalInput: text, normalizedInput: normalized, items: [], unresolvedTerms: [text], clarificationQuestions: ["I couldn't identify that safely. What food or product should I use?"], overallConfidence: 0.1, state: .unavailable(.unknownFood))
    }

    private func resolveIncompleteLocal(text: String, normalized: String, local: [FoodResolutionItem], understanding: any FoodUnderstandingService) async -> FoodResolutionResult {
        do {
            let parse = try await understanding.parse(text: text, image: nil)
            let aiItems = await resolveAI(parse).map { completeWithCuratedFallback($0) }
            let questions = clarification.questions(for: parse, matches: aiItems.compactMap(\.canonical))
                + localQuestions(for: aiItems, input: normalized)
            let unresolved = parse.unresolvedItems + aiItems.filter { $0.canonical == nil }.map { $0.parsedItem.originalText }
            return result(text: text, normalized: normalized, items: aiItems, unresolved: Array(Set(unresolved)), extraQuestions: questions, attemptedAI: true)
        } catch {
            FoodLoggingDiagnostics.record("resolution.ai", fields: ["status": "unavailable", "reason": "provider-error", "fallback": "curated"])
            let fallbackItems = local.map { completeWithCuratedFallback($0) }
            return result(text: text, normalized: normalized, items: fallbackItems, unresolved: [],
                          extraQuestions: localQuestions(for: fallbackItems, input: normalized), attemptedAI: true)
        }
    }

    private func completeWithCuratedFallback(_ item: FoodResolutionItem) -> FoodResolutionItem {
        guard !completeness.evaluate(item).isComplete else { return item }
        let nutrition = fallback.resolve(item: item.parsedItem, canonical: item.canonical)
        return resolvedItem(item.parsedItem, item.canonical, nutrition, item.interpretationRoute)
    }

    private func resolveLocal(_ components: [ParsedFoodComponent]) async -> [FoodResolutionItem] {
        await withTaskGroup(of: FoodResolutionItem?.self, returning: [FoodResolutionItem].self) { group in
            for component in components {
                group.addTask {
                    let parsed = ParsedFoodItem(originalText: component.matchedAlias,
                                                canonicalSearchName: component.food.englishName,
                                                regionalName: component.food.regionalNames.first,
                                                quantity: component.quantity,
                                                unit: component.servingUnit.rawValue,
                                                estimatedGrams: nil,
                                                preparationMethod: component.preparationMethod,
                                                additions: component.modifiers)
                    let match = CanonicalFoodMatch(food: component.food, matchedAlias: component.matchedAlias,
                                                   confidence: component.confidenceScore, source: "local-canonical-catalog")
                    let nutrition = await self.nutrition.resolve(item: parsed, canonical: match)
                    return self.resolvedItem(parsed, match, nutrition, self.route(for: component))
                }
            }
            var output: [FoodResolutionItem] = []
            for await item in group { if let item { output.append(item) } }
            return output
        }
    }

    private func resolveMatches(_ foods: [IndianFoodDefinition], input: String, route: FoodInterpretationRoute) async -> [FoodResolutionItem] {
        await withTaskGroup(of: FoodResolutionItem?.self, returning: [FoodResolutionItem].self) { group in
            for food in foods {
                group.addTask {
                    let parsed = ParsedFoodItem(originalText: food.canonicalName, canonicalSearchName: food.englishName,
                                                quantity: food.standardServing?.quantity ?? 1,
                                                unit: food.standardServing?.unit.rawValue ?? "serving")
                    let match = CanonicalFoodMatch(food: food, matchedAlias: food.canonicalName, confidence: 0.8, source: "local-fuzzy-catalog")
                    let nutrition = await self.nutrition.resolve(item: parsed, canonical: match)
                    return self.resolvedItem(parsed, match, nutrition, route)
                }
            }
            var output: [FoodResolutionItem] = []
            for await item in group { if let item { output.append(item) } }
            return output
        }
    }

    private func resolveAI(_ parse: MealParseResult) async -> [FoodResolutionItem] {
        await withTaskGroup(of: FoodResolutionItem?.self, returning: [FoodResolutionItem].self) { group in
            for parsed in parse.detectedItems {
                group.addTask {
                    let match = await self.normalisation.match(parsed, memory: self.memory)
                    let nutrition = await self.nutrition.resolve(item: parsed, canonical: match)
                    return self.resolvedItem(parsed, match, nutrition, .openAI)
                }
            }
            var output: [FoodResolutionItem] = []
            for await item in group { if let item { output.append(item) } }
            return output
        }
    }

    private func resolvedItem(_ parsed: ParsedFoodItem, _ canonical: CanonicalFoodMatch?, _ nutrition: NutritionResolution, _ route: FoodInterpretationRoute) -> FoodResolutionItem {
        let nutritionRoute: FoodNutritionRoute
        switch nutrition.lookup.provenance.kind {
        case .packagedLabel: nutritionRoute = .packagedLabel
        case .verifiedDatabase: nutritionRoute = .verifiedProvider
        case .curatedRecipeEstimate, .userCreated: nutritionRoute = .curatedLocal
        case .modelFallback: nutritionRoute = .modelEstimate
        case .unavailable: nutritionRoute = .unavailable
        }
        return FoodResolutionItem(parsedItem: parsed, canonical: canonical, nutrition: nutrition,
                                  interpretationRoute: route,
                                  nutritionRoute: nutrition.verified ? nutritionRoute : (nutrition.lookup.values.isEmpty ? .clarificationRequired : nutritionRoute))
    }

    private func route(for component: ParsedFoodComponent) -> FoodInterpretationRoute {
        let query = normalize(component.matchedAlias)
        let food = component.food
        if normalize(food.canonicalName) == query || normalize(food.englishName) == query { return .exactLocal }
        if food.transliterations.contains(where: { normalize($0) == query }) { return .localTransliteration }
        return .localAlias
    }

    private func localQuestions(for items: [FoodResolutionItem], input: String) -> [String] {
        var questions: [String] = []
        if items.contains(where: { $0.canonical?.food.canonicalId == "chai" }) { questions.append("Was the chai sweetened, and approximately how much milk was used?") }
        if items.contains(where: { $0.canonical?.food.canonicalId == "tea" }) { questions.append("Was the tea plain, or did it include milk or sugar?") }
        if items.contains(where: { $0.canonical?.food.canonicalId == "paratha" }) { questions.append("Was the paratha plain, stuffed or buttered?") }
        if items.contains(where: { $0.canonical?.food.canonicalId == "kadhi" }) { questions.append("Was it plain kadhi or kadhi with pakoras?") }
        if items.contains(where: { $0.parsedItem.canonicalSearchName.localizedCaseInsensitiveContains("whey") && !$0.parsedItem.additions.contains(where: { ["water", "milk"].contains($0) }) }) { questions.append("How many scoops, and was it mixed with water or milk?") }
        return Array(NSOrderedSet(array: questions)) as? [String] ?? questions
    }

    private func result(text: String, normalized: String, items: [FoodResolutionItem], unresolved: [String], extraQuestions: [String], attemptedAI: Bool = false) -> FoodResolutionResult {
        let reviewAssumptions = items.reduce(into: [String]()) { partial, item in
            partial.append(contentsOf: item.nutrition.assumptions.filter { $0.localizedCaseInsensitiveContains("review") })
        }
        let questions = Array(NSOrderedSet(array: extraQuestions + reviewAssumptions)) as? [String] ?? extraQuestions
        let confidence = items.map { $0.parsedItem.confidence }.min() ?? 0
        FoodLoggingDiagnostics.record("resolution.route", fields: [
            "inputFingerprint": FoodLoggingDiagnostics.fingerprint(text),
            "interpretation": items.map { $0.interpretationRoute.rawValue }.joined(separator: ","),
            "nutrition": items.map { $0.nutritionRoute.rawValue }.joined(separator: ","),
            "unresolvedCount": String(unresolved.count),
            "clarificationCount": String(questions.count)
        ])
        let report = completeness.evaluate(items)
        let state: FoodResolutionState
        if !questions.isEmpty || !unresolved.isEmpty {
            state = .clarificationRequired
        } else if report.isComplete {
            state = .readyForReview
        } else if attemptedAI {
            state = .unavailable(.incompleteNutrition)
        } else {
            state = .requiresAIInterpretation
        }
        return FoodResolutionResult(originalInput: text, normalizedInput: normalized, items: items,
                                    unresolvedTerms: unresolved, clarificationQuestions: questions,
                                    overallConfidence: confidence, state: state)
    }

    private func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: " ")
    }
}

/// Converts the provider-independent resolution model into the existing
/// editable diary draft. This keeps the UI model stable while allowing the
/// router to evolve independently of SwiftUI.
struct HybridMealAnalysisCoordinator: Sendable {
    let router: any FoodResolutionRouter

    init(router: any FoodResolutionRouter = DefaultFoodResolutionRouter()) {
        self.router = router
    }

    func analyse(text: String, imageReference: MealImageReference = .transient()) async -> MealAnalysisResult {
        let resolution = await router.resolve(text: text)
        return makeAnalysis(from: resolution, imageReference: imageReference, imageType: .noImage)
    }

    func analyse(
        parse: MealParseResult,
        originalInput: String,
        imageReference: MealImageReference,
        imageType: MealImageType
    ) async -> MealAnalysisResult {
        let resolution = await router.resolve(parse: parse, originalInput: originalInput)
        return makeAnalysis(from: resolution, imageReference: imageReference, imageType: imageType)
    }

    private func makeAnalysis(
        from resolution: FoodResolutionResult,
        imageReference: MealImageReference,
        imageType: MealImageType
    ) -> MealAnalysisResult {
        let items = resolution.items.compactMap(makeDetectedItem)
        let totals = NutritionValues.total(of: items.map(\.nutrition))
        let validation = DefaultNutritionValidationService().validate(rawValues: totals)
        let questions = resolution.clarificationQuestions.map {
            ClarificationQuestion(id: UUID(), relatedFoodItemId: nil, question: $0,
                                  answerType: .freeText, options: [], impactLevel: .high, answer: nil)
        }
        let analysisID = UUID()
        let visualRequest = MealVisualRequestBuilder().make(mealID: analysisID, items: items, clarificationQuestions: questions)
        let provenance = items.first?.nutritionProvenance ?? .unavailable
        var warnings = resolution.unresolvedTerms.isEmpty ? ["Review the editable serving before saving."] : ["Some terms need confirmation before they can be logged."]
        if items.contains(where: { $0.nutrition.isEmpty }) { warnings.append("Nutrition unavailable. Confirm the food or enter the nutrition manually.") }
        if !validation.isApproved { warnings.append(contentsOf: validation.issues.map(\.message)) }
        return MealAnalysisResult(
            analysisId: analysisID,
            imageReference: imageReference,
            imageType: imageType,
            detectedItems: items,
            mealTotals: validation.safeValues ?? .unavailable,
            overallConfidence: items.map(\.confidence).min(by: confidenceOrder) ?? .low,
            assumptions: items.flatMap(\.assumptions),
            clarificationQuestions: questions,
            warnings: warnings,
            createdAt: .now,
            recognitionModelVersion: items.contains(where: { $0.matchedAlias == nil }) ? "local-router" : nil,
            nutritionDatabaseVersion: provenance.dataVersion,
            glycaemicDatabaseVersion: nil,
            nutritionProvenance: provenance,
            nutritionValidation: validation,
            visualRequest: visualRequest
        )
    }

    private func makeDetectedItem(_ resolved: FoodResolutionItem) -> DetectedFoodItem? {
        guard let canonical = resolved.canonical else { return nil }
        let parsed = resolved.parsedItem
        let unit = servingUnit(for: parsed.unit, food: canonical.food)
        let quantity = parsed.quantity ?? 1
        let values = resolved.nutrition.lookup.values
        return DetectedFoodItem(
            id: UUID(), canonicalFoodId: canonical.food.canonicalId,
            displayName: canonical.food.canonicalName,
            regionalName: parsed.regionalName ?? canonical.food.regionalNames.first,
            category: canonical.food.category,
            confidence: parsed.confidence >= 0.9 ? .high : parsed.confidence >= 0.75 ? .medium : .low,
            alternatives: [], quantity: quantity, servingUnit: unit,
            estimatedWeightGrams: resolved.nutrition.estimatedGrams,
            visibleIngredients: [], inferredIngredients: canonical.food.commonIngredients,
            possibleIngredients: [], preparationMethod: parsed.preparationMethod,
            nutrition: values, glycaemicInformation: .unavailable,
            assumptions: resolved.nutrition.assumptions + ["Serving is editable before confirmation."],
            warnings: values.isEmpty ? ["Nutrition unavailable. Confirm the food or enter the nutrition manually."] : [],
            boundingRegion: nil, nutritionProvenance: resolved.nutrition.lookup.provenance,
            rawNutrition: values, nutritionValidation: nil,
            matchedAlias: resolved.interpretationRoute == .openAI ? nil : resolved.parsedItem.originalText,
            confidenceScore: parsed.confidence, modifiers: parsed.additions
        )
    }

    private func servingUnit(for raw: String?, food: IndianFoodDefinition) -> ServingUnit {
        guard let raw else { return food.standardServing?.unit ?? .serving }
        if let unit = ServingUnit(rawValue: raw) { return unit }
        switch raw.lowercased() {
        case "whole", "whole egg", "egg", "eggs": return .wholeEgg
        case "medium bowl", "bowl": return .mediumBowl
        case "small bowl": return .smallBowl
        case "large bowl": return .largeBowl
        case "ml", "millilitre", "millilitres", "milliliter", "milliliters": return .millilitres
        case "cup", "cups": return .cup
        case "glass", "glasses": return .glass
        case "piece", "pieces": return .piece
        case "scoop", "scoops": return .scoop
        default: return food.standardServing?.unit ?? .serving
        }
    }

    private func confidenceOrder(_ lhs: ConfidenceLevel, _ rhs: ConfidenceLevel) -> Bool {
        let rank: [ConfidenceLevel: Int] = [.high: 4, .medium: 3, .low: 2, .unknown: 1]
        return rank[lhs, default: 0] < rank[rhs, default: 0]
    }
}
