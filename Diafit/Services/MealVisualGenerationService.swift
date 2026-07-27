import Foundation

enum MealVisualGenerationError: LocalizedError, Equatable {
    case providerUnavailable
    case invalidAssociation
    case invalidImagePayload
    case imageTooLarge

    var errorDescription: String? {
        switch self {
        case .providerUnavailable:
            return "Editorial image generation is unavailable. The verified component visual is still available."
        case .invalidAssociation:
            return "The image response no longer matches this meal. It was safely ignored."
        case .invalidImagePayload:
            return "The image provider returned a file that could not be safely used."
        case .imageTooLarge:
            return "The generated image was too large to store safely."
        }
    }
}

struct GeneratedMealVisual: Sendable {
    let mealID: UUID
    let requestID: UUID
    let cacheKey: String
    let mimeType: String
    let data: Data
}

protocol MealVisualGenerating: Sendable {
    var isConfigured: Bool { get }
    func generate(_ request: MealVisualRequest) async throws -> GeneratedMealVisual
}

struct UnavailableMealVisualGenerator: MealVisualGenerating {
    let isConfigured = false

    func generate(_ request: MealVisualRequest) async throws -> GeneratedMealVisual {
        throw MealVisualGenerationError.providerUnavailable
    }
}

/// Calls Diafit's authenticated backend, never an image-provider endpoint. The
/// provider credential remains server-side and responses are accepted only
/// when all meal/request/cache association fields match.
struct BackendMealVisualGenerator: MealVisualGenerating {
    let endpoint: URL
    let tokenProvider: BackendAccessTokenProvider
    let session: URLSession
    let isConfigured = true

    init(endpoint: URL, tokenProvider: BackendAccessTokenProvider, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.tokenProvider = tokenProvider
        self.session = session
    }

    func generate(_ request: MealVisualRequest) async throws -> GeneratedMealVisual {
        let token = try await tokenProvider.accessToken()
        var urlRequest = URLRequest(url: endpoint.appending(path: "v1/meal-visual"))
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 45
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue(request.requestID.uuidString, forHTTPHeaderField: "Idempotency-Key")
        urlRequest.httpBody = try JSONEncoder().encode(RequestBody(
            apiVersion: "v1",
            mealID: request.mealID,
            requestID: request.requestID,
            cacheKey: request.cacheKey,
            canonicalComponentIDs: request.canonicalComponentIDs,
            quantitySignature: request.quantitySignature,
            styleVersion: request.styleVersion,
            prompt: request.prompt
        ))

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let body = try? JSONDecoder().decode(ResponseBody.self, from: data),
              let imageData = Data(base64Encoded: body.imageBase64) else {
            throw MealVisualGenerationError.providerUnavailable
        }
        return GeneratedMealVisual(
            mealID: body.mealID,
            requestID: body.requestID,
            cacheKey: body.cacheKey,
            mimeType: body.mimeType,
            data: imageData
        )
    }

    private struct RequestBody: Encodable {
        let apiVersion: String
        let mealID: UUID
        let requestID: UUID
        let cacheKey: String
        let canonicalComponentIDs: [String]
        let quantitySignature: [String]
        let styleVersion: String
        let prompt: String
    }

    private struct ResponseBody: Decodable {
        let mealID: UUID
        let requestID: UUID
        let cacheKey: String
        let mimeType: String
        let imageBase64: String
    }
}

