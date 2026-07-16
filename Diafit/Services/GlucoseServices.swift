import Foundation

struct GlucoseValidationResult: Equatable, Sendable {
    let isValid: Bool
    let requiresConfirmation: Bool
    let message: String?

    static let valid = GlucoseValidationResult(isValid: true, requiresConfirmation: false, message: nil)
}

protocol GlucoseValidationService: Sendable {
    func validate(value: Decimal, unit: GlucoseUnit, type: GlucoseReadingType, minutesAfterMeal: Int?) -> GlucoseValidationResult
}

struct DefaultGlucoseValidationService: GlucoseValidationService, Sendable {
    func validate(value: Decimal, unit: GlucoseUnit, type: GlucoseReadingType, minutesAfterMeal: Int? = nil) -> GlucoseValidationResult {
        guard value > 0 else {
            return GlucoseValidationResult(isValid: false, requiresConfirmation: false, message: "Enter a glucose value greater than zero.")
        }
        if let minutesAfterMeal, minutesAfterMeal < 0 {
            return GlucoseValidationResult(isValid: false, requiresConfirmation: false, message: "Time after meal cannot be negative.")
        }

        let mgPerDl = unit.normalizedMgPerDl(from: value)
        // This is a technical input guard, not a clinical threshold.
        if mgPerDl < 20 || mgPerDl > 1_000 {
            return GlucoseValidationResult(isValid: true, requiresConfirmation: true, message: "This value is unusual. Check the number and unit before saving.")
        }
        return .valid
    }
}

struct GlucoseReadingFactory: Sendable {
    let validation: any GlucoseValidationService

    init(validation: any GlucoseValidationService = DefaultGlucoseValidationService()) {
        self.validation = validation
    }

    func make(
        value: Decimal,
        unit: GlucoseUnit,
        type: GlucoseReadingType,
        measuredAt: Date,
        mealId: UUID? = nil,
        minutesAfterMeal: Int? = nil,
        fastingDurationMinutes: Int? = nil,
        note: String? = nil,
        existing: GlucoseReading? = nil
    ) -> Result<GlucoseReading, GlucoseEntryError> {
        let validation = validation.validate(value: value, unit: unit, type: type, minutesAfterMeal: minutesAfterMeal)
        guard validation.isValid else {
            return .failure(.invalidValue(validation.message ?? "Check the glucose value."))
        }
        let now = Date()
        let reading = GlucoseReading(
            id: existing?.id ?? UUID(),
            value: value,
            unit: unit,
            type: type,
            measuredAt: measuredAt,
            mealId: mealId,
            minutesAfterMeal: minutesAfterMeal,
            fastingDurationMinutes: fastingDurationMinutes,
            note: note,
            source: existing?.source ?? .manual,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )
        return .success(reading)
    }
}

enum GlucoseEntryError: LocalizedError, Equatable {
    case invalidValue(String)
    case missingValue
    case invalidDecimal
    case relatedMealMissing
    case persistenceFailed

    var errorDescription: String? {
        switch self {
        case .invalidValue(let message): return message
        case .missingValue: return "Enter a glucose value before saving."
        case .invalidDecimal: return "Use a number such as 96 or 5.7."
        case .relatedMealMissing: return "That meal is no longer available. Save without an association or choose another meal."
        case .persistenceFailed: return "This reading could not be saved. Your entry is still available to retry."
        }
    }
}

struct ParsedGlucoseNote: Sendable {
    let draft: GlucoseDraft
}

