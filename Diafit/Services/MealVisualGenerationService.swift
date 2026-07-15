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
        if let fileName = meal.visualIdentity?.assetFileName {
            await assets.remove(fileName: fileName)
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
