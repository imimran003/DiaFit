import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// A portable, privacy-conscious snapshot. Internal database identifiers,
/// binary photos, cache keys, and provider URLs are intentionally omitted.
/// The user can export this file to review or move the meaningful diary data.
struct DiafitExportPayload: Codable, Equatable, Sendable {
    static let currentVersion = "1"

    let formatVersion: String
    let exportedAt: Date
    let profile: ProfileExport
    let preferences: PreferencesExport
    let days: [DayExport]
    let savedFoodMemories: [SavedFoodMemoryExport]
    let packagedFoods: [PackagedFoodExport]

    init(
        profile: UserProfile,
        preferences: UserPreferences,
        days: [Day],
        savedFoodMemories: [UserFoodMemory] = [],
        packagedFoods: [PackagedFoodRecord] = []
    ) {
        formatVersion = Self.currentVersion
        exportedAt = .now
        self.profile = ProfileExport(profile: profile)
        self.preferences = PreferencesExport(preferences: preferences)
        self.days = days
            .sorted { $0.date < $1.date }
            .map(DayExport.init)
        self.savedFoodMemories = savedFoodMemories
            .sorted { $0.lastConfirmedAt < $1.lastConfirmedAt }
            .map { SavedFoodMemoryExport(memory: $0) }
        self.packagedFoods = packagedFoods
            .sorted { $0.productName.localizedCaseInsensitiveCompare($1.productName) == .orderedAscending }
            .map { PackagedFoodExport(record: $0) }
    }

    struct ProfileExport: Codable, Equatable, Sendable {
        let preferredName: String
        let dateOfBirth: Date?
        let sex: ProfileSex
        let genderIdentity: String?
        let heightCentimeters: Double?
        let weightKilograms: Double?
        let diabetesContext: DiabetesContext
        let activityLevel: ProfileActivityLevel
        let dietaryPattern: DietaryPattern
        let allergies: [String]
        let calorieGoal: Int?
        let carbohydrateGoalGrams: Int?
        let proteinGoalGrams: Int?
        let stepGoal: Int?
        let profilePhotoPresent: Bool

        init(profile: UserProfile) {
            preferredName = profile.preferredName
            dateOfBirth = profile.dateOfBirth
            sex = profile.sex
            genderIdentity = profile.genderIdentity
            heightCentimeters = profile.heightCentimeters
            weightKilograms = profile.weightKilograms
            diabetesContext = profile.diabetesContext
            activityLevel = profile.activityLevel
            dietaryPattern = profile.dietaryPattern
            allergies = profile.allergies
            calorieGoal = profile.calorieGoal
            carbohydrateGoalGrams = profile.carbohydrateGoalGrams
            proteinGoalGrams = profile.proteinGoalGrams
            stepGoal = profile.stepGoal
            profilePhotoPresent = profile.avatarJPEGData != nil
        }
    }

    struct PreferencesExport: Codable, Equatable, Sendable {
        let measurementSystem: MeasurementSystem
        let preferredGlucoseUnit: GlucoseUnit
        let hapticsEnabled: Bool

        init(preferences: UserPreferences) {
            measurementSystem = preferences.measurementSystem
            preferredGlucoseUnit = preferences.preferredGlucoseUnit
            hapticsEnabled = preferences.hapticsEnabled
        }
    }

    struct DayExport: Codable, Equatable, Sendable {
        let date: Date
        let meals: [MealExport]
        let glucoseReadings: [GlucoseExport]

        init(day: Day) {
            date = day.date
            meals = day.meals.sorted { $0.time < $1.time }.map { MealExport(meal: $0) }
            glucoseReadings = day.glucoseReadings.map { GlucoseExport(reading: $0) }
        }
    }

    struct MealExport: Codable, Equatable, Sendable {
        let name: String
        let details: String
        let mealType: String
        let time: Date
        let calories: Int
        let carbohydratesGrams: Int
        let proteinGrams: Int
        let fatGrams: Int
        let confidence: Meal.Confidence

        init(meal: Meal) {
            name = meal.title
            details = meal.subtitle
            mealType = meal.period.displayName
            time = meal.time
            calories = meal.energy
            carbohydratesGrams = meal.carbs
            proteinGrams = meal.protein
            fatGrams = meal.fat
            confidence = meal.confidence
        }
    }

    struct GlucoseExport: Codable, Equatable, Sendable {
        let measuredAt: Date
        let type: GlucoseReadingType
        let value: Decimal
        let unit: GlucoseUnit
        let normalizedMgPerDl: Decimal
        let minutesAfterMeal: Int?
        let fastingDurationMinutes: Int?
        let note: String?
        let source: GlucoseReadingSource

        init(reading: GlucoseReading) {
            measuredAt = reading.measuredAt
            type = reading.type
            value = reading.value
            unit = reading.unit
            normalizedMgPerDl = reading.normalizedMgPerDl
            minutesAfterMeal = reading.minutesAfterMeal
            fastingDurationMinutes = reading.fastingDurationMinutes
            note = reading.note
            source = reading.source
        }
    }

    struct SavedFoodMemoryExport: Codable, Equatable, Sendable {
        let alias: String
        let canonicalFoodID: String
        let servingGrams: Double?
        let servingUnit: String?
        let preparation: String?
        let productID: String?
        let lastConfirmedAt: Date

        init(memory: UserFoodMemory) {
            alias = memory.alias
            canonicalFoodID = memory.canonicalFoodID
            servingGrams = memory.servingGrams
            servingUnit = memory.servingUnit
            preparation = memory.preparation
            productID = memory.productID
            lastConfirmedAt = memory.lastConfirmedAt
        }
    }

    struct PackagedFoodExport: Codable, Equatable, Sendable {
        let brand: String
        let productName: String
        let barcode: String?
        let flavour: String?
        let gramsPerScoop: Double?
        let servingGrams: Double
        let nutritionPerServing: NutritionValues
        let nutritionPer100Grams: NutritionValues?
        let source: String
        let sourceVersion: String?
        let userConfirmed: Bool

        init(record: PackagedFoodRecord) {
            brand = record.brand
            productName = record.productName
            barcode = record.barcode
            flavour = record.flavour
            gramsPerScoop = record.gramsPerScoop
            servingGrams = record.servingGrams
            nutritionPerServing = record.nutritionPerServing
            nutritionPer100Grams = record.nutritionPer100Grams
            source = record.source
            sourceVersion = record.sourceVersion
            userConfirmed = record.userConfirmed
        }
    }
}

/// A JSON `FileDocument` keeps export in the system share/save sheet instead
/// of silently writing a copy into an unknown location.
struct DiafitExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    static var writableContentTypes: [UTType] { [.json] }

    let data: Data

    init(
        profile: UserProfile,
        preferences: UserPreferences,
        days: [Day],
        savedFoodMemories: [UserFoodMemory] = [],
        packagedFoods: [PackagedFoodRecord] = []
    ) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        data = try encoder.encode(DiafitExportPayload(
            profile: profile,
            preferences: preferences,
            days: days,
            savedFoodMemories: savedFoodMemories,
            packagedFoods: packagedFoods
        ))
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
