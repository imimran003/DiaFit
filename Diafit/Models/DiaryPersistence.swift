import Foundation

struct DiaryArchive: Codable, Hashable {
    static let currentVersion = 2

    let schemaVersion: Int
    let savedAt: Date
    let days: [Day]
    let manualStrengthDays: [Date]

    init(schemaVersion: Int = currentVersion, savedAt: Date = .now, days: [Day], manualStrengthDays: [Date] = []) {
        self.schemaVersion = schemaVersion
        self.savedAt = savedAt
        self.days = days
        self.manualStrengthDays = manualStrengthDays
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, savedAt, days, manualStrengthDays
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        savedAt = try container.decode(Date.self, forKey: .savedAt)
        days = try container.decode([Day].self, forKey: .days)
        manualStrengthDays = try container.decodeIfPresent([Date].self, forKey: .manualStrengthDays) ?? []
    }
}

enum DiaryPersistenceError: Error, Equatable {
    case unsupportedSchema(found: Int, current: Int)
    case invalidArchive
}

protocol DiaryPersisting {
    func load() throws -> DiaryArchive?
    func save(_ archive: DiaryArchive) throws
}

/// Destructive operations are kept separate from normal persistence so a
/// caller cannot accidentally erase a diary while saving an edit. The
/// privacy controls use this capability only after explicit confirmation.
protocol DiaryDataDeleting: Sendable {
    func deleteStoredArchive() throws
}

/// Used by previews and deterministic UI tests. It preserves the same store
/// transaction behavior without writing test fixtures into the member diary.
struct TransientDiaryPersistence: DiaryPersisting, DiaryDataDeleting {
    func load() throws -> DiaryArchive? { nil }
    func save(_ archive: DiaryArchive) throws {}
    func deleteStoredArchive() throws {}
}

struct FileDiaryPersistence: DiaryPersisting, DiaryDataDeleting, @unchecked Sendable {
    let fileURL: URL
    var appliesFileProtection: Bool = true
    private let fileManager: FileManager

    init(
        fileURL: URL,
        appliesFileProtection: Bool = true,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.appliesFileProtection = appliesFileProtection
        self.fileManager = fileManager
    }

    static func live(fileName: String = "diary.json", fileManager: FileManager = .default) -> FileDiaryPersistence {
        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = supportDirectory.appendingPathComponent("Diafit", isDirectory: true)
        return FileDiaryPersistence(
            fileURL: directory.appendingPathComponent(fileName, isDirectory: false),
            fileManager: fileManager
        )
    }

    func load() throws -> DiaryArchive? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        let decoder = Self.decoder
        guard let header = try? decoder.decode(ArchiveHeader.self, from: data) else {
            throw DiaryPersistenceError.invalidArchive
        }
        guard header.schemaVersion <= DiaryArchive.currentVersion else {
            throw DiaryPersistenceError.unsupportedSchema(
                found: header.schemaVersion,
                current: DiaryArchive.currentVersion
            )
        }
        guard let archive = try? decoder.decode(DiaryArchive.self, from: data) else {
            // Keeping this explicit prevents corrupt records from being
            // treated as an empty diary and overwritten.
            throw DiaryPersistenceError.invalidArchive
        }
        if header.schemaVersion == DiaryArchive.currentVersion { return archive }
        // Version 1 stored legacy checkpoint thread items. The new glucose
        // case is additive, so decoding the old days preserves every meal and
        // checkpoint while the next save upgrades the archive header.
        return DiaryArchive(
            schemaVersion: DiaryArchive.currentVersion,
            savedAt: archive.savedAt,
            days: archive.days,
            manualStrengthDays: archive.manualStrengthDays
        )
    }

    func save(_ archive: DiaryArchive) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Self.encoder.encode(archive)
        try data.write(to: fileURL, options: [.atomic])
        guard appliesFileProtection else { return }
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
    }

    func deleteStoredArchive() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }

    private struct ArchiveHeader: Decodable {
        let schemaVersion: Int
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}
