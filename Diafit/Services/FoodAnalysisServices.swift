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
    let integrity = PhotoParseIntegrityService()
    let inventoryVerification: PhotoInventoryVerificationService
    let spatialReview = SpatialPlateReviewImageService()

    init(
        understanding: any FoodUnderstandingService,
        coordinator: HybridMealAnalysisCoordinator,
        catalog: IndianFoodCatalogService = IndianFoodCatalogService()
    ) {
        self.understanding = understanding
        self.coordinator = coordinator
        self.inventoryVerification = PhotoInventoryVerificationService(catalog: catalog)
    }

    func analyse(_ image: PreparedFoodImage, dishHint: String?) async throws -> MealAnalysisResult {
        let trimmedHint = dishHint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // A typed hint is evidence, not an inventory. Older builds passed the
        // hint as the entire prompt, which encouraged the provider to return
        // only the named dish and silently omit the rest of the plate.
        let instruction = trimmedHint.isEmpty
            ? "Inspect the entire meal photo and identify every distinct physical food serving exactly once. Preserve regional Indian names, include breads, rice, dal, sabji, curries and sides when visible, and never list alternative guesses as separate foods."
            : "The member described this meal as \(trimmedHint). Use that as a hint, but inspect the entire photo and return every distinct visible serving exactly once."
        let primaryParse = try await understanding.parse(text: instruction, image: image)
        var selectedParse = primaryParse
        if inventoryVerification.needsIndependentCheck(primaryParse),
           let verifiedParse = try? await understanding.parse(
               text: inventoryVerification.prompt(after: primaryParse),
               // Keep the original composition for the first independent
               // pass. A collage can make a bowl look like a different dish
               // and was the source of the recurring stale “vegetable soup”
               // result in otherwise unrelated photos.
               image: image
           ) {
            selectedParse = inventoryVerification.preferred(primary: primaryParse, verified: verifiedParse)
        } else {
            selectedParse = primaryParse
        }

        // A single broad label is not a safe inventory for a plate photo. If
        // both full-frame passes still collapse the image to a generic dish or
        // a small garnish/ingredient, spend one additional pass on spatial
        // crops. This is deliberately quality-gated, so ordinary single-food
        // photos do not incur an unnecessary third request.
        if inventoryVerification.needsExpandedInventory(selectedParse),
           let montage = spatialReview.make(from: image),
           let spatialParse = try? await understanding.parse(
               text: inventoryVerification.spatialPrompt(after: selectedParse),
               image: montage
           ) {
            selectedParse = inventoryVerification.preferred(primary: selectedParse, verified: spatialParse)
        }

        // A provider can repeat the same salient garnish across the full-frame
        // and montage passes. One short, fresh recovery pass prevents that
        // repeated answer from becoming the meal inventory. It is only used
        // when the result is still sparse after the spatial review, so normal
        // single-food photographs keep the fast path and do not pay for an
        // extra request.
        if inventoryVerification.needsRecoveryPass(selectedParse),
           let recoveryParse = try? await understanding.parse(
               text: inventoryVerification.recoveryPrompt(after: selectedParse),
               image: image
           ) {
            selectedParse = inventoryVerification.preferred(primary: selectedParse, verified: recoveryParse)
        }
        let parse = integrity.audit(selectedParse)
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

/// A whole plate can be nutritionally complete while still being visually
/// incomplete. Common one-to-four-component interpretations receive one
/// independent inventory check. The second pass must return the complete plate
/// and is reconciled with the first rather than blindly replacing it.
struct PhotoInventoryVerificationService: Sendable {
    let catalog: IndianFoodCatalogService

    init(catalog: IndianFoodCatalogService = IndianFoodCatalogService()) {
        self.catalog = catalog
    }

    func needsIndependentCheck(_ parse: MealParseResult) -> Bool {
        // A six-component plate is still small enough to audit, and is where
        // a single broad label is most likely to hide a side or flatbread.
        (1...6).contains(parse.detectedItems.count)
    }

    func needsExpandedInventory(_ parse: MealParseResult) -> Bool {
        guard !parse.detectedItems.isEmpty else { return true }

        // Do not gate this on a one-item result. The recurring failure was a
        // photo reduced to two plausible labels (for example rice + soup)
        // while the roti, dal, or dry sabzi on the same plate disappeared.
        // Any generic label, garnish-sized ingredient, or low-confidence
        // component warrants the spatial pass even when other components look
        // complete.
        return parse.detectedItems.contains { item in
            let key = identityKey(item)
            let smallIngredient = ["peanut", "almond", "walnut", "mixed nuts", "nut"].contains {
                key == $0 || key.hasPrefix($0 + " ")
            }
            return isReplaceableGeneric(item) || smallIngredient || item.confidence < 0.80
        }
    }

    func needsRecoveryPass(_ parse: MealParseResult) -> Bool {
        guard parse.detectedItems.count == 1,
              let item = parse.detectedItems.first else { return false }
        let key = identityKey(item).replacingOccurrences(of: "-", with: " ")
        let salientIngredient = ["peanut", "almond", "walnut", "mixed nuts", "nut", "seed"]
            .contains { key == $0 || key.hasPrefix($0 + " ") }
        let generic = isReplaceableGeneric(item)
        return salientIngredient || generic || item.confidence < 0.80
    }

    func prompt(after parse: MealParseResult) -> String {
        let firstPass = parse.detectedItems
            .map { $0.regionalName ?? $0.originalText }
            .joined(separator: ", ")
        return """
        Re-inspect the entire food photograph independently. The first inventory is an untrusted hypothesis: \(firstPass). \
        Do not anchor on it or repeat a generic label just because it was suggested. \
        The supplied image may be a spatial review montage containing overlapping views of the same original \
        photograph. Do not count a food twice merely because it appears in more than one panel. Return a complete \
        corrected inventory, not only additions. Scan the main plate and every separate bowl \
        from top to bottom and left to right. Check separately for grains, breads or stacked flatbreads, dal or \
        other legumes, dry vegetables or sabzi, wet curries, protein foods, sides, and drinks. Distinguish a \
        separate lentil dish from generic vegetable soup when the visual evidence supports it. Preserve visible \
        counts and regional names. Include each physical serving exactly once and do not invent food hidden from view.
        """
    }

    func spatialPrompt(after parse: MealParseResult) -> String {
        let firstPass = parse.detectedItems
            .map { $0.regionalName ?? $0.originalText }
            .joined(separator: ", ")
        return """
        This is a four-panel spatial review of the same meal photograph. The current pass only found the following \
        untrusted hypothesis: \(firstPass). Do not anchor on it or repeat a generic label without visual evidence. \
        Reconstruct one complete inventory of the original plate, not four separate meals. Inspect every panel and \
        merge overlapping views. Look for separate bowls, piles, stacked flatbreads, eggs, sprouts, nuts, rice, \
        lentils and vegetable preparations. A generic label such as soup, curry, food or peanut is not sufficient \
        when a more specific visible serving is supported. Return each physical serving once, preserve visible \
        counts, and use a concise clarification only for genuinely hidden or ambiguous details.
        """
    }

    func recoveryPrompt(after parse: MealParseResult) -> String {
        let firstPass = parse.detectedItems
            .map { $0.regionalName ?? $0.originalText }
            .joined(separator: ", ")
        return """
        Perform a fresh component-level inventory of the entire original meal photo. Earlier passes repeatedly
        returned only \(firstPass), which is an incomplete hypothesis, not a conclusion. A single nut, seed,
        garnish, or generic label must never stand in for a plate that contains other visible foods. Scan the full
        frame and all separate piles, bowls, and containers before answering. Return every visually separable food
        exactly once, including eggs, sprouts, nuts, breads, rice, dal, sabzi, curries, sides, and drinks when they
        are present. Count visible units conservatively, preserve regional names, and do not invent anything hidden.
        If the photograph truly contains only one food, explain why in mealDescription; otherwise do not return a
        one-item garnish result.
        """
    }

    func preferred(primary: MealParseResult, verified: MealParseResult) -> MealParseResult {
        guard !verified.detectedItems.isEmpty else { return primary }

        let primaryKeys = Set(primary.detectedItems.map(identityKey))
        let verifiedKeys = Set(verified.detectedItems.map(identityKey))
        let hasSharedIdentity = !primaryKeys.intersection(verifiedKeys).isEmpty

        // Never throw away a physical serving merely because the second pass
        // saw a different region. Merge both inventories, deduplicating by a
        // canonical catalog identity and preferring the better-evidenced item.
        // The previous count-based replacement was why roti or dal vanished
        // when another pass returned only kadhi/soup.
        var merged = deduplicatedItems(primary.detectedItems + verified.detectedItems)

        // A generic label from one pass is often the wrong name for a serving
        // that the other pass identified specifically. Drop only that generic
        // candidate; never drop a specific item from either inventory.
        let primaryGenericKeys = Set(primary.detectedItems.filter(isReplaceableGeneric).map(identityKey))
        let verifiedGenericKeys = Set(verified.detectedItems.filter(isReplaceableGeneric).map(identityKey))
        if hasSharedIdentity, verified.detectedItems.count >= primary.detectedItems.count {
            merged.removeAll { item in
                primaryGenericKeys.contains(identityKey(item))
                    && !verifiedKeys.contains(identityKey(item))
            }
        }
        if !hasSharedIdentity {
            merged.removeAll { item in
                let key = identityKey(item)
                let fromVerifiedGeneric = verifiedGenericKeys.contains(key)
                let fromPrimaryGeneric = primaryGenericKeys.contains(key)
                guard fromVerifiedGeneric || fromPrimaryGeneric else { return false }
                let other = fromVerifiedGeneric ? primary.detectedItems : verified.detectedItems
                // A generic curry/soup label should not replace any specific
                // serving found by the other pass. This is intentionally not
                // limited to a shared category: the recurring failures were a
                // soup label replacing a kadhi bowl, roti stack, eggs or nuts
                // that the spatial pass could see. Generic-only single-food
                // photos remain untouched because there is no specific item
                // to justify removal.
                return other.contains { hasIdentity($0) && !isReplaceableGeneric($0) }
            }
        }

        // The fallback above intentionally remains conservative. If a future
        // provider returns an empty merge after filtering, preserve the more
        // complete response rather than showing a blank review.
        if merged.isEmpty { merged = verified.detectedItems }
        var selected = verified
        selected.detectedItems = merged
        selected.mealDescription = [primary.mealDescription, verified.mealDescription]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        selected.confidence = min(primary.confidence, verified.confidence)

        selected.unresolvedItems = SemanticQuestionDeduplicator.uniqueStrings(
            primary.unresolvedItems + verified.unresolvedItems
        )
        selected.clarificationQuestions = SemanticQuestionDeduplicator.uniqueStrings(
            primary.clarificationQuestions + verified.clarificationQuestions
        )
        return selected
    }

    private func identityKey(_ item: ParsedFoodItem) -> String {
        let candidates = [item.canonicalSearchName, item.regionalName, item.originalText]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if let canonical = candidates.compactMap({ catalog.normalise($0)?.canonicalId }).first {
            return canonical
        }
        let source = candidates.first ?? ""
        return SemanticQuestionDeduplicator.normalizedKey(source)
    }

    private func deduplicatedItems(_ items: [ParsedFoodItem]) -> [ParsedFoodItem] {
        var indexByKey: [String: Int] = [:]
        var result: [ParsedFoodItem] = []
        for item in items {
            let key = identityKey(item)
            guard !key.isEmpty else { continue }
            if let index = indexByKey[key] {
                if evidenceScore(item) > evidenceScore(result[index]) {
                    result[index] = item
                }
            } else {
                indexByKey[key] = result.count
                result.append(item)
            }
        }
        return result
    }

    private func isReplaceableGeneric(_ item: ParsedFoodItem) -> Bool {
        let key = identityKey(item).replacingOccurrences(of: "-", with: " ")
        let genericWords = ["food", "meal", "dish", "soup", "vegetable soup", "mixed food", "mixed dish", "curry", "salad"]
        let broad = genericWords.contains {
            key == $0 || key.hasPrefix($0 + " ") || key.contains(" \($0) ")
        }
        return broad && (item.confidence < 0.9 || item.category == .unknown || item.category == .vegetarianCurry)
    }

    private func evidenceScore(_ item: ParsedFoodItem) -> Double {
        item.confidence
            + (item.quantityEvidence == nil ? 0 : 0.12)
            + (item.estimatedGrams == nil ? 0 : 0.06)
            + (item.preparationMethod == nil ? 0 : 0.03)
    }

    private func hasIdentity(_ item: ParsedFoodItem) -> Bool {
        !item.canonicalSearchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !(item.regionalName ?? item.originalText).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Reframes one photograph into overlapping spatial views for the independent
/// inventory pass. It helps the vision model inspect foods at the edges of a
/// large plate without uploading additional photographs or requiring the user
/// to type a hint.
struct SpatialPlateReviewImageService: Sendable {
    func make(from image: PreparedFoodImage) -> PreparedFoodImage? {
        guard image.pixelWidth >= 64, image.pixelHeight >= 64,
              let source = CGImageSourceCreateWithData(image.data as CFData, nil),
              let original = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }

        let canvasSide = 2_048
        guard let context = CGContext(
            data: nil,
            width: canvasSide,
            height: canvasSide,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setFillColor(CGColor(gray: 0.96, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: canvasSide, height: canvasSide))
        context.interpolationQuality = .high

        let width = CGFloat(original.width)
        let height = CGFloat(original.height)
        let crops = [
            CGRect(x: 0, y: height * 0.40, width: width, height: height * 0.60),
            CGRect(x: 0, y: 0, width: width, height: height * 0.60),
            CGRect(x: 0, y: 0, width: width * 0.60, height: height),
            CGRect(x: width * 0.40, y: 0, width: width * 0.60, height: height)
        ]
        let cells = [
            CGRect(x: 0, y: 1_024, width: 1_024, height: 1_024),
            CGRect(x: 1_024, y: 1_024, width: 1_024, height: 1_024),
            CGRect(x: 0, y: 0, width: 1_024, height: 1_024),
            CGRect(x: 1_024, y: 0, width: 1_024, height: 1_024)
        ]

        for (crop, cell) in zip(crops, cells) {
            guard let cropped = original.cropping(to: crop.integral) else { continue }
            drawAspectFit(cropped, in: cell.insetBy(dx: 6, dy: 6), context: context)
        }

        guard let montage = context.makeImage() else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            "public.jpeg" as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, montage, [
            kCGImageDestinationLossyCompressionQuality: 0.82
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination), output.length > 0 else { return nil }

        return PreparedFoodImage(
            data: output as Data,
            mimeType: "image/jpeg",
            pixelWidth: canvasSide,
            pixelHeight: canvasSide,
            // A montage is a distinct provider request. Reusing the original
            // reference made diagnostics and any intermediary cache unable to
            // distinguish the verification pass from the user's photo.
            imageReference: .transient()
        )
    }

    private func drawAspectFit(_ image: CGImage, in destination: CGRect, context: CGContext) {
        let scale = min(
            destination.width / CGFloat(image.width),
            destination.height / CGFloat(image.height)
        )
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        let rect = CGRect(
            x: destination.midX - size.width / 2,
            y: destination.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        context.draw(image, in: rect)
    }
}

/// Clarification text can be produced by interpretation, nutrition fallback
/// and UI correction stages. UUID-based identity cannot remove duplicates, so
/// questions are canonicalised by their readable content at the boundary.
enum SemanticQuestionDeduplicator {
    static func uniqueStrings(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(normalizedKey(trimmed)).inserted else { return nil }
            return trimmed
        }
    }

    static func uniqueQuestions(_ values: [ClarificationQuestion]) -> [ClarificationQuestion] {
        var result: [ClarificationQuestion] = []
        var indexByKey: [String: Int] = [:]
        for question in values {
            let key = normalizedKey(question.question)
            guard !key.isEmpty else { continue }
            if let index = indexByKey[key] {
                if usefulness(of: question) > usefulness(of: result[index]) {
                    result[index] = question
                }
            } else {
                indexByKey[key] = result.count
                result.append(question)
            }
        }
        return result
    }

    static func normalizedKey(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func usefulness(of question: ClarificationQuestion) -> Int {
        (question.answer == nil ? 0 : 100)
            + (question.answerType == .freeText ? 0 : 10)
            + question.options.count
            + (question.relatedFoodItemId == nil ? 0 : 1)
    }
}

/// Structured vision still produces hypotheses. Countable foods must carry
/// visual count evidence or remain explicitly reviewable instead of receiving
/// an unjustified high-confidence default of one.
struct PhotoParseIntegrityService: Sendable {
    func audit(_ parse: MealParseResult) -> MealParseResult {
        var audited = parse
        var questions = audited.clarificationQuestions
        audited.detectedItems = audited.detectedItems.map { item in
            guard isVisuallyCountable(item) else { return item }
            let evidence = item.quantityEvidence?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard evidence.isEmpty else { return item }

            var reviewed = item
            reviewed.confidence = min(reviewed.confidence, 0.74)
            reviewed.requiresClarification = true
            let name = reviewed.regionalName ?? reviewed.originalText
            let question = "How many \(name) were visible?"
            if !questions.contains(question) { questions.append(question) }
            return reviewed
        }
        audited.clarificationQuestions = SemanticQuestionDeduplicator.uniqueStrings(questions)
        audited.confidence = min(audited.confidence, audited.detectedItems.map(\.confidence).min() ?? audited.confidence)
        return audited
    }

    private func isVisuallyCountable(_ item: ParsedFoodItem) -> Bool {
        if item.category == .egg || item.category == .bread { return true }
        let unit = item.unit?.lowercased() ?? ""
        return ["whole", "whole egg", "egg", "eggs", "piece", "pieces", "roti", "chapati", "naan", "paratha"]
            .contains(unit)
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

    /// A photo can have valid nutrition for one item and still be an unsafe
    /// inventory. This is the failure mode behind a plate containing eggs,
    /// sprouts and nuts being reduced to one peanut: the one item is valid in
    /// isolation, but it is not enough evidence that the whole photograph was
    /// inspected. Keep the rule deliberately conservative and semantic so it
    /// applies to any salient garnish/ingredient, not just one named meal.
    func requiresInventoryRecovery(_ result: MealAnalysisResult) -> Bool {
        guard result.imageType == .originalPhoto,
              result.detectedItems.count == 1,
              let item = result.detectedItems.first else { return false }

        if result.overallConfidence == .low || result.overallConfidence == .unknown {
            return true
        }

        let identity = item.canonicalFoodId
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
        let source = item.displayName.lowercased()
        let smallVisualIdentities = [
            "peanut", "almond", "walnut", "mixed-nuts", "nut", "seed", "seeds",
            "garnish", "sprinkle", "topping"
        ]
        if smallVisualIdentities.contains(where: { identity == $0 || identity.contains($0) || source.contains($0) }) {
            return true
        }

        // A one-piece serving with only a gram or two is another useful,
        // provider-independent signal that the classifier surfaced a garnish
        // rather than the meal occupying the plate.
        if item.estimatedWeightGrams.map({ $0 > 0 && $0 <= 5 }) == true {
            return true
        }

        return false
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
        var remoteFailed = false
        var remoteIncomplete: MealAnalysisResult?
        var remoteNeedsInventoryRecovery = false

        // Structured vision owns food identity when it is available. Running
        // the generic whole-image classifier first added device work and
        // delayed every successful backend result, even though those broad
        // labels were discarded afterwards.
        if let remote {
            do {
                let remoteResult = try await remote.analyse(image, dishHint: description)
                // A late response from a previous photo is valid JSON, but it
                // is not valid for this review. Every remote implementation
                // must carry the image identity through its result so the
                // orchestrator can reject cross-request contamination before
                // completeness or persistence is evaluated.
                guard remoteResult.imageReference == image.imageReference else {
                    remoteFailed = true
                    FoodLoggingDiagnostics.record("photo.classification", fields: [
                        "route": "structured-backend-stale-result",
                        "expectedReference": image.imageReference.identifier,
                        "responseReference": remoteResult.imageReference.identifier
                    ])
                    throw FoodAnalysisError.malformedProviderResponse
                }
                // Inventory coverage is a separate gate from nutrition
                // completeness. A single valid peanut (or other tiny
                // garnish) can have perfectly plausible nutrition while
                // still being an unsafe representation of a full plate.
                let needsInventoryRecovery = completeness.requiresInventoryRecovery(remoteResult)
                let report = completeness.evaluate(remoteResult)
                if report.isComplete && !needsInventoryRecovery {
                    FoodLoggingDiagnostics.record("photo.classification", fields: [
                        "route": "structured-backend",
                        "candidateCount": String(remoteResult.detectedItems.count),
                        "remoteAttempted": "true",
                        "complete": "true"
                    ])
                    return remoteResult
                }
                remoteIncomplete = remoteResult
                remoteNeedsInventoryRecovery = needsInventoryRecovery
            } catch {
                remoteFailed = true
                FoodLoggingDiagnostics.record("photo.classification", fields: [
                    "route": "structured-backend-failed",
                    "reason": safeRemoteFailureReason(error)
                ])
            }
        }

        if var remoteIncomplete, !remoteIncomplete.detectedItems.isEmpty, !remoteNeedsInventoryRecovery {
            remoteIncomplete.warnings.insert(
                "The image was interpreted, but nutrition still needs confirmation before it can be saved.",
                at: 0
            )
            FoodLoggingDiagnostics.record("photo.classification", fields: [
                "route": "structured-backend-incomplete",
                "candidateCount": String(remoteIncomplete.detectedItems.count),
                "remoteAttempted": "true",
                "complete": "false"
            ])
            return remoteIncomplete
        }

        if remoteNeedsInventoryRecovery {
            FoodLoggingDiagnostics.record("photo.classification", fields: [
                "route": "structured-backend-sparse-inventory",
                "candidateCount": String(remoteIncomplete?.detectedItems.count ?? 0),
                "remoteAttempted": "true",
                "complete": "false"
            ])
        }

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

        // If the structured provider and the private classifier agree only on
        // one tiny/salient item, do not turn that agreement into a saved meal.
        // Keep the photo and route the member to the recoverable retry state;
        // a wrong one-item total is more harmful than an explicit unavailable
        // result, especially for diabetes-focused carbohydrate tracking.
        if remoteNeedsInventoryRecovery,
           let remoteIncomplete,
           !remoteIncomplete.detectedItems.isEmpty,
           result.detectedItems.count <= 1,
           localCompleteness.isComplete || !candidates.isEmpty {
            var unresolved = local.makeAnalysis(
                description: "",
                imageReference: image.imageReference,
                imageType: .originalPhoto
            )
            unresolved.recognitionModelVersion = "Structured vision returned a sparse plate inventory"
            unresolved.warnings.insert(
                "I could verify one visible item, but the photo may contain more foods. Retry AI recognition before saving.",
                at: 0
            )
            FoodLoggingDiagnostics.record("photo.classification", fields: [
                "route": "sparse-inventory-withheld",
                "candidateCount": String(candidates.count),
                "remoteAttempted": "true",
                "remoteFailed": String(remoteFailed)
            ])
            return unresolved
        }

        // A generic whole-image classifier can produce a nutritionally complete
        // but visually wrong list. When structured vision is configured, its
        // component-aware interpretation owns food identity; on-device labels
        // are a private resilience fallback only when the backend fails.
        if localCompleteness.isComplete {
            let liveRecognitionUnavailable = remote == nil || remoteFailed
            if liveRecognitionUnavailable,
               !isSafeFallback(memberDescription: trimmedDescription) {
                var unresolved = local.makeAnalysis(
                    description: "",
                    imageReference: image.imageReference,
                    imageType: .originalPhoto
                )
                unresolved.recognitionModelVersion = "On-device whole-image suggestions withheld"
                unresolved.warnings.insert(
                    remoteFailed
                        ? "Live recognition is unavailable. The private whole-image suggestions were too broad to identify this plate safely."
                        : "Secure AI recognition is not configured. The private whole-image suggestions were too broad to identify this plate safely.",
                    at: 0
                )
                FoodLoggingDiagnostics.record("photo.classification", fields: [
                    "route": "unsafe-on-device-suggestions-withheld",
                    "candidateCount": String(candidates.count),
                    "remoteAttempted": String(remote != nil),
                    "remoteFailed": String(remoteFailed)
                ])
                return unresolved
            }
            if remoteFailed {
                result.overallConfidence = .low
                result.warnings.insert(
                    "Live recognition is unavailable, so this private on-device estimate needs your review.",
                    at: 0
                )
                result.clarificationQuestions.insert(
                    ClarificationQuestion(
                        id: UUID(),
                        relatedFoodItemId: nil,
                        question: "Live recognition is unavailable. Do these food names match your photo?",
                        answerType: .yesNo,
                        options: ["Yes", "No — I’ll edit them"],
                        impactLevel: .high,
                        answer: nil
                    ),
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

    private func isSafeFallback(memberDescription: String) -> Bool {
        // Whole-image classification cannot prove that a plate contains only
        // one food. It is useful as a private suggestion, but never sufficient
        // to auto-confirm an image-only meal. A member-entered description is
        // explicit evidence and may still use the local nutrition path.
        !memberDescription.isEmpty
    }

    private func safeRemoteFailureReason(_ error: Error) -> String {
        if let error = error as? URLError {
            return "url-\(error.code.rawValue)"
        }
        if let error = error as? FoodAnalysisError {
            switch error {
            case .endpointUnavailable: return "endpoint-unavailable"
            case .malformedProviderResponse: return "malformed-response"
            case .unsupportedImage: return "unsupported-image"
            case .imageTooLarge: return "image-too-large"
            case .unauthenticatedBackend: return "unauthenticated"
            }
        }
        return "provider-error"
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
        FoodInputNormalizer.tokens(for: value).joined(separator: " ")
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

/// Rebuilds an edited component from a stable serving basis. Catalog foods are
/// always recalculated from their per-100 g record. Provider or AI-recognised
/// foods that are not in the local catalog retain their traceable source and
/// scale from the previous raw nutrition/weight pair. This keeps edits
/// responsive without repeatedly scaling already-rounded display totals.
struct MealItemNutritionRecalculator: Sendable {
    let catalog: IndianFoodCatalogService
    let portions: StandardPortionEstimationService
    let nutrition: CatalogNutritionLookupService
    let fallback: CuratedNutritionFallbackService
    let glycaemic: CatalogGlycaemicDataService
    let validation: any NutritionValidationService

    init(
        catalog: IndianFoodCatalogService = IndianFoodCatalogService(),
        portions: StandardPortionEstimationService = .init(),
        nutrition: CatalogNutritionLookupService = .init(),
        fallback: CuratedNutritionFallbackService? = nil,
        glycaemic: CatalogGlycaemicDataService = .init(),
        validation: any NutritionValidationService = DefaultNutritionValidationService()
    ) {
        self.catalog = catalog
        self.portions = portions
        self.nutrition = nutrition
        self.fallback = fallback ?? CuratedNutritionFallbackService(
            catalog: catalog,
            portions: portions,
            validation: validation
        )
        self.glycaemic = glycaemic
        self.validation = validation
    }

    func recalculate(
        _ item: DetectedFoodItem,
        previous: DetectedFoodItem? = nil
    ) -> DetectedFoodItem {
        if let definition = catalog.food(canonicalID: item.canonicalFoodId) {
            return recalculateCatalogItem(item, definition: definition)
        }
        return recalculateProviderItem(item, previous: previous ?? item)
    }

    private func recalculateCatalogItem(
        _ original: DetectedFoodItem,
        definition: IndianFoodDefinition
    ) -> DetectedFoodItem {
        var item = original
        let weight = portions.estimatedWeight(
            quantity: item.quantity,
            unit: item.servingUnit,
            food: definition
        )
        let catalogLookup = nutrition.nutrition(for: definition, estimatedWeightGrams: weight)
        let fallbackResolution = catalogLookup.values.isEmpty
            ? fallback.resolve(
                item: ParsedFoodItem(
                    originalText: item.matchedAlias ?? item.displayName,
                    canonicalSearchName: definition.englishName,
                    regionalName: item.regionalName,
                    quantity: item.quantity,
                    unit: item.servingUnit.rawValue,
                    estimatedGrams: weight,
                    preparationMethod: item.preparationMethod,
                    confidence: item.confidenceScore
                ),
                canonical: CanonicalFoodMatch(
                    food: definition,
                    matchedAlias: item.matchedAlias ?? item.displayName,
                    confidence: item.confidenceScore,
                    source: "member-corrected-canonical"
                )
            )
            : nil
        let lookup = fallbackResolution?.lookup ?? catalogLookup
        let resolvedValues = nutritionIncludingShakeBase(
            lookup.values,
            profile: item.supplementProfile
        )
        let report = validation.validate(
            rawValues: resolvedValues,
            canonicalFoodID: definition.canonicalId,
            quantity: item.quantity,
            servingUnit: item.servingUnit,
            estimatedWeightGrams: weight
        )

        item.estimatedWeightGrams = weight
        item.rawNutrition = resolvedValues
        item.nutrition = report.safeValues ?? .unavailable
        item.nutritionValidation = report
        item.nutritionProvenance = report.isApproved ? lookup.provenance : .unavailable
        if let fallbackResolution {
            item.assumptions = fallbackResolution.assumptions
        }
        item.glycaemicInformation = glycaemic.information(
            for: definition,
            availableCarbohydrateGrams: report.safeValues?.availableCarbohydrateGrams
        )
        item.warnings = nutritionWarnings(from: report, preserving: item.warnings)
        return item
    }

    private func recalculateProviderItem(
        _ original: DetectedFoodItem,
        previous: DetectedFoodItem
    ) -> DetectedFoodItem {
        var item = original
        let newWeight = estimatedWeight(for: item, previous: previous)
        let oldWeight = previous.estimatedWeightGrams
        let oldValues = previous.rawNutrition ?? previous.nutrition

        let multiplier: Double? = {
            if let oldWeight, oldWeight.isFinite, oldWeight > 0,
               let newWeight, newWeight.isFinite, newWeight > 0 {
                return newWeight / oldWeight
            }
            guard previous.quantity.isFinite, previous.quantity > 0,
                  item.quantity.isFinite, item.quantity > 0,
                  previous.servingUnit == item.servingUnit else { return nil }
            return item.quantity / previous.quantity
        }()

        // If no safe conversion is available, preserve the source values and
        // surface validation instead of silently treating the new amount as
        // the old serving.
        let resolvedValues = multiplier.map { oldValues.scaled(by: $0) } ?? oldValues
        let report = validation.validate(
            rawValues: resolvedValues,
            canonicalFoodID: item.canonicalFoodId,
            quantity: item.quantity,
            servingUnit: item.servingUnit,
            estimatedWeightGrams: newWeight
        )

        item.estimatedWeightGrams = newWeight
        item.rawNutrition = resolvedValues
        item.nutrition = report.safeValues ?? .unavailable
        item.nutritionValidation = report
        item.warnings = nutritionWarnings(from: report, preserving: item.warnings)
        return item
    }

    private func estimatedWeight(
        for item: DetectedFoodItem,
        previous: DetectedFoodItem
    ) -> Double? {
        switch item.servingUnit {
        case .grams, .millilitres:
            return item.quantity
        case .teaspoon:
            return item.quantity * 5
        case .tablespoon:
            return item.quantity * 15
        case .katori:
            return item.quantity * 150
        case .smallBowl:
            return item.quantity * 120
        case .mediumBowl:
            return item.quantity * 200
        case .largeBowl:
            return item.quantity * 300
        case .cup:
            return item.quantity * 240
        case .ladle:
            return item.quantity * 60
        case .piece:
            return item.quantity * 60
        case .roti:
            return item.quantity * 35
        case .naan:
            return item.quantity * 90
        case .paratha:
            return item.quantity * 90
        case .poori:
            return item.quantity * 35
        case .bhatura:
            return item.quantity * 100
        case .dosa:
            return item.quantity * 120
        case .idli:
            return item.quantity * 40
        case .vada:
            return item.quantity * 55
        case .slice:
            return item.quantity * 30
        case .glass:
            return item.quantity * 250
        case .plate:
            return item.quantity * 300
        case .wholeEgg:
            return item.quantity * 50
        case .scoop:
            let gramsPerScoop = item.supplementProfile?.gramsPerScoop
                ?? previous.supplementProfile?.gramsPerScoop
                ?? 30
            return item.quantity * gramsPerScoop
        case .serving:
            guard previous.servingUnit == .serving,
                  previous.quantity.isFinite, previous.quantity > 0,
                  let previousWeight = previous.estimatedWeightGrams else {
                return item.estimatedWeightGrams
            }
            return previousWeight * item.quantity / previous.quantity
        }
    }

    private func nutritionIncludingShakeBase(
        _ powder: NutritionValues,
        profile: SupplementProductProfile?
    ) -> NutritionValues {
        guard profile?.base == .milk,
              let milk = catalog.normalise("milk") else { return powder }
        let milkWeight = milk.standardServing?.grams ?? 240
        let milkValues = nutrition.nutrition(
            for: milk,
            estimatedWeightGrams: milkWeight
        ).values
        return NutritionValues.total(of: [powder, milkValues])
    }

    private func nutritionWarnings(
        from report: NutritionValidationReport,
        preserving warnings: [String]
    ) -> [String] {
        let retained = warnings.filter {
            !$0.localizedCaseInsensitiveContains("nutrition unavailable")
                && !$0.localizedCaseInsensitiveContains("serving quantity")
                && !$0.localizedCaseInsensitiveContains("serving weight")
        }
        return retained + report.issues.map(\.message)
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
                question: "What food or main dish is in this photo?",
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
            mealType: draft.mealPeriod.displayName,
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
