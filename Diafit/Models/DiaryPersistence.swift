import Foundation

struct DiaryArchive: Codable, Hashable {
    static let currentVersion = 1

    let schemaVersion: Int
    let savedAt: Date
    let days: [Day]

    init(schemaVersion: Int = currentVersion, savedAt: Date = .now, days: [Day]) {
        self.schemaVersion = schemaVersion
        self.savedAt = savedAt
        self.days = days
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

/// Used by previews and deterministic UI tests. It preserves the same store
/// transaction behavior without writing test fixtures into the member diary.
struct TransientDiaryPersistence: DiaryPersisting {
    func load() throws -> DiaryArchive? { nil }
    func save(_ archive: DiaryArchive) throws {}
}

struct FileDiaryPersistence: DiaryPersisting {
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
        guard header.schemaVersion == DiaryArchive.currentVersion,
              let archive = try? decoder.decode(DiaryArchive.self, from: data) else {
            // There are no older persisted schemas in the repository. Keeping
            // this explicit prevents corrupt or unknown records being treated
            // as an empty diary and overwritten.
            throw DiaryPersistenceError.invalidArchive
        }
        return archive
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