/// Generated images live separately from the diary JSON. The archive stores
/// only a sandbox-relative file name, never an absolute path or provider URL.
actor MealVisualAssetStore {
    private let directory: URL
    private let fileManager: FileManager
    private let appliesFileProtection: Bool
    private let maximumBytes = 12_000_000

    init(
        directory: URL,
        fileManager: FileManager = .default,
        appliesFileProtection: Bool = true
    ) {
        self.directory = directory
        self.fileManager = fileManager
        self.appliesFileProtection = appliesFileProtection
    }

    static func live(fileManager: FileManager = .default) -> MealVisualAssetStore {
        MealVisualAssetStore(directory: Self.liveDirectory(fileManager: fileManager), fileManager: fileManager)
    }

    func store(_ visual: GeneratedMealVisual) throws -> String {
        guard visual.data.count <= maximumBytes else { throw MealVisualGenerationError.imageTooLarge }
        let fileExtension: String
        switch visual.mimeType.lowercased() {
        case "image/png":
            guard Self.isPNG(visual.data) else { throw MealVisualGenerationError.invalidImagePayload }
            fileExtension = "png"
        case "image/jpeg", "image/jpg":
            guard Self.isJPEG(visual.data) else { throw MealVisualGenerationError.invalidImagePayload }
            fileExtension = "jpg"
        default:
            throw MealVisualGenerationError.invalidImagePayload
        }

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileName = "meal-\(visual.cacheKey)-\(visual.requestID.uuidString.lowercased()).\(fileExtension)"
        let destination = directory.appendingPathComponent(fileName, isDirectory: false)
        try visual.data.write(to: destination, options: [.atomic])
        if appliesFileProtection {
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: destination.path
            )
        }
        return fileName
    }

    func storeOriginalPhoto(data: Data, mealID: UUID, requestID: UUID) throws -> MealVisualAsset {
        guard data.count <= maximumBytes else { throw MealVisualGenerationError.imageTooLarge }
        let mimeType: String
        let fileExtension: String
        if Self.isJPEG(data) {
            mimeType = "image/jpeg"
            fileExtension = "jpg"
        } else if Self.isPNG(data) {
            mimeType = "image/png"
            fileExtension = "png"
        } else {
            throw MealVisualGenerationError.invalidImagePayload
        }

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let cacheKey = "original-\(mealID.uuidString.lowercased())"
        let fileName = "\(cacheKey)-\(requestID.uuidString.lowercased()).\(fileExtension)"
        let destination = directory.appendingPathComponent(fileName, isDirectory: false)
        try data.write(to: destination, options: [.atomic])
        if appliesFileProtection {
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: destination.path
            )
        }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDestination = destination
        try? mutableDestination.setResourceValues(values)
        return MealVisualAsset(
            requestID: requestID,
            cacheKey: cacheKey,
            fileName: fileName,
            mimeType: mimeType
        )
    }

    func remove(fileName: String) {
        guard Self.isSafeFileName(fileName) else { return }
        try? fileManager.removeItem(at: directory.appendingPathComponent(fileName, isDirectory: false))
    }

    nonisolated static func liveURL(for fileName: String, fileManager: FileManager = .default) -> URL? {
        guard isSafeFileName(fileName) else { return nil }
        return liveDirectory(fileManager: fileManager).appendingPathComponent(fileName, isDirectory: false)
    }

    private nonisolated static func liveDirectory(fileManager: FileManager) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Diafit", isDirectory: true)
            .appendingPathComponent("MealVisuals", isDirectory: true)
    }

    private nonisolated static func isSafeFileName(_ fileName: String) -> Bool {
        !fileName.isEmpty
            && fileName == URL(fileURLWithPath: fileName).lastPathComponent
            && !fileName.contains("..")
            && fileName.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." }
    }

    private nonisolated static func isPNG(_ data: Data) -> Bool {
        data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }

    private nonisolated static func isJPEG(_ data: Data) -> Bool {
        data.count >= 4 && data.starts(with: [0xFF, 0xD8]) && data.suffix(2) == Data([0xFF, 0xD9])
    }
}

/// Owns request lifecycle and the only path by which asynchronous provider
/// output can enter a persisted draft. A late result cannot cross meals,
/// requests, edits, or deletion boundaries.
struct MealVisualGenerationService: Sendable {
    let generator: any MealVisualGenerating
    let assets: MealVisualAssetStore
    let ledger: MealVisualRequestLedger

    static let local = MealVisualGenerationService(
        generator: UnavailableMealVisualGenerator(),
        assets: .live(),
        ledger: MealVisualRuntime.ledger
    )

    @MainActor
    func prepare(
        draft: MealAnalysisDraft,
        itemID: ThreadItem.ID,
        in diary: DiaryStore,
        dayID: Day.ID
    ) async {
        // A member's own confirmed photo is the truthful primary visual. Never
        // spend provider work creating a decorative replacement for it.
        guard draft.transientImageData == nil,
              draft.result.originalPhotoAsset == nil else { return }
        guard var request = draft.result.visualRequest,
              request.state != .waitingForClarification else { return }

        await ledger.begin(mealID: request.mealID, cacheKey: request.cacheKey, requestID: request.requestID)

        if !generator.isConfigured {
            request.state = .deterministicFallback
            request.failureReason = MealVisualGenerationError.providerUnavailable.errorDescription
            apply(request: request, asset: nil, to: draft, itemID: itemID, in: diary, dayID: dayID)
            await ledger.cancel(requestID: request.requestID)
            record(request, event: "visual.fallback", reason: request.failureReason)
            return
        }

        request.state = .queued
        request.failureReason = nil
        apply(request: request, asset: nil, to: draft, itemID: itemID, in: diary, dayID: dayID)

        do {
            let output = try await generator.generate(request)
            guard output.mealID == request.mealID,
                  output.requestID == request.requestID,
                  output.cacheKey == request.cacheKey else {
                throw MealVisualGenerationError.invalidAssociation
            }
            guard await ledger.canApply(
                mealID: output.mealID,
                cacheKey: output.cacheKey,
                requestID: output.requestID
            ) else { return }

            let fileName = try await assets.store(output)
            guard await ledger.finish(
                mealID: output.mealID,
                cacheKey: output.cacheKey,
                requestID: output.requestID
            ) else {
                await assets.remove(fileName: fileName)
                return
            }

            request.state = .ready
            let asset = MealVisualAsset(
                requestID: output.requestID,
                cacheKey: output.cacheKey,
                fileName: fileName,
                mimeType: output.mimeType
            )
            apply(request: request, asset: asset, to: draft, itemID: itemID, in: diary, dayID: dayID)
            record(request, event: "visual.ready", reason: nil)
        } catch {
            guard await ledger.finish(
                mealID: request.mealID,
                cacheKey: request.cacheKey,
                requestID: request.requestID
            ) else { return }
            request.state = .failed
            request.failureReason = (error as? LocalizedError)?.errorDescription
                ?? "Editorial image generation failed. Your nutrition draft is unaffected."
            apply(request: request, asset: nil, to: draft, itemID: itemID, in: diary, dayID: dayID)
            record(request, event: "visual.failed", reason: request.failureReason)
        }
    }

