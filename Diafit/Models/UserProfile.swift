import Foundation
import Combine

enum ProfileSex: String, Codable, CaseIterable, Hashable, Sendable {
    case notSpecified
    case female
    case male
    case intersex

    var displayName: String {
        switch self {
        case .notSpecified: return "Prefer not to say"
        case .female: return "Female"
        case .male: return "Male"
        case .intersex: return "Intersex"
        }
    }
}

enum DiabetesContext: String, Codable, CaseIterable, Hashable, Sendable {
    case notSpecified
    case type1
    case type2
    case prediabetes
    case gestational
    case other

    var displayName: String {
        switch self {
        case .notSpecified: return "Not provided"
        case .type1: return "Type 1"
        case .type2: return "Type 2"
        case .prediabetes: return "Prediabetes"
        case .gestational: return "Gestational"
        case .other: return "Other"
        }
    }
}

enum ProfileActivityLevel: String, Codable, CaseIterable, Hashable, Sendable {
    case notSpecified
    case mostlySeated
    case lightlyActive
    case active
    case veryActive

    var displayName: String {
        switch self {
        case .notSpecified: return "Not provided"
        case .mostlySeated: return "Mostly seated"
        case .lightlyActive: return "Lightly active"
        case .active: return "Active"
        case .veryActive: return "Very active"
        }
    }
}

enum DietaryPattern: String, Codable, CaseIterable, Hashable, Sendable {
    case notSpecified
    case vegetarian
    case vegan
    case pescatarian
    case omnivore
    case other

    var displayName: String {
        switch self {
        case .notSpecified: return "Not provided"
        case .vegetarian: return "Vegetarian"
        case .vegan: return "Vegan"
        case .pescatarian: return "Pescatarian"
        case .omnivore: return "No specific pattern"
        case .other: return "Other"
        }
    }
}

enum MeasurementSystem: String, Codable, CaseIterable, Hashable, Sendable {
    case metric
    case imperial

    var displayName: String {
        switch self {
        case .metric: return "Metric"
        case .imperial: return "Imperial"
        }
    }
}

struct UserProfile: Codable, Equatable, Sendable {
    var preferredName: String
    var dateOfBirth: Date?
    var sex: ProfileSex
    var genderIdentity: String?
    var heightCentimeters: Double?
    var weightKilograms: Double?
    var diabetesContext: DiabetesContext
    var activityLevel: ProfileActivityLevel
    var dietaryPattern: DietaryPattern
    var allergies: [String]
    var calorieGoal: Int?
    var carbohydrateGoalGrams: Int?
    var proteinGoalGrams: Int?
    var stepGoal: Int?
    var avatarJPEGData: Data?
    var updatedAt: Date

    static let empty = UserProfile(
        preferredName: "",
        dateOfBirth: nil,
        sex: .notSpecified,
        genderIdentity: nil,
        heightCentimeters: nil,
        weightKilograms: nil,
        diabetesContext: .notSpecified,
        activityLevel: .notSpecified,
        dietaryPattern: .notSpecified,
        allergies: [],
        calorieGoal: nil,
        carbohydrateGoalGrams: nil,
        proteinGoalGrams: nil,
        stepGoal: nil,
        avatarJPEGData: nil,
        updatedAt: .now
    )

    var initials: String {
        let letters = preferredName
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
        return letters.isEmpty ? "ME" : String(letters).uppercased()
    }

    func age(on date: Date = .now, calendar: Calendar = .autoupdatingCurrent) -> Int? {
        guard let dateOfBirth, dateOfBirth <= date else { return nil }
        return calendar.dateComponents([.year], from: dateOfBirth, to: date).year
    }

    var completionCount: Int {
        [
            !preferredName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            dateOfBirth != nil,
            sex != .notSpecified,
            heightCentimeters != nil,
            weightKilograms != nil,
            activityLevel != .notSpecified,
            dietaryPattern != .notSpecified
        ].filter { $0 }.count
    }

    var isEmpty: Bool { completionCount == 0 && avatarJPEGData == nil }
}

struct UserPreferences: Codable, Equatable, Sendable {
    var measurementSystem: MeasurementSystem
    var preferredGlucoseUnit: GlucoseUnit
    var hapticsEnabled: Bool

    static let `default` = UserPreferences(
        measurementSystem: .metric,
        preferredGlucoseUnit: .milligramsPerDeciliter,
        hapticsEnabled: true
    )
}

struct UserProfileArchive: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let schemaVersion: Int
    let savedAt: Date
    let profile: UserProfile
    let preferences: UserPreferences

    init(
        schemaVersion: Int = currentVersion,
        savedAt: Date = .now,
        profile: UserProfile,
        preferences: UserPreferences
    ) {
        self.schemaVersion = schemaVersion
        self.savedAt = savedAt
        self.profile = profile
        self.preferences = preferences
    }
}

enum UserProfileValidationError: LocalizedError, Equatable {
    case missingName
    case futureDateOfBirth
    case invalidHeight
    case invalidWeight
    case invalidGoal

    var errorDescription: String? {
        switch self {
        case .missingName: return "Add the name you would like Diafit to use."
        case .futureDateOfBirth: return "Check the date of birth."
        case .invalidHeight: return "Check the height."
        case .invalidWeight: return "Check the weight."
        case .invalidGoal: return "Goals must be positive numbers."
        }
    }
}

