import Foundation
import ImageIO
import Vision

// MARK: - Provider seams

protocol FoodRecognitionService: Sendable {
    func analyse(_ image: PreparedFoodImage, dishHint: String?) async throws -> MealAnalysisResult
}

struct FoodImageCandidate: Hashable, Sendable {
    let canonicalFoodId: String
    let sourceLabel: String
    let confidence: Double
}

/// Produces food identity candidates only. Nutrition is deliberately resolved
/// afterwards from canonical records; an image classifier is never treated as
/// a nutrition database.
protocol FoodImageClassificationService: Sendable {
    func candidates(in image: PreparedFoodImage) async throws -> [FoodImageCandidate]
}

protocol FoodNormalisationService: Sendable {
    func normalise(_ query: String) -> IndianFoodDefinition?
    func matches(in description: String) -> [IndianFoodDefinition]
}

protocol NutritionLookupService: Sendable {
    func nutrition(for food: IndianFoodDefinition, estimatedWeightGrams: Double?) -> NutritionLookup
}

protocol GlycaemicDataService: Sendable {
    func information(for food: IndianFoodDefinition, availableCarbohydrateGrams: Double?) -> GlycaemicInformation
}

protocol PortionEstimationService: Sendable {
    func estimatedWeight(quantity: Double, unit: ServingUnit, food: IndianFoodDefinition) -> Double?
}

protocol MealAnalysisRepository: Sendable {
    func saveDraft(_ draft: MealAnalysisDraft) async
    func draft(id: UUID) async -> MealAnalysisDraft?
    func removeDraft(id: UUID) async
}

protocol MealLoggingService: Sendable {
    @MainActor func confirm(_ draft: MealAnalysisDraft, replacing itemID: ThreadItem.ID, in store: DiaryStore, dayID: Day.ID) -> Meal
    @MainActor func update(_ meal: Meal, in store: DiaryStore, dayID: Day.ID)
    @MainActor func delete(mealID: Meal.ID, in store: DiaryStore, dayID: Day.ID)
}

protocol ImageCompressionService: Sendable {
    func prepare(imageData: Data) throws -> PreparedFoodImage
}

protocol GeneratedMealImageService: Sendable {
    func cachedEditorialImage(for key: GeneratedMealImageKey) async -> URL?
}

protocol AgentToolService: Sendable {
    func draftFromDescription(_ description: String, imageReference: MealImageReference, imageType: MealImageType) async -> MealAnalysisResult
}

struct PreparedFoodImage: Sendable {
    let data: Data
    let mimeType: String
    let pixelWidth: Int
    let pixelHeight: Int
    let imageReference: MealImageReference
}

struct NutritionLookup: Sendable {
    let values: NutritionValues
    let provenance: NutritionProvenance
}

/// Private, offline fast path for ordinary food photos. Vision suggestions are
/// admitted only when they map to the canonical catalog and clear a conservative
/// confidence threshold. A configured backend remains the preferred provider
/// for mixed meals and portion-aware interpretation.
struct AppleFoodImageClassificationService: FoodImageClassificationService, Sendable {
    let catalog: IndianFoodCatalogService
    let minimumConfidence: Float

    init(catalog: IndianFoodCatalogService = IndianFoodCatalogService(), minimumConfidence: Float = 0.20) {
        self.catalog = catalog
        self.minimumConfidence = minimumConfidence
    }

    func candidates(in image: PreparedFoodImage) async throws -> [FoodImageCandidate] {
        let observations = try await classify(image.data)
        var bestByCanonicalID: [String: FoodImageCandidate] = [:]

        for observation in observations where observation.confidence >= minimumConfidence {
            for food in catalog.matches(in: observation.identifier) {
                let candidate = FoodImageCandidate(
                    canonicalFoodId: food.canonicalId,
                    sourceLabel: observation.identifier,
                    confidence: Double(observation.confidence)
                )
                if candidate.confidence > (bestByCanonicalID[food.canonicalId]?.confidence ?? 0) {
                    bestByCanonicalID[food.canonicalId] = candidate
                }
            }
        }

        return bestByCanonicalID.values
            .sorted { lhs, rhs in
                if lhs.confidence == rhs.confidence { return lhs.canonicalFoodId < rhs.canonicalFoodId }
                return lhs.confidence > rhs.confidence
            }
            .prefix(5)
            .map { $0 }
    }

    private func classify(_ data: Data) async throws -> [VNClassificationObservation] {
        try await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw FoodAnalysisError.unsupportedImage
            }
            let request = VNClassifyImageRequest()
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            return Array((request.results ?? []).prefix(30))
        }.value
    }
}

struct GeneratedMealImageKey: Hashable, Sendable {
    let canonicalFoodId: String
    let variation: String
    let visualStyleVersion: String
}

enum FoodAnalysisError: LocalizedError {
    case endpointUnavailable
    case malformedProviderResponse
    case unsupportedImage
    case imageTooLarge
    case unauthenticatedBackend

    var errorDescription: String? {
        switch self {
        case .endpointUnavailable: return "Photo analysis is unavailable right now. You can still describe or search for the meal."
        case .malformedProviderResponse: return "The analysis response could not be safely read. Nothing was logged."
        case .unsupportedImage: return "Choose a JPEG, HEIC, or PNG photo to continue."
        case .imageTooLarge: return "That photo is too large to process. Try a smaller image."
        case .unauthenticatedBackend: return "Secure photo analysis needs an authenticated account. You can still describe the meal."
        }
    }
}

