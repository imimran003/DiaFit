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
        for phrase in description.split(whereSeparator: { ",;+".contains($0) }) {
            if let food = normalise(String(phrase)), !result.contains(where: { $0.id == food.id }) { result.append(food) }
        }
        return result.isEmpty ? catalog.matches(in: description) : result
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
