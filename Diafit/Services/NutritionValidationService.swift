import Foundation

/// A provider result is never allowed to become a diary total merely because it
/// has a numeric value. This guard preserves the raw proposal for inspection,
/// but exposes values to the UI only when they are structurally and nutritionally
/// plausible for the identified food and serving.
struct NutritionValidationReport: Codable, Hashable, Sendable {
    enum Status: String, Codable, Hashable, Sendable {
        case approved
        case requiresClarification
    }

    struct Issue: Codable, Hashable, Sendable, Identifiable {
        enum Code: String, Codable, Hashable, Sendable {
            case invalidNumber
            case unreasonableQuantity
            case unreasonableWeight
            case energyMismatch
            case implausibleBeverageEnergy
            case implausibleEggEnergy
            case implausibleSupplementServing
            case unavailableNutrition
        }

        enum Severity: String, Codable, Hashable, Sendable {
            case warning
            case blocking
        }

        let code: Code
        let severity: Severity
        let message: String

        var id: String { code.rawValue + message }
    }

    var status: Status
    /// The provider or catalog value is retained for transparent diagnostics;
    /// `safeValues` is what may be shown in final totals and persisted meals.
    var rawValues: NutritionValues
    var safeValues: NutritionValues?
    var issues: [Issue]

    var isApproved: Bool { status == .approved }
}

protocol NutritionValidationService: Sendable {
    func validate(
        rawValues: NutritionValues,
        canonicalFoodID: String?,
        quantity: Double?,
        servingUnit: ServingUnit?,
        estimatedWeightGrams: Double?
    ) -> NutritionValidationReport
}