protocol BackendAccessTokenProvider: Sendable {
    func accessToken() async throws -> String
}

/// Holds an already-issued account/development token in memory. It is supplied
/// by authentication or an Xcode launch environment and is never a provider key.
struct RuntimeBackendAccessTokenProvider: BackendAccessTokenProvider, Sendable {
    let token: String

    func accessToken() async throws -> String {
        guard !token.isEmpty else { throw FoodAnalysisError.unauthenticatedBackend }
        return token
    }
}

/// The app supplies an account-scoped token from its authentication layer. This
/// is deliberately not a provider key and is never persisted in app resources.
struct HTTPFoodRecognitionService: FoodRecognitionService {
    let endpoint: URL
    let tokenProvider: BackendAccessTokenProvider
    let session: URLSession

    init(endpoint: URL, tokenProvider: BackendAccessTokenProvider, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.tokenProvider = tokenProvider
        self.session = session
    }

    func analyse(_ image: PreparedFoodImage, dishHint: String?) async throws -> MealAnalysisResult {
        let token = try await tokenProvider.accessToken()
        var request = URLRequest(url: endpoint.appending(path: "v1/meal-analysis"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.httpBody = try JSONEncoder().encode(RemoteAnalysisRequest(
            apiVersion: "v1",
            imageReference: image.imageReference.identifier,
            imageBase64: image.data.base64EncodedString(),
            mimeType: image.mimeType,
            dishHint: dishHint ?? "meal photo"
        ))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw FoodAnalysisError.endpointUnavailable
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(MealAnalysisResult.self, from: data)
        } catch {
            throw FoodAnalysisError.malformedProviderResponse
        }
    }
}

private struct RemoteAnalysisRequest: Encodable {
    let apiVersion: String
    let imageReference: String
    let imageBase64: String
    let mimeType: String
    let dishHint: String
}

/// Adapts the schema-constrained meal-understanding endpoint to the existing
/// photo-review model. The backend identifies foods; canonical matching,
/// nutrition lookup and validation still happen in the app's typed services.
struct StructuredPhotoRecognitionService: FoodRecognitionService, Sendable {
    let understanding: any FoodUnderstandingService
    let coordinator: HybridMealAnalysisCoordinator

    func analyse(_ image: PreparedFoodImage, dishHint: String?) async throws -> MealAnalysisResult {
        let trimmedHint = dishHint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let instruction = trimmedHint.isEmpty
            ? "Inspect the entire meal photo and identify every distinct physical food serving exactly once. Preserve regional Indian names, include breads, rice, dal, sabji, curries and sides when visible, and never list alternative guesses as separate foods."
            : trimmedHint
        let parse = try await understanding.parse(text: instruction, image: image)
        guard !parse.detectedItems.isEmpty else { throw FoodAnalysisError.malformedProviderResponse }

        var result = await coordinator.analyse(
            parse: parse,
            originalInput: instruction,
            imageReference: image.imageReference,
            imageType: .originalPhoto
        )
        result.recognitionModelVersion = "Backend structured vision interpretation"
        result.assumptions.insert(
            "AI interpreted the visible foods; nutrition was resolved separately from canonical records and remains editable.",
            at: 0
        )
        return result
    }
}

struct PhotoAnalysisCompletenessReport: Equatable, Sendable {
    let isComplete: Bool
    let missingRequirements: [String]
}

/// A photo result is only successful when it can actually support the review
/// UI. A classifier label without serving conversion, nutrition provenance, or
/// validated core nutrients must escalate to the structured backend.
struct PhotoAnalysisCompletenessEvaluator: Sendable {
    private let validation = DefaultNutritionValidationService()

    func evaluate(_ result: MealAnalysisResult) -> PhotoAnalysisCompletenessReport {
        var missing: [String] = []
        if result.detectedItems.isEmpty { missing.append("food component") }
        if result.overallConfidence == .low || result.overallConfidence == .unknown {
            missing.append("recognition confidence")
        }

        for item in result.detectedItems {
            if item.canonicalFoodId.isEmpty || item.displayName.isEmpty { missing.append("canonical identity") }
            if !item.quantity.isFinite || item.quantity <= 0 { missing.append("quantity") }
            if item.estimatedWeightGrams.map({ !$0.isFinite || $0 <= 0 }) ?? true { missing.append("serving conversion") }
            if item.nutrition.caloriesKcal == nil
                || item.nutrition.carbohydrateGrams == nil
                || item.nutrition.proteinGrams == nil {
                missing.append("nutrition")
            }
            if item.nutritionProvenance.kind == .unavailable { missing.append("nutrition source") }
        }

        let totalValidation = result.nutritionValidation
            ?? validation.validate(rawValues: result.mealTotals)
        if !totalValidation.isApproved { missing.append("nutrition validation") }
        if result.nutritionProvenance.kind == .unavailable { missing.append("nutrition source") }

        let unique = Array(NSOrderedSet(array: missing)) as? [String] ?? missing
        return PhotoAnalysisCompletenessReport(isComplete: unique.isEmpty, missingRequirements: unique)
    }
}

struct PhotoAnalysisOrchestrator: Sendable {
    let remote: (any FoodRecognitionService)?
    let onDevice: (any FoodImageClassificationService)?
    let local: LocalMealAnalysisEngine
    let completeness: PhotoAnalysisCompletenessEvaluator

