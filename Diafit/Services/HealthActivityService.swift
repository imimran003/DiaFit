import Foundation
import HealthKit

struct HealthActivitySummary: Equatable, Sendable {
    let dayStart: Date
    let steps: Int?
    let walkingRunningKilometres: Double?
    let activeEnergyKilocalories: Double?
    let restingEnergyKilocalories: Double?
    let fetchedAt: Date

    var totalEnergyBurnedKilocalories: Double? {
        guard let activeEnergyKilocalories, let restingEnergyKilocalories else { return nil }
        return activeEnergyKilocalories + restingEnergyKilocalories
    }

    var hasAnyData: Bool {
        steps != nil
            || walkingRunningKilometres != nil
            || activeEnergyKilocalories != nil
            || restingEnergyKilocalories != nil
    }
}

struct DailyEnergyBalance: Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case deficit
        case surplus
        case balanced

        var displayName: String {
            switch self {
            case .deficit: return "Deficit"
            case .surplus: return "Surplus"
            case .balanced: return "Balanced"
            }
        }
    }

    let intakeKilocalories: Int
    let burnedKilocalories: Int
    let differenceKilocalories: Int
    let kind: Kind

    static func calculate(intakeKilocalories: Int, burnedKilocalories: Double?) -> DailyEnergyBalance? {
        guard let burnedKilocalories, burnedKilocalories.isFinite, burnedKilocalories >= 0 else { return nil }
        let burned = Int(burnedKilocalories.rounded())
        let difference = intakeKilocalories - burned
        return DailyEnergyBalance(
            intakeKilocalories: intakeKilocalories,
            burnedKilocalories: burned,
            differenceKilocalories: abs(difference),
            kind: difference < 0 ? .deficit : (difference > 0 ? .surplus : .balanced)
        )
    }
}

enum HealthActivityError: LocalizedError, Equatable {
    case unavailable
    case requiredTypeUnavailable
    case invalidDayRange

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Apple Health is not available on this device."
        case .requiredTypeUnavailable:
            return "The requested Apple Health activity type is unavailable."
        case .invalidDayRange:
            return "This day could not be read from Apple Health."
        }
    }
}

protocol HealthActivityProviding: Sendable {
    var isAvailable: Bool { get }
    var hasRequestedAccess: Bool { get }
    func requestAccess() async throws
    func summary(for date: Date, calendar: Calendar) async throws -> HealthActivitySummary
}

protocol HealthConnectionPreferenceStoring: Sendable {
    var hasRequestedAccess: Bool { get }
    func markAccessRequested()
}

struct UserDefaultsHealthConnectionPreferenceStore: HealthConnectionPreferenceStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = "diafit.health.requestedAccess"
    ) {
        self.defaults = defaults
        self.key = key
    }

    var hasRequestedAccess: Bool { defaults.bool(forKey: key) }

    func markAccessRequested() {
        defaults.set(true, forKey: key)
    }
}

final class HealthKitActivityService: HealthActivityProviding, @unchecked Sendable {
    private let healthStore: HKHealthStore
    private let preferenceStore: any HealthConnectionPreferenceStoring

    init(
        healthStore: HKHealthStore = HKHealthStore(),
        preferenceStore: any HealthConnectionPreferenceStoring = UserDefaultsHealthConnectionPreferenceStore()
    ) {
        self.healthStore = healthStore
        self.preferenceStore = preferenceStore
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
    var hasRequestedAccess: Bool { preferenceStore.hasRequestedAccess }

    func requestAccess() async throws {
        guard isAvailable else { throw HealthActivityError.unavailable }
        let readTypes = try requiredReadTypes()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.requestAuthorization(toShare: [], read: readTypes) { [preferenceStore] success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    preferenceStore.markAccessRequested()
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HealthActivityError.unavailable)
                }
            }
        }
    }

    func summary(for date: Date, calendar: Calendar = .autoupdatingCurrent) async throws -> HealthActivitySummary {
        guard isAvailable else { throw HealthActivityError.unavailable }
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start), end > start else {
            throw HealthActivityError.invalidDayRange
        }

        async let steps = cumulativeSum(
            identifier: .stepCount,
            unit: .count(),
            start: start,
            end: end
        )
        async let distance = cumulativeSum(
            identifier: .distanceWalkingRunning,
            unit: .meterUnit(with: .kilo),
            start: start,
            end: end
        )
        async let activeEnergy = cumulativeSum(
            identifier: .activeEnergyBurned,
            unit: .kilocalorie(),
            start: start,
            end: end
        )
        async let restingEnergy = cumulativeSum(
            identifier: .basalEnergyBurned,
            unit: .kilocalorie(),
            start: start,
            end: end
        )

        let (stepValue, distanceValue, activeEnergyValue, restingEnergyValue) = try await (
            steps,
            distance,
            activeEnergy,
            restingEnergy
        )
        return HealthActivitySummary(
            dayStart: start,
            steps: stepValue.map { Int($0.rounded()) },
            walkingRunningKilometres: distanceValue,
            activeEnergyKilocalories: activeEnergyValue,
            restingEnergyKilocalories: restingEnergyValue,
            fetchedAt: .now
        )
    }

    private func requiredReadTypes() throws -> Set<HKObjectType> {
        let identifiers: [HKQuantityTypeIdentifier] = [
            .stepCount,
            .distanceWalkingRunning,
            .activeEnergyBurned,
            .basalEnergyBurned
        ]
        let types = identifiers.compactMap(HKObjectType.quantityType(forIdentifier:))
        guard types.count == identifiers.count else { throw HealthActivityError.requiredTypeUnavailable }
        return Set(types)
    }

    private func cumulativeSum(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async throws -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            throw HealthActivityError.requiredTypeUnavailable
        }
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: [.strictStartDate]
        )
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: [.cumulativeSum]
            ) { _, result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: result?.sumQuantity()?.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }
}

#if DEBUG
/// Deterministic test-only adapter selected by explicit UI-test launch
/// arguments. It is excluded from release builds.
struct FixtureHealthActivityService: HealthActivityProviding, Sendable {
    let isAvailable: Bool
    let hasRequestedAccess: Bool
    let fixture: HealthActivitySummary?

    func requestAccess() async throws {}

    func summary(for date: Date, calendar: Calendar) async throws -> HealthActivitySummary {
        if let fixture {
            return HealthActivitySummary(
                dayStart: calendar.startOfDay(for: date),
                steps: fixture.steps,
                walkingRunningKilometres: fixture.walkingRunningKilometres,
                activeEnergyKilocalories: fixture.activeEnergyKilocalories,
                restingEnergyKilocalories: fixture.restingEnergyKilocalories,
                fetchedAt: fixture.fetchedAt
            )
        }
        throw HealthActivityError.unavailable
    }

    static let disconnected = FixtureHealthActivityService(
        isAvailable: true,
        hasRequestedAccess: false,
        fixture: nil
    )

    static let connected = FixtureHealthActivityService(
        isAvailable: true,
        hasRequestedAccess: true,
        fixture: HealthActivitySummary(
            dayStart: .distantPast,
            steps: 8_420,
            walkingRunningKilometres: 6.2,
            activeEnergyKilocalories: 480,
            restingEnergyKilocalories: 1_520,
            fetchedAt: .distantPast
        )
    )
}
#endif