struct GlucoseNaturalLanguageParser: Sendable {
    func parse(_ text: String, now: Date = .now) -> GlucoseDraft? {
        let normalized = text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        guard DefaultConversationInputIntentClassifier().classify(normalized).intent == .glucose else { return nil }
        guard let value = extractValue(from: normalized) else { return nil }

        let unit: GlucoseUnit?
        if normalized.range(of: #"\bmmol\s*/?\s*l\b"#, options: .regularExpression) != nil { unit = .millimolesPerLiter }
        else if normalized.range(of: #"\b(?:mg\s*/?\s*dl|mgdl)\b"#, options: .regularExpression) != nil { unit = .milligramsPerDeciliter }
        else { unit = nil }

        let type: GlucoseReadingType
        if normalized.contains("fbs") || normalized.contains("fasting") || normalized.contains("morning sugar") || normalized.contains("morning blood") {
            type = .fasting
        } else if normalized.contains("ppbs") || normalized.contains("post-meal") || normalized.contains("post meal") || normalized.contains("postmeal") || normalized.contains("postprandial") || normalized.contains("after lunch") || normalized.contains("after dinner") || normalized.contains("after breakfast") || normalized.contains("after meal") {
            type = .postMeal
        } else if normalized.contains("before meal") || normalized.contains("pre-meal") || normalized.contains("pre meal") || normalized.contains("premeal") {
            type = .preMeal
        } else if normalized.contains("bedtime") || normalized.contains("before bed") {
            type = .bedtime
        } else {
            type = .other
        }

        let minutes = extractMinutesAfterMeal(from: normalized)
        var missing: [String] = []
        if unit == nil { missing.append("unit") }
        if type == .postMeal && minutes == nil { missing.append("time after meal") }
        let mealReference = ["breakfast", "lunch", "dinner", "snack"].first { normalized.contains($0) }
        let confidence = (unit == nil ? 0.7 : 0.9) - (type == .other ? 0.15 : 0)

        return GlucoseDraft(
            value: value,
            unit: unit,
            type: type,
            measuredAt: now,
            mealReference: mealReference,
            minutesAfterMeal: minutes,
            confidence: confidence,
            missingInformation: missing
        )
    }

    private func extractValue(from text: String) -> Decimal? {
        let value = #"([0-9]{1,4}(?:[\.,][0-9]{1,2})?)"#
        let marker = #"(?:fbs|ppbs|blood\s+(?:sugar|glucose)|glucose|(?:fasting|morning|post[-\s]?meal|postprandial|pre[-\s]?meal|bedtime)\s+(?:blood\s+)?sugar|sugar\s+after\s+(?:breakfast|lunch|dinner|meal))"#
        let unit = #"(?:mg\s*/?\s*dl|mgdl|mmol\s*/?\s*l)"#
        let patterns = [
            #"\#(marker).{0,64}?\b(?:was|is|at|of)\s*\#(value)"#,
            #"\#(marker)\s*(?:reading\s*)?[:=\-]?\s*\#(value)"#,
            #"\#(marker)\s+(?:reading\s+)?(?:after|before)\s+(?:breakfast|lunch|dinner|meal)\s*(?:was|is)?\s*\#(value)"#,
            #"\#(value)\s*\#(unit)\b"#,
            #"\#(value)\s+\#(marker)\b"#
        ]

        for pattern in patterns {
            if let parsed = capturedDecimal(in: text, pattern: pattern) { return parsed }
        }
        return nil
    }

    private func capturedDecimal(in text: String, pattern: String) -> Decimal? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let searchRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = expression.firstMatch(in: text, range: searchRange),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        let raw = String(text[range]).replacingOccurrences(of: ",", with: ".")
        return Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX"))
    }

    private func extractMinutesAfterMeal(from text: String) -> Int? {
        let patterns: [(String, Int)] = [
            (#"30[-\s]*(?:min|mins|minute|minutes)"#, 30),
            (#"(?:1|one)[-\s]*(?:hour|hr)"#, 60),
            (#"90[-\s]*(?:min|mins|minute|minutes)"#, 90),
            (#"(?:2|two)[-\s]*(?:hour|hr|hours)"#, 120),
            (#"(?:3|three)[-\s]*(?:hour|hr|hours)"#, 180)
        ]
        for (pattern, minutes) in patterns where text.range(of: pattern, options: .regularExpression) != nil {
            return minutes
        }
        return nil
    }
}

@MainActor
protocol GlucoseReadingRepository {
    func save(_ reading: GlucoseReading, to dayID: Day.ID, in store: DiaryStore) -> Result<Void, GlucoseEntryError>
    func update(_ reading: GlucoseReading, in dayID: Day.ID, store: DiaryStore) -> Result<Void, GlucoseEntryError>
    func delete(_ reading: GlucoseReading, from dayID: Day.ID, store: DiaryStore) -> Result<Void, GlucoseEntryError>
}

@MainActor
struct DiaryGlucoseReadingRepository: GlucoseReadingRepository {
    func save(_ reading: GlucoseReading, to dayID: Day.ID, in store: DiaryStore) -> Result<Void, GlucoseEntryError> {
        guard let day = store.day(id: dayID) else { return .failure(.persistenceFailed) }
        if let mealId = reading.mealId, !day.meals.contains(where: { $0.id == mealId }) {
            return .failure(.relatedMealMissing)
        }
        store.appendGlucoseReading(reading, to: dayID)
        return store.persistenceIssue == nil ? .success(()) : .failure(.persistenceFailed)
    }

    func update(_ reading: GlucoseReading, in dayID: Day.ID, store: DiaryStore) -> Result<Void, GlucoseEntryError> {
        guard let day = store.day(id: dayID), day.glucoseReadings.contains(where: { $0.id == reading.id }) else {
            return .failure(.persistenceFailed)
        }
        if let mealId = reading.mealId, !day.meals.contains(where: { $0.id == mealId }) {
            return .failure(.relatedMealMissing)
        }
        store.updateGlucoseReading(reading, in: dayID)
        return store.persistenceIssue == nil ? .success(()) : .failure(.persistenceFailed)
    }

    func delete(_ reading: GlucoseReading, from dayID: Day.ID, store: DiaryStore) -> Result<Void, GlucoseEntryError> {
        store.removeGlucoseReading(id: reading.id, from: dayID)
        return store.persistenceIssue == nil ? .success(()) : .failure(.persistenceFailed)
    }
}

struct GlucoseDaySummary: Hashable, Sendable {
    let count: Int
    let averageMgPerDl: Decimal?
    let minimumMgPerDl: Decimal?
    let maximumMgPerDl: Decimal?
}

struct GlucoseHistoryService: Sendable {
    func readings(in days: [Day], range: DateInterval? = nil, type: GlucoseReadingType? = nil, calendar: Calendar = .current) -> [GlucoseReading] {
        days.flatMap(\.glucoseReadings)
            .filter { reading in
                let matchesType = type == nil || reading.type == type
                let matchesRange = range == nil || range!.contains(reading.measuredAt)
                return matchesType && matchesRange
            }
            .sorted { $0.measuredAt < $1.measuredAt }
    }

    func summary(for readings: [GlucoseReading]) -> GlucoseDaySummary {
        guard !readings.isEmpty else { return GlucoseDaySummary(count: 0, averageMgPerDl: nil, minimumMgPerDl: nil, maximumMgPerDl: nil) }
        let values = readings.map(\.normalizedMgPerDl)
        let total = values.reduce(Decimal.zero, +)
        return GlucoseDaySummary(
            count: values.count,
            averageMgPerDl: total / Decimal(values.count),
            minimumMgPerDl: values.min(),
            maximumMgPerDl: values.max()
        )
    }

    func dateInterval(days: Int, now: Date = .now, calendar: Calendar = .current) -> DateInterval {
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now)) ?? now
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return DateInterval(start: start, end: end)
    }
}

struct GlucoseCSVExporter: Sendable {
    func csv(readings: [GlucoseReading], mealNames: [UUID: String] = [:]) -> String {
        var lines = ["date,time,reading_type,value,unit,normalized_mg_dl,minutes_after_meal,related_meal,note"]
        let formatter = ISO8601DateFormatter()
        for reading in readings.sorted(by: { $0.measuredAt < $1.measuredAt }) {
            let date = formatter.string(from: reading.measuredAt)
            let meal = reading.mealId.flatMap { mealNames[$0] } ?? ""
            let note = (reading.note ?? "").replacingOccurrences(of: "\"", with: "\"\"")
            let offset = reading.minutesAfterMeal.map(String.init) ?? ""
            let line = [date, date, reading.type.rawValue, "\(reading.value)", reading.unit.rawValue,
                        "\(reading.normalizedMgPerDl)", offset, meal, note]
                .map { "\"\($0)\"" }
                .joined(separator: ",")
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
}