struct DefaultNutritionValidationService: NutritionValidationService, Sendable {
    func validate(
        rawValues: NutritionValues,
        canonicalFoodID: String? = nil,
        quantity: Double? = nil,
        servingUnit: ServingUnit? = nil,
        estimatedWeightGrams: Double? = nil
    ) -> NutritionValidationReport {
        var issues: [NutritionValidationReport.Issue] = []

        let nutrients: [(String, Double?)] = [
            ("Calories", rawValues.caloriesKcal),
            ("Protein", rawValues.proteinGrams),
            ("Carbohydrate", rawValues.carbohydrateGrams),
            ("Available carbohydrate", rawValues.availableCarbohydrateGrams),
            ("Fat", rawValues.fatGrams),
            ("Saturated fat", rawValues.saturatedFatGrams),
            ("Fibre", rawValues.fibreGrams),
            ("Total sugar", rawValues.totalSugarGrams),
            ("Added sugar", rawValues.addedSugarGrams),
            ("Sodium", rawValues.sodiumMilligrams),
            ("Cholesterol", rawValues.cholesterolMilligrams)
        ]

        for (name, value) in nutrients {
            guard let value else { continue }
            if !value.isFinite || value < 0 {
                issues.append(.init(
                    code: .invalidNumber,
                    severity: .blocking,
                    message: "\(name) must be a finite, non-negative value."
                ))
            }
        }

        let maximumQuantity = servingUnit == .millilitres ? 20_000.0 : 20.0
        if let quantity, (!quantity.isFinite || quantity < 0.1 || quantity > maximumQuantity) {
            issues.append(.init(
                code: .unreasonableQuantity,
                severity: .blocking,
                message: servingUnit == .millilitres
                    ? "This volume is outside the supported 0.1–20,000 mL range."
                    : "This serving quantity is outside the supported 0.1–20 range."
            ))
        }

        if let estimatedWeightGrams, (!estimatedWeightGrams.isFinite || estimatedWeightGrams < 1 || estimatedWeightGrams > 2_000) {
            issues.append(.init(
                code: .unreasonableWeight,
                severity: .blocking,
                message: "The estimated serving weight needs review before it can be logged."
            ))
        }

        if rawValues.isEmpty {
            issues.append(.init(
                code: .unavailableNutrition,
                severity: .blocking,
                message: "Nutrition is unavailable for this preparation. Choose a variation or add the serving details."
            ))
        }

        if let calories = rawValues.caloriesKcal,
           let protein = rawValues.proteinGrams,
           let carbohydrate = rawValues.carbohydrateGrams,
           let fat = rawValues.fatGrams {
            let expectedEnergy = protein * 4 + carbohydrate * 4 + fat * 9
            let variance = abs(calories - expectedEnergy)
            let tolerance = max(25, expectedEnergy * 0.35)
            if variance > tolerance {
                let severity: NutritionValidationReport.Issue.Severity = variance > max(100, expectedEnergy * 0.75) ? .blocking : .warning
                issues.append(.init(
                    code: .energyMismatch,
                    severity: severity,
                    message: "Reported energy does not reasonably match the listed protein, carbohydrate, and fat."
                ))
            }
        }

        if ["black-coffee", "plain-tea", "green-tea"].contains(canonicalFoodID),
           let calories = rawValues.caloriesKcal {
            let servings = max(quantity ?? 1, 1)
            if calories > max(20, servings * 6) {
                issues.append(.init(
                    code: .implausibleBeverageEnergy,
                    severity: .blocking,
                    message: "A plain unsweetened beverage cannot use this calorie estimate. Check milk, sugar, cream, and serving details."
                ))
            }
        }

        let singleEggRecords: Set<String> = [
            "whole-egg", "boiled-egg", "soft-boiled-egg", "poached-egg",
            "fried-egg", "scrambled-egg", "egg-white", "egg-yolk"
        ]
        if let canonicalFoodID,
           singleEggRecords.contains(canonicalFoodID),
           let calories = rawValues.caloriesKcal {
            let count = max(quantity ?? 1, 1)
            let perEgg = calories / count
            let isBoiled = canonicalFoodID.contains("boiled")
            let range: ClosedRange<Double>
            if canonicalFoodID.contains("white") {
                range = 10...40
            } else if canonicalFoodID.contains("yolk") {
                range = 30...85
            } else {
                range = isBoiled ? 50...110 : 35...160
            }
            if !range.contains(perEgg) {
                issues.append(.init(
                    code: .implausibleEggEnergy,
                    severity: .blocking,
                    message: "This egg estimate does not scale plausibly for the selected preparation and quantity."
                ))
            }
        }

        if let canonicalFoodID,
           canonicalFoodID.contains("whey"),
           let protein = rawValues.proteinGrams,
           servingUnit == .scoop {
            let scoops = max(quantity ?? 1, 1)
            let proteinPerScoop = protein / scoops
            // Generic whey usually supplies roughly 15–35 g protein per scoop.
            // Values outside this range often reveal scoop/gram confusion.
            if proteinPerScoop < 12 || proteinPerScoop > 40 {
                issues.append(.init(
                    code: .implausibleSupplementServing,
                    severity: .blocking,
                    message: "Protein per scoop is implausible for whey. Check scoop count and the product label."
                ))
            }
        }

        let blocking = issues.contains { $0.severity == .blocking }
        return NutritionValidationReport(
            status: blocking ? .requiresClarification : .approved,
            rawValues: rawValues,
            safeValues: blocking ? nil : rawValues,
            issues: issues
        )
    }
}

enum FoodLoggingDiagnostics {
    /// Development-only diagnostics intentionally omit image bytes, tokens, and
    /// raw meal text. The input fingerprint makes a trace correlatable without
    /// turning debug logs into another source of sensitive diary data.
    static func record(_ stage: String, fields: [String: String]) {
        #if DEBUG
        let payload = fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        print("[DiafitFoodAudit] \(stage) \(payload)")
        #endif
    }

    static func fingerprint(_ value: String) -> String {
        let scalars = value.lowercased().unicodeScalars.map { UInt64($0.value) }
        let hash = scalars.reduce(UInt64(5_381)) { ($0 &* 33) &+ $1 }
        return String(hash, radix: 16)
    }
}