    func delete(meal: Meal) async {
        await ledger.delete(mealID: meal.id)
        let fileNames = Set([
            meal.visualIdentity?.assetFileName,
            meal.analysis?.originalPhotoAsset?.fileName,
            meal.analysis?.generatedVisualAsset?.fileName
        ].compactMap { $0 })
        for fileName in fileNames {
            await assets.remove(fileName: fileName)
        }
    }

    /// Confirmation explicitly retains a prepared, metadata-stripped photo as
    /// the meal's local visual. Failure never rolls back nutrition persistence.
    @MainActor
    func retainOriginalPhoto(
        _ data: Data,
        mealID: UUID,
        in diary: DiaryStore,
        dayID: Day.ID
    ) async {
        guard var meal = diary.day(id: dayID)?.meals.first(where: { $0.id == mealID }),
              var analysis = meal.analysis else { return }
        do {
            let requestID = analysis.visualRequest?.requestID ?? analysis.analysisId
            let asset = try await assets.storeOriginalPhoto(
                data: data,
                mealID: mealID,
                requestID: requestID
            )
            analysis.originalPhotoAsset = asset
            analysis.imageReference = MealImageReference(
                identifier: analysis.imageReference.identifier,
                retention: .memberPermitted
            )
            analysis.imageType = .originalPhoto
            meal.analysis = analysis
            meal.visualIdentity = MealVisualIdentityFactory().make(
                mealID: meal.id,
                result: analysis,
                artwork: meal.artwork
            )
            diary.update(meal, in: dayID)
            FoodLoggingDiagnostics.record("visual.original-retained", fields: [
                "mealID": mealID.uuidString,
                "requestID": requestID.uuidString
            ])
        } catch {
            FoodLoggingDiagnostics.record("visual.original-retention-failed", fields: [
                "mealID": mealID.uuidString,
                "reason": String(describing: type(of: error))
            ])
        }
    }

    @MainActor
    private func apply(
        request: MealVisualRequest,
        asset: MealVisualAsset?,
        to original: MealAnalysisDraft,
        itemID: ThreadItem.ID,
        in diary: DiaryStore,
        dayID: Day.ID
    ) {
        guard let current = diary.day(id: dayID)?.messages.first(where: { $0.id == itemID }) else { return }
        switch current.kind {
        case .mealAnalysis(var draft):
            guard draft.result.visualRequest?.requestID == request.requestID else { return }
            draft.result.visualRequest = request
            draft.result.generatedVisualAsset = asset
            if asset != nil { draft.result.imageType = .generatedEditorial }
            diary.update(draft, for: itemID, in: dayID)
        case .meal(var meal):
            // Editing a confirmed meal creates a replacement request before
            // the saved analysis is replaced. The meal ID is the durable
            // boundary; accepting the new request here lets the visual retry
            // complete without prematurely overwriting nutrition values.
            guard meal.id == request.mealID,
                  var analysis = meal.analysis else { return }
            analysis.visualRequest = request
            analysis.generatedVisualAsset = asset
            if asset != nil { analysis.imageType = .generatedEditorial }
            meal.analysis = analysis
            meal.visualIdentity = MealVisualIdentityFactory().make(
                mealID: meal.id,
                result: analysis,
                artwork: meal.artwork
            )
            diary.update(meal, in: dayID)
        default:
            return
        }
    }

    private func record(_ request: MealVisualRequest, event: String, reason: String?) {
        FoodLoggingDiagnostics.record(event, fields: [
            "cacheKey": String(request.cacheKey.prefix(12)),
            "mealID": request.mealID.uuidString,
            "requestID": request.requestID.uuidString,
            "state": request.state.rawValue,
            "failure": reason ?? "none"
        ])
    }
}

enum MealVisualRuntime {
    static let ledger = MealVisualRequestLedger()
}