struct UserProfileValidator: Sendable {
    func validate(_ profile: UserProfile, now: Date = .now) -> Result<Void, UserProfileValidationError> {
        guard !profile.preferredName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.missingName)
        }
        if let dateOfBirth = profile.dateOfBirth, dateOfBirth > now {
            return .failure(.futureDateOfBirth)
        }
        if let height = profile.heightCentimeters,
           !height.isFinite || !(50...260).contains(height) {
            return .failure(.invalidHeight)
        }
        if let weight = profile.weightKilograms,
           !weight.isFinite || !(20...500).contains(weight) {
            return .failure(.invalidWeight)
        }
        let goals = [
            profile.calorieGoal,
            profile.carbohydrateGoalGrams,
            profile.proteinGoalGrams,
            profile.stepGoal
        ].compactMap { $0 }
        guard goals.allSatisfy({ $0 > 0 }) else { return .failure(.invalidGoal) }
        return .success(())
    }
}

enum UserProfilePersistenceError: Error, Equatable {
    case unsupportedSchema
    case invalidArchive
}

protocol UserProfilePersisting: Sendable {
    func load() throws -> UserProfileArchive?
    func save(_ archive: UserProfileArchive) throws
}

struct TransientUserProfilePersistence: UserProfilePersisting {
    func load() throws -> UserProfileArchive? { nil }
    func save(_ archive: UserProfileArchive) throws {}
}

struct FileUserProfilePersistence: UserProfilePersisting, @unchecked Sendable {
    let fileURL: URL
    var appliesFileProtection: Bool
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

    static func live(
        fileName: String = "profile.json",
        fileManager: FileManager = .default
    ) -> FileUserProfilePersistence {
        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = supportDirectory.appendingPathComponent("Diafit", isDirectory: true)
        return FileUserProfilePersistence(
            fileURL: directory.appendingPathComponent(fileName),
            fileManager: fileManager
        )
    }

    func load() throws -> UserProfileArchive? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        let decoder = Self.decoder
        guard let header = try? decoder.decode(Header.self, from: data) else {
            throw UserProfilePersistenceError.invalidArchive
        }
        guard header.schemaVersion <= UserProfileArchive.currentVersion else {
            throw UserProfilePersistenceError.unsupportedSchema
        }
        guard let archive = try? decoder.decode(UserProfileArchive.self, from: data) else {
            throw UserProfilePersistenceError.invalidArchive
        }
        return archive
    }

    func save(_ archive: UserProfileArchive) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.encoder.encode(archive).write(to: fileURL, options: .atomic)
        guard appliesFileProtection else { return }
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
    }

    private struct Header: Decodable { let schemaVersion: Int }

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

@MainActor
final class UserProfileStore: ObservableObject {
    @Published private(set) var profile: UserProfile
    @Published private(set) var preferences: UserPreferences
    @Published private(set) var persistenceIssue: String?

    private let persistence: any UserProfilePersisting
    private let validator = UserProfileValidator()

    init(
        profile: UserProfile = .empty,
        preferences: UserPreferences = .default,
        persistence: any UserProfilePersisting = TransientUserProfilePersistence()
    ) {
        self.persistence = persistence
        do {
            if let archive = try persistence.load() {
                self.profile = archive.profile
                self.preferences = archive.preferences
            } else {
                self.profile = profile
                self.preferences = preferences
            }
        } catch {
            self.profile = profile
            self.preferences = preferences
            persistenceIssue = "Your profile could not be opened. The original file was left untouched."
        }
    }

    @discardableResult
    func save(profile candidate: UserProfile, preferences: UserPreferences? = nil) -> Result<Void, Error> {
        switch validator.validate(candidate) {
        case .failure(let error):
            return .failure(error)
        case .success:
            break
        }

        var normalized = candidate
        normalized.preferredName = candidate.preferredName.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.genderIdentity = candidate.genderIdentity?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfBlank
        normalized.allergies = candidate.allergies
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        normalized.updatedAt = .now
        let resolvedPreferences = preferences ?? self.preferences

        do {
            try persistence.save(UserProfileArchive(
                profile: normalized,
                preferences: resolvedPreferences
            ))
            profile = normalized
            self.preferences = resolvedPreferences
            persistenceIssue = nil
            return .success(())
        } catch {
            persistenceIssue = "This profile change could not be saved. Check available storage and try again."
            return .failure(error)
        }
    }

    @discardableResult
    func updatePreferences(_ candidate: UserPreferences) -> Result<Void, Error> {
        do {
            try persistence.save(UserProfileArchive(profile: profile, preferences: candidate))
            preferences = candidate
            persistenceIssue = nil
            return .success(())
        } catch {
            persistenceIssue = "This setting could not be saved. Check available storage and try again."
            return .failure(error)
        }
    }

    @discardableResult
    func resetProfile() -> Result<Void, Error> {
        do {
            try persistence.save(UserProfileArchive(profile: .empty, preferences: preferences))
            profile = .empty
            persistenceIssue = nil
            return .success(())
        } catch {
            persistenceIssue = "The profile could not be reset."
            return .failure(error)
        }
    }
}

private extension String {
    var nilIfBlank: String? { isEmpty ? nil : self }
}
