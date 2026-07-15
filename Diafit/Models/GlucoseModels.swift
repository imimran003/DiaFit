import Foundation

enum GlucoseUnit: String, Codable, CaseIterable, Hashable, Sendable {
    case milligramsPerDeciliter = "mg/dL"
    case millimolesPerLiter = "mmol/L"

    var shortName: String { rawValue }

    var spokenName: String {
        switch self {
        case .milligramsPerDeciliter: return "milligrams per deciliter"
        case .millimolesPerLiter: return "millimoles per liter"
        }
    }

    func normalizedMgPerDl(from value: Decimal) -> Decimal {
        switch self {
        case .milligramsPerDeciliter: return value
        case .millimolesPerLiter: return value * Decimal(18)
        }
    }

    func displayValue(from normalizedMgPerDl: Decimal) -> Decimal {
        switch self {
        case .milligramsPerDeciliter: return normalizedMgPerDl
        case .millimolesPerLiter: return normalizedMgPerDl / Decimal(18)
        }
    }

    func formatted(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value)
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = self == .millimolesPerLiter ? 1 : 0
        formatter.maximumFractionDigits = self == .millimolesPerLiter ? 1 : 0
        return formatter.string(from: number) ?? number.stringValue
    }
}

enum GlucoseReadingType: String, Codable, CaseIterable, Hashable, Sendable {
    case fasting
    case postMeal
    case preMeal
    case bedtime
    case other

    var displayName: String {
        switch self {
        case .fasting: return "Fasting"
        case .postMeal: return "Post-meal"
        case .preMeal: return "Before meal"
        case .bedtime: return "Bedtime"
        case .other: return "Other"
        }
    }

    var compactName: String {
        switch self {
        case .fasting: return "FBS"
        case .postMeal: return "Post-meal"
        case .preMeal: return "Before meal"
        case .bedtime: return "Bedtime"
        case .other: return "Other"
        }
    }
}

enum GlucoseReadingSource: String, Codable, CaseIterable, Hashable, Sendable {
    case manual
    case imported
    case healthKit
}

struct GlucoseReading: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var value: Decimal
    var unit: GlucoseUnit
    var normalizedMgPerDl: Decimal
    var type: GlucoseReadingType
    var measuredAt: Date
    var mealId: UUID?
    var minutesAfterMeal: Int?
    var fastingDurationMinutes: Int?
    var note: String?
    var source: GlucoseReadingSource
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        value: Decimal,
        unit: GlucoseUnit,
        type: GlucoseReadingType,
        measuredAt: Date = .now,
        mealId: UUID? = nil,
        minutesAfterMeal: Int? = nil,
        fastingDurationMinutes: Int? = nil,
        note: String? = nil,
        source: GlucoseReadingSource = .manual,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.value = value
        self.unit = unit
        self.normalizedMgPerDl = unit.normalizedMgPerDl(from: value)
        self.type = type
        self.measuredAt = measuredAt
        self.mealId = mealId
        self.minutesAfterMeal = minutesAfterMeal
        self.fastingDurationMinutes = fastingDurationMinutes
        self.note = note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var formattedValue: String { unit.formatted(value) }

    func displayed(in preferredUnit: GlucoseUnit) -> String {
        preferredUnit.formatted(preferredUnit.displayValue(from: normalizedMgPerDl))
    }

    var accessibilityValue: String {
        "(unit.formatted(value)) (unit.spokenName)"
    }
}

struct GlucoseDraft: Codable, Hashable, Sendable {
    var value: Decimal
    var unit: GlucoseUnit?
    var type: GlucoseReadingType
    var measuredAt: Date
    var mealReference: String?
    var minutesAfterMeal: Int?
    var confidence: Double
    var missingInformation: [String]

    var requiresConfirmation: Bool {
        unit == nil || !missingInformation.isEmpty || confidence < 0.8
    }
}

extension GlucoseDraft: Identifiable {
    var id: String { "\(type.rawValue)-\(value)-\(measuredAt.timeIntervalSince1970)" }
}

extension String {
    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