    init(
        remote: (any FoodRecognitionService)? = nil,
        onDevice: (any FoodImageClassificationService)? = AppleFoodImageClassificationService(),
        local: LocalMealAnalysisEngine = LocalMealAnalysisEngine(),
        completeness: PhotoAnalysisCompletenessEvaluator = PhotoAnalysisCompletenessEvaluator()
    ) {
        self.remote = remote
        self.onDevice = onDevice
        self.local = local
        self.completeness = completeness
    }

    func analyse(image: PreparedFoodImage, description: String) async -> MealAnalysisResult {
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidates: [FoodImageCandidate] = []
        if let onDevice {
            candidates = (try? await onDevice.candidates(in: image)) ?? []
        }
        // A member-supplied hint is more specific than a whole-image label and
        // prevents a broad classifier label from adding an unrelated component.
        let candidateNames = trimmedDescription.isEmpty
            ? candidates.compactMap { local.catalog.food(canonicalID: $0.canonicalFoodId)?.canonicalName }
            : []
        let combinedDescription = ([trimmedDescription] + candidateNames)
            .filter { !$0.isEmpty }
            .joined(separator: " with ")

        var result = local.makeAnalysis(
            description: combinedDescription,
            imageReference: image.imageReference,
            imageType: .originalPhoto
        )
        if trimmedDescription.isEmpty, !candidates.isEmpty {
            let confidenceByID = Dictionary(
                uniqueKeysWithValues: candidates.map { ($0.canonicalFoodId, $0.confidence) }
            )
            result.detectedItems = result.detectedItems.map { item in
                var updated = item
                if let score = confidenceByID[item.canonicalFoodId] {
                    updated.confidenceScore = score
                    updated.confidence = confidenceLevel(for: score)
                }
                return updated
            }
            result.overallConfidence = confidenceLevel(
                for: result.detectedItems.map(\.confidenceScore).min() ?? 0
            )
        }
        if !candidateNames.isEmpty {
            result.recognitionModelVersion = "Apple Vision on-device classification"
            result.assumptions.removeAll { $0.contains("description") || $0.contains("image was not sent") }
            result.assumptions.insert(
                "On-device image recognition suggested the visible foods. Serving sizes remain editable estimates.",
                at: 0
            )
        }
        let localCompleteness = completeness.evaluate(result)

        var remoteFailed = false
        var remoteIncomplete: MealAnalysisResult?
        if let remote {
            do {
                let remoteResult = try await remote.analyse(image, dishHint: description)
                let report = completeness.evaluate(remoteResult)
                if report.isComplete {
                    FoodLoggingDiagnostics.record("photo.classification", fields: [
                        "route": "structured-backend",
                        "candidateCount": String(remoteResult.detectedItems.count),
                        "remoteAttempted": "true",
                        "complete": "true"
                    ])
                    return remoteResult
                }
                remoteIncomplete = remoteResult
            } catch {
                remoteFailed = true
            }
        }

        // A generic whole-image classifier can produce a nutritionally complete
        // but visually wrong list. When structured vision is configured, its
        // component-aware interpretation owns food identity; on-device labels
        // are a private resilience fallback only when the backend fails.
        if let remoteIncomplete, !remoteIncomplete.detectedItems.isEmpty {
            result = remoteIncomplete
            result.warnings.insert(
                "The image was interpreted, but nutrition still needs confirmation before it can be saved.",
                at: 0
            )
        } else if localCompleteness.isComplete {
            if remoteFailed {
                result.warnings.insert(
                    "Live recognition is unavailable, so this private on-device estimate needs your review.",
                    at: 0
                )
            }
            FoodLoggingDiagnostics.record("photo.classification", fields: [
                "route": candidateNames.isEmpty ? "member-hint" : "on-device-fallback",
                "canonicalIDs": candidates.map(\.canonicalFoodId).joined(separator: ","),
                "candidateCount": String(candidates.count),
                "remoteAttempted": String(remote != nil),
                "remoteFailed": String(remoteFailed),
                "complete": "true"
            ])
            return result
        } else if remoteFailed {
            let warning = result.detectedItems.isEmpty
                ? "Secure AI recognition is unavailable. Add the food name below without losing your photo."
                : "Secure AI recognition is unavailable, so this private on-device estimate needs your review."
            result.warnings.insert(warning, at: 0)
        } else if candidates.isEmpty && trimmedDescription.isEmpty {
            result.warnings.insert(
                remote == nil
                    ? "Secure AI recognition is not configured. Add the food name below and nutrition will recalculate."
                    : "Automatic recognition could not identify this plate confidently. Add the food name below and nutrition will recalculate.",
                at: 0
            )
        }
        FoodLoggingDiagnostics.record("photo.classification", fields: [
            "route": result.detectedItems.isEmpty ? "unresolved" : "incomplete-local",
            "canonicalIDs": candidates.map(\.canonicalFoodId).joined(separator: ","),
            "candidateCount": String(candidates.count),
            "remoteAttempted": String(remote != nil),
            "remoteFailed": String(remoteFailed),
            "missing": completeness.evaluate(result).missingRequirements.joined(separator: ",")
        ])
        return result
    }

    private func confidenceLevel(for score: Double) -> ConfidenceLevel {
        if score >= 0.9 { return .high }
        if score >= 0.8 { return .medium }
        return .low
    }
}

// MARK: - Catalog and offline calculation

/// The catalog is a data resource, rather than a UI switch statement. It can be
/// replaced by an account-scoped, server-delivered catalog without changing views.
struct IndianFoodCatalogService: FoodNormalisationService, Sendable {
    let version: String
    let source: String
    let foods: [IndianFoodDefinition]

    init(bundle: Bundle = .main) {
        let data = bundle.url(forResource: "IndianFoodCatalog", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) } ?? Data()
        self.init(data: data)
    }

    init(data: Data) {
        guard let document = try? JSONDecoder().decode(CatalogDocument.self, from: data) else {
            self.version = "unavailable"
            self.source = "No local food catalog"
            self.foods = []
            return
        }

        self.version = document.version
        self.source = document.source
        self.foods = document.groups.flatMap { group in
            group.foods.map { record in
                IndianFoodDefinition(
                    canonicalId: record.id,
                    canonicalName: record.name,
                    regionalNames: record.regionalNames ?? [],
                    englishName: record.englishName ?? record.name,
                    transliterations: record.transliterations ?? [],
                    aliases: Array(Set(([record.name, record.id] + record.aliases))).sorted(),
                    category: group.category,
                    dietaryClassification: record.dietaryClassification ?? group.dietaryClassification,
                    commonIngredients: record.ingredients ?? [],
                    possibleAllergens: record.allergens ?? group.allergens,
                    commonPreparationMethods: record.methods ?? group.methods,
                    nutritionPer100Grams: record.nutrition,
                    standardServing: record.serving,
                    glycaemicIndex: record.glycaemicIndex,
                    glycaemicIndexSource: record.glycaemicIndexSource,
                    dataSource: record.dataSource ?? document.source,
                    dataVersion: record.dataVersion ?? document.version,
                    confidence: record.confidence ?? (record.nutrition == nil ? .unknown : .low),
                    revision: record.revision
                )
            }
        }
    }

    func normalise(_ query: String) -> IndianFoodDefinition? {
        let key = normalized(query)
        return foods.first { food in
            food.aliases.contains { normalized($0) == key }
                || normalized(food.canonicalName) == key
                || normalized(food.englishName) == key
        }
    }

    func food(canonicalID: String) -> IndianFoodDefinition? {
        foods.first { $0.canonicalId == canonicalID }
    }

    func matches(in description: String) -> [IndianFoodDefinition] {
        var remaining = " " + normalized(description) + " "
        var matches: [IndianFoodDefinition] = []

        let candidates = foods
            .flatMap { food in food.aliases.map { (food, normalized($0)) } }
            .filter { !$0.1.isEmpty }
            .sorted { $0.1.count > $1.1.count }

        for (food, alias) in candidates {
            let needle = " " + alias + " "
            guard remaining.contains(needle), !matches.contains(where: { $0.id == food.id }) else { continue }
            matches.append(food)
            remaining = remaining.replacingOccurrences(of: needle, with: " ")
        }

        return matches
    }

    private func normalized(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

struct StandardPortionEstimationService: PortionEstimationService, Sendable {
    func estimatedWeight(quantity: Double, unit: ServingUnit, food: IndianFoodDefinition) -> Double? {
        if unit == .grams { return quantity }
        if let serving = food.standardServing, serving.unit == unit, let grams = serving.grams {
            return grams * quantity / serving.quantity
        }

        let gramsPerUnit: Double? = switch unit {
        case .millilitres: 1
        case .teaspoon: 5
        case .tablespoon: 15
        case .katori: 150
        case .smallBowl: 120
        case .mediumBowl: 200
        case .largeBowl: 300
        case .cup: 240
        case .ladle: 60
        case .piece: 60
        case .roti: 35
        case .naan: 90
        case .paratha: 90
        case .poori: 35
        case .bhatura: 100
        case .dosa: 120
        case .idli: 40
        case .vada: 55
        case .slice: 30
        case .glass: 250
        case .plate: 300
        case .serving: food.standardServing?.grams
        case .wholeEgg: 50
        case .scoop: food.standardServing?.grams ?? 30
        case .grams: nil
        }
        return gramsPerUnit.map { $0 * quantity }
    }
}

struct CatalogNutritionLookupService: NutritionLookupService, Sendable {
    func nutrition(for food: IndianFoodDefinition, estimatedWeightGrams: Double?) -> NutritionLookup {
        guard let per100 = food.nutritionPer100Grams, let estimatedWeightGrams else {
            return NutritionLookup(values: .unavailable, provenance: .unavailable)
        }

        return NutritionLookup(
            values: per100.scaled(by: estimatedWeightGrams / 100),
            provenance: NutritionProvenance(
                kind: .curatedRecipeEstimate,
                dataSource: food.dataSource ?? "Bundled recipe estimate — recipe may vary",
                dataVersion: food.dataVersion,
                confidence: food.confidence
            )
        )
    }
}

struct CatalogGlycaemicDataService: GlycaemicDataService, Sendable {
    func information(for food: IndianFoodDefinition, availableCarbohydrateGrams: Double?) -> GlycaemicInformation {
        GlycaemicInformation.calculate(
            index: food.glycaemicIndex,
            source: food.glycaemicIndexSource,
            availableCarbohydrate: availableCarbohydrateGrams
        )
    }
}

// MARK: - Draft construction and tool orchestration

/// Offline analysis works only from a member's description. It is never passed
/// off as computer vision, and it does not send a photo anywhere.
struct LocalMealAnalysisEngine: AgentToolService, Sendable {
    let catalog: IndianFoodCatalogService
    let portionService: StandardPortionEstimationService
    let nutritionService: CatalogNutritionLookupService
    let glycaemicService: CatalogGlycaemicDataService
    let validationService: DefaultNutritionValidationService
    let fallbackService: CuratedNutritionFallbackService

    init(
        catalog: IndianFoodCatalogService = IndianFoodCatalogService(),
        portionService: StandardPortionEstimationService = StandardPortionEstimationService(),
        nutritionService: CatalogNutritionLookupService = CatalogNutritionLookupService(),
        glycaemicService: CatalogGlycaemicDataService = CatalogGlycaemicDataService(),
        validationService: DefaultNutritionValidationService = DefaultNutritionValidationService(),
        fallbackService: CuratedNutritionFallbackService? = nil
    ) {
        self.catalog = catalog
        self.portionService = portionService
        self.nutritionService = nutritionService
        self.glycaemicService = glycaemicService
        self.validationService = validationService
        self.fallbackService = fallbackService ?? CuratedNutritionFallbackService(catalog: catalog)
    }

    func draftFromDescription(_ description: String, imageReference: MealImageReference, imageType: MealImageType) async -> MealAnalysisResult {
        makeAnalysis(description: description, imageReference: imageReference, imageType: imageType)
    }

    func makeAnalysis(description: String, imageReference: MealImageReference = .transient(), imageType: MealImageType = .noImage) -> MealAnalysisResult {
        let trace = FoodUnderstandingPipeline(catalog: catalog).parse(description)
        let items = trace.components.map(makeItem)
        let questions = clarificationQuestions(for: items, imageType: imageType)
        let totals = NutritionValues.total(of: items.map(\.nutrition))
        let rawValidation = validationService.validate(
            rawValues: totals,
            canonicalFoodID: nil,
            quantity: nil,
            servingUnit: nil,
            estimatedWeightGrams: nil
        )
        let allValuesSupported = !items.isEmpty && items.allSatisfy { !$0.nutrition.isEmpty }
        let validation = allValuesSupported ? rawValidation : NutritionValidationReport(
            status: .requiresClarification,
            rawValues: totals,
            safeValues: nil,
            issues: rawValidation.issues + [.init(
                code: .unavailableNutrition,
                severity: .blocking,
                message: "Choose the requested food variation before nutrition can be shown or logged."
            )]
        )
        let provenance = allValuesSupported
            ? NutritionProvenance(kind: .curatedRecipeEstimate, dataSource: catalog.source, dataVersion: catalog.version, confidence: .low)
            : .unavailable
        let analysisID = UUID()
        let visualRequest = MealVisualRequestBuilder().make(
            mealID: analysisID,
            items: items,
            clarificationQuestions: questions
        )

        FoodLoggingDiagnostics.record("analysis.parsed", fields: [
            "components": items.map(\.canonicalFoodId).joined(separator: ","),
            "inputFingerprint": FoodLoggingDiagnostics.fingerprint(description),
            "nutritionStatus": validation.status.rawValue,
            "entityCount": String(trace.entities.count)
        ])

        return MealAnalysisResult(
            analysisId: analysisID,
            imageReference: imageReference,
            imageType: imageType,
            detectedItems: items,
            mealTotals: validation.safeValues ?? .unavailable,
            overallConfidence: overallConfidence(for: items),
            assumptions: assumptions(for: items, imageType: imageType),
            clarificationQuestions: questions,
            warnings: warnings(for: items, imageType: imageType, validation: validation),
            createdAt: .now,
            recognitionModelVersion: nil,
            nutritionDatabaseVersion: catalog.version,
            glycaemicDatabaseVersion: nil,
            nutritionProvenance: provenance,
            nutritionValidation: validation,
            visualRequest: visualRequest
        )
    }

    private func makeItem(_ component: ParsedFoodComponent) -> DetectedFoodItem {
        let food = component.food
        let quantity = component.quantity
        let unit = component.servingUnit
        let weight = portionService.estimatedWeight(quantity: quantity, unit: unit, food: food)
        let catalogLookup = nutritionService.nutrition(for: food, estimatedWeightGrams: weight)
        let fallback = catalogLookup.values.isEmpty
            ? fallbackService.resolve(
                item: ParsedFoodItem(
                    originalText: component.matchedAlias,
                    canonicalSearchName: food.englishName,
                    regionalName: food.regionalNames.first,
                    quantity: quantity,
                    unit: unit.rawValue,
                    estimatedGrams: weight,
                    preparationMethod: component.preparationMethod,
                    confidence: component.confidenceScore
                ),
                canonical: CanonicalFoodMatch(
                    food: food,
                    matchedAlias: component.matchedAlias,
                    confidence: component.confidenceScore,
                    source: "local-canonical-catalog"
                )
            )
            : nil
        let lookup = fallback?.lookup ?? catalogLookup
        let resolvedValues = nutritionIncludingShakeBase(
            lookup.values,
            supplement: component.supplementProfile
        )
        let validation = validationService.validate(
            rawValues: resolvedValues,
            canonicalFoodID: food.canonicalId,
            quantity: quantity,
            servingUnit: unit,
            estimatedWeightGrams: weight
        )
        let safeNutrition = validation.safeValues ?? .unavailable
        let glycaemic = glycaemicService.information(for: food, availableCarbohydrateGrams: safeNutrition.availableCarbohydrateGrams)

        FoodLoggingDiagnostics.record("nutrition.lookup", fields: [
            "canonicalFoodID": food.canonicalId,
            "estimatedWeightGrams": weight.map { String(format: "%.1f", $0) } ?? "unavailable",
            "provenance": lookup.provenance.kind.rawValue,
            "providerResponse": resolvedValues.isEmpty ? "unavailable" : "usable",
            "validation": validation.status.rawValue
        ])

        return DetectedFoodItem(
            id: UUID(),
            canonicalFoodId: food.canonicalId,
            displayName: food.canonicalName,
            regionalName: food.regionalNames.first,
            category: food.category,
            confidence: confidence(for: component),
            alternatives: alternatives(for: food),
            quantity: quantity,
            servingUnit: unit,
            estimatedWeightGrams: weight,
            visibleIngredients: [],
            inferredIngredients: food.commonIngredients,
            possibleIngredients: [],
            preparationMethod: component.preparationMethod,
            nutrition: safeNutrition,
            glycaemicInformation: glycaemic,
            assumptions: assumptions(for: component) + (fallback?.assumptions ?? []),
            warnings: itemWarnings(for: resolvedValues, validation: validation),
            boundingRegion: nil,
            nutritionProvenance: lookup.provenance,
            rawNutrition: resolvedValues,
            nutritionValidation: validation,
            matchedAlias: component.matchedAlias,
            confidenceScore: component.confidenceScore,
            modifiers: component.modifiers,
            supplementProfile: component.supplementProfile
        )
    }

    private func nutritionIncludingShakeBase(
        _ powder: NutritionValues,
        supplement: SupplementProductProfile?
    ) -> NutritionValues {
        guard supplement?.base == .milk,
              let milk = catalog.normalise("milk") else { return powder }
        let milkWeight = milk.standardServing?.grams ?? 240
        let milkValues = nutritionService.nutrition(for: milk, estimatedWeightGrams: milkWeight).values
        return NutritionValues.total(of: [powder, milkValues])
    }

    private func confidence(for component: ParsedFoodComponent) -> ConfidenceLevel {
        if component.food.confidence == .unknown { return .low }
        if component.confidenceScore >= 0.9 { return .high }
        if component.confidenceScore >= 0.8 { return .medium }
        return .low
    }

    private func assumptions(for component: ParsedFoodComponent) -> [String] {
        var values = ["Serving is an editable starting estimate."]
        if component.food.canonicalId == "mixed-sprouts" {
            values.append("Generic mixed sprouts were used; choose a specific variety if it matters to you.")
        }
        if let supplement = component.supplementProfile {
            values.append("Using \(supplement.productName) at \(supplement.servingSizeGrams.formatted(.number.precision(.fractionLength(0...1)))) g. \(supplement.base == .unspecified ? "Base is still needed." : "Base: \(supplement.base.displayName).")")
        }
        return values
    }

    private func itemWarnings(for values: NutritionValues, validation: NutritionValidationReport) -> [String] {
        if !validation.isApproved { return validation.issues.map(\.message) }
        return values.isEmpty
            ? ["Nutrition is not available from the offline catalog for this dish."]
            : ["Estimated from a recipe profile. Oil, ghee, cream, and sugar may change this substantially."]
    }

    private func alternatives(for food: IndianFoodDefinition) -> [AlternativeFoodMatch] {
        catalog.foods
            .filter { $0.category == food.category && $0.id != food.id }
            .prefix(2)
            .map { AlternativeFoodMatch(canonicalFoodId: $0.canonicalId, displayName: $0.canonicalName, confidence: .low) }
    }

    private func assumptions(for items: [DetectedFoodItem], imageType: MealImageType) -> [String] {
        var values = imageType == .originalPhoto
            ? ["The local fallback used your description; the image was not sent for recognition."]
            : ["Items were matched from your words, not a photo."]
        if items.contains(where: { $0.category == .rice || $0.category == .bread }) {
            values.append("Carbohydrate totals depend heavily on the final serving size.")
        }
        return values
    }

    private func warnings(for items: [DetectedFoodItem], imageType: MealImageType, validation: NutritionValidationReport) -> [String] {
        guard !items.isEmpty else {
            return ["No supported dish was found. Tell me the main dish and I’ll create an editable estimate."]
        }
        var values = ["Estimated — recipe may vary. This is not medical advice."]
        if items.contains(where: { $0.category == .dessertOrDrink }) {
            values.append("Sweeteners may substantially change this estimate.")
        }
        if items.contains(where: { $0.nutrition.isEmpty }) {
            values.append("Nutrition is incomplete: totals are withheld until every component has a supported variation.")
        }
        if !validation.isApproved {
            values.append("Nutrition needs confirmation before it can affect your daily totals.")
        }
        if imageType == .originalPhoto {
            values.append("A photo cannot reliably reveal oil, ghee, cream, sugar, recipe, or exact weight.")
        }
        return values
    }

    private func clarificationQuestions(for items: [DetectedFoodItem], imageType: MealImageType) -> [ClarificationQuestion] {
        var questions: [ClarificationQuestion] = []
        if let whey = items.first(where: { $0.category == .supplement && $0.supplementProfile?.base == .unspecified }) {
            questions.append(ClarificationQuestion(
                id: UUID(), relatedFoodItemId: whey.id,
                question: "How many scoops, and was it mixed with water or milk?",
                answerType: .singleChoice,
                options: ["1 scoop + water", "1 scoop + milk", "2 scoops + water", "2 scoops + milk"],
                impactLevel: .high,
                answer: nil
            ))
        }
        if let sprouts = items.first(where: { $0.canonicalFoodId == "mixed-sprouts" }) {
            questions.append(ClarificationQuestion(
                id: UUID(), relatedFoodItemId: sprouts.id,
                question: "Was the sprouts serving roughly a small, medium, or large bowl?",
                answerType: .singleChoice,
                options: ["Small", "Medium", "Large"],
                impactLevel: .low,
                answer: nil
            ))
        }
        if let coffee = items.first(where: { $0.canonicalFoodId == "coffee" }) {
            questions.append(ClarificationQuestion(
                id: UUID(), relatedFoodItemId: coffee.id,
                question: "Was it plain black coffee, or did it contain milk, cream or sugar?",
                answerType: .singleChoice, options: ["Black", "Milk", "Milk + sugar"], impactLevel: .high, answer: nil
            ))
        }
        if let chai = items.first(where: { $0.canonicalFoodId == "chai" }) {
            questions.append(ClarificationQuestion(
                id: UUID(), relatedFoodItemId: chai.id,
                question: "Was the chai sweetened, and approximately how much milk was used?",
                answerType: .singleChoice, options: ["No milk or sugar", "Milk, no sugar", "Milk + sugar"], impactLevel: .high, answer: nil
            ))
        }
        if let tea = items.first(where: { $0.canonicalFoodId == "tea" }) {
            questions.append(ClarificationQuestion(
                id: UUID(), relatedFoodItemId: tea.id,
                question: "Was the tea plain, or did it include milk or sugar?",
                answerType: .singleChoice, options: ["Plain", "Milk, no sugar", "Milk + sugar"], impactLevel: .high, answer: nil
            ))
        }
        if let paratha = items.first(where: { $0.canonicalFoodId == "paratha" }) {
            questions.append(ClarificationQuestion(
                id: UUID(), relatedFoodItemId: paratha.id,
                question: "Was the paratha plain, stuffed or buttered?",
                answerType: .singleChoice, options: ["Plain", "Aloo / stuffed", "Buttered"], impactLevel: .high, answer: nil
            ))
        }
        if let bread = items.first(where: { $0.category == .bread && $0.canonicalFoodId != "paratha" }) {
            questions.append(ClarificationQuestion(
                id: UUID(), relatedFoodItemId: bread.id,
                question: "How many \(bread.displayName.lowercased()) pieces did you have?",
                answerType: .quantity, options: ["1", "2", "3+"], impactLevel: .high, answer: nil
            ))
        }
        if let rice = items.first(where: { $0.category == .rice }) {
            questions.append(ClarificationQuestion(
                id: UUID(), relatedFoodItemId: rice.id,
                question: "Was the rice a small, medium, or large serving?",
                answerType: .singleChoice, options: ["Small", "Medium", "Large"], impactLevel: .high, answer: nil
            ))
        }
        if let richDish = items.first(where: { [.vegetarianCurry, .nonVegetarian, .lentilOrLegume].contains($0.category) }) {
            questions.append(ClarificationQuestion(
                id: UUID(), relatedFoodItemId: richDish.id,
                question: "Was it made with oil, ghee, butter, or cream?",
                answerType: .singleChoice, options: ["No / very little", "Some", "A generous amount"], impactLevel: .high, answer: nil
            ))
        }
        if let drink = items.first(where: { $0.category == .dessertOrDrink && !["coffee", "chai", "tea", "black-coffee", "plain-tea", "green-tea"].contains($0.canonicalFoodId) }) {
            questions.append(ClarificationQuestion(
                id: UUID(), relatedFoodItemId: drink.id,
                question: "Was the drink or dessert sweetened?",
                answerType: .yesNo, options: ["No", "Yes", "Not sure"], impactLevel: .high, answer: nil
            ))
        }
        if items.isEmpty && imageType == .originalPhoto {
            questions.append(ClarificationQuestion(
                id: UUID(), relatedFoodItemId: nil,
                question: "What is the main dish in this photo?",
                answerType: .freeText, options: [], impactLevel: .high, answer: nil
            ))
        }
        return Array(questions.prefix(2))
    }

    private func overallConfidence(for items: [DetectedFoodItem]) -> ConfidenceLevel {
        let rank: [ConfidenceLevel: Int] = [.high: 4, .medium: 3, .low: 2, .unknown: 1]
        return items.min { rank[$0.confidence, default: 0] < rank[$1.confidence, default: 0] }?.confidence ?? .low
    }

    private func quantityHint(for food: IndianFoodDefinition, in description: String) -> Double? {
        let tokens = tokenize(description)
        let numberWords: [String: Double] = [
            "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4,
            "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10
        ]

        for alias in food.aliases.sorted(by: { $0.count > $1.count }) {
            let aliasTokens = tokenize(alias)
            guard !aliasTokens.isEmpty else { continue }
            for start in tokens.indices where Array(tokens.dropFirst(start).prefix(aliasTokens.count)) == aliasTokens {
                guard start > 0 else { return nil }
                let preceding = tokens[start - 1]
                if let decimal = Double(preceding), (0.1...20).contains(decimal) { return decimal }
                if let word = numberWords[preceding] { return word }
            }
        }
        return nil
    }

    private func tokenize(_ value: String) -> [String] {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}

actor InMemoryMealAnalysisRepository: MealAnalysisRepository {
    private var drafts: [UUID: MealAnalysisDraft] = [:]

    func saveDraft(_ draft: MealAnalysisDraft) async { drafts[draft.id] = draft }
    func draft(id: UUID) async -> MealAnalysisDraft? { drafts[id] }
    func removeDraft(id: UUID) async { drafts[id] = nil }
}

struct DiaryMealLoggingService: MealLoggingService {
    let userFoodMemory: (any UserFoodMemoryRepository)?

    init(userFoodMemory: (any UserFoodMemoryRepository)? = nil) {
        self.userFoodMemory = userFoodMemory
    }

    @MainActor
    func confirm(_ draft: MealAnalysisDraft, replacing itemID: ThreadItem.ID, in store: DiaryStore, dayID: Day.ID) -> Meal {
        let result = draft.result
        let title = result.detectedItems
            .filter { $0.category != .hydration }
            .map(\.displayName)
            .joined(separator: " + ")
            .ifEmpty("Meal draft")
        // The draft analysis ID is the stable meal identity for any visual work
        // started before confirmation. This makes a late provider response
        // impossible to attach to another saved meal.
        let mealID = result.visualRequest?.mealID ?? result.analysisId
        let artwork = artwork(for: result)
        let visualIdentity = MealVisualIdentityFactory().make(mealID: mealID, result: result, artwork: artwork)
        let meal = Meal(
            id: mealID,
            title: title,
            subtitle: "Confirmed estimate · \(result.nutritionProvenance.dataSource)",
            mealType: mealType(for: result),
            time: .now,
            energy: Int(result.mealTotals.caloriesKcal?.rounded() ?? 0),
            carbs: Int(result.mealTotals.carbohydrateGrams?.rounded() ?? 0),
            protein: Int(result.mealTotals.proteinGrams?.rounded() ?? 0),
            fat: Int(result.mealTotals.fatGrams?.rounded() ?? 0),
            artwork: artwork,
            confidence: .estimated,
            analysis: result,
            visualIdentity: visualIdentity
        )
        store.replace(itemID: itemID, with: .meal(meal), in: dayID)
        if let request = result.visualRequest {
            Task {
                await MealVisualRuntime.ledger.begin(mealID: mealID, cacheKey: request.cacheKey, requestID: request.requestID)
            }
        }
        if let userFoodMemory {
            for item in result.detectedItems {
                let memory = UserFoodMemory(
                    id: UUID(),
                    alias: item.matchedAlias ?? item.displayName,
                    canonicalFoodID: item.canonicalFoodId,
                    servingGrams: item.estimatedWeightGrams,
                    servingUnit: item.servingUnit.rawValue,
                    preparation: item.preparationMethod,
                    productID: item.supplementProfile?.barcode,
                    lastConfirmedAt: .now
                )
                Task { await userFoodMemory.save(memory) }
            }
        }
        return meal
    }

    @MainActor
    func update(_ meal: Meal, in store: DiaryStore, dayID: Day.ID) {
        store.update(meal, in: dayID)
        if let request = meal.analysis?.visualRequest {
            Task {
                await MealVisualRuntime.ledger.begin(mealID: meal.id, cacheKey: request.cacheKey, requestID: request.requestID)
            }
        }
    }

    @MainActor
    func delete(mealID: Meal.ID, in store: DiaryStore, dayID: Day.ID) {
        store.removeMeal(id: mealID, from: dayID)
        Task { await MealVisualRuntime.ledger.delete(mealID: mealID) }
    }

    private func mealType(for result: MealAnalysisResult) -> String {
        result.detectedItems.contains(where: { $0.category == .breakfastOrSnack }) ? "Meal" : "Meal"
    }

    private func artwork(for result: MealAnalysisResult) -> Meal.Artwork {
        // The bundled cutouts depict specific sample dishes, not generic rice,
        // bread, drinks, or curries. Until a generated or verified editorial
        // image is attached, a component-labelled placeholder is more honest
        // than reusing a convincing but unrelated photograph.
        .neutral
    }
}

private extension String {
    func ifEmpty(_ replacement: String) -> String { isEmpty ? replacement : self }
}

private struct CatalogDocument: Decodable {
    let version: String
    let source: String
    let groups: [CatalogGroup]
}

private struct CatalogGroup: Decodable {
    let category: FoodCategory
    let dietaryClassification: DietaryClassification
    let allergens: [String]
    let methods: [String]
    let foods: [CatalogFoodRecord]
}

private struct CatalogFoodRecord: Decodable {
    let id: String
    let name: String
    let aliases: [String]
    let regionalNames: [String]?
    let englishName: String?
    let transliterations: [String]?
    let dietaryClassification: DietaryClassification?
    let ingredients: [String]?
    let allergens: [String]?
    let methods: [String]?
    let nutrition: NutritionValues?
    let serving: StandardServing?
    let glycaemicIndex: Double?
    let glycaemicIndexSource: String?
    let dataSource: String?
    let dataVersion: String?
    let confidence: ConfidenceLevel?
    let revision: String?
}
