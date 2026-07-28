import Foundation
import UserNotifications

struct DailyNutritionReview: Equatable, Sendable {
    struct Observation: Identifiable, Equatable, Sendable {
        let id: String
        let title: String
        let detail: String
        let symbol: String
    }

    let title: String
    let overview: String
    let observations: [Observation]
    let closing: String
}

struct DailyNutritionReviewService: Sendable {
    func review(for day: Day, activity: HealthActivitySummary? = nil) -> DailyNutritionReview? {
        let meals = day.meals.sorted { $0.time < $1.time }
        guard !meals.isEmpty else { return nil }

        let periods = Set(meals.map(\.period))
        var observations: [DailyNutritionReview.Observation] = []

        let proteinMeals = meals.filter { $0.protein > 0 }
        if day.totalProtein > 0 {
            let distribution = proteinMeals.count >= 3
                ? "It was spread across \(proteinMeals.count) meals, rather than appearing in only one eating window."
                : "Most recorded protein came from \(proteinMeals.count) \(proteinMeals.count == 1 ? "meal" : "meals"); another protein-containing meal may create a more even pattern if that suits your plan."
            observations.append(.init(
                id: "protein",
                title: "Protein pattern",
                detail: "You logged \(day.totalProtein) g of protein. \(distribution)",
                symbol: "circle.grid.2x2"
            ))
        }

        if let highestCarbMeal = meals.max(by: { $0.carbs < $1.carbs }), highestCarbMeal.carbs > 0 {
            observations.append(.init(
                id: "carbohydrate",
                title: "Carbohydrate context",
                detail: "\(highestCarbMeal.period.displayName) was the largest recorded carbohydrate window at \(highestCarbMeal.carbs) g. You can compare that meal with your own post-meal glucose readings when available.",
                symbol: "chart.bar.xaxis"
            ))
        }

        let analysedMeals = meals.compactMap(\.analysis)
        let knownFibre = analysedMeals.compactMap(\.mealTotals.fibreGrams).reduce(0, +)
        let fibreIsComplete = analysedMeals.count == meals.count
            && analysedMeals.allSatisfy { $0.mealTotals.fibreGrams != nil }
        if knownFibre > 0 {
            observations.append(.init(
                id: "fibre",
                title: "Fibre recorded",
                detail: "Today’s \(fibreIsComplete ? "total" : "known amount") is \(knownFibre.formatted(.number.precision(.fractionLength(0...1)))) g. This is a record of the foods logged, not a claim about digestion or glucose response.",
                symbol: "leaf"
            ))
        }

        if let balance = DailyEnergyBalance.calculate(
            intakeKilocalories: day.totalEnergy,
            burnedKilocalories: activity?.totalEnergyBurnedKilocalories
        ) {
            let relationship: String
            switch balance.kind {
            case .deficit:
                relationship = "Recorded intake was \(balance.differenceKilocalories) kcal below Apple Health’s recorded burn."
            case .surplus:
                relationship = "Recorded intake was \(balance.differenceKilocalories) kcal above Apple Health’s recorded burn."
            case .balanced:
                relationship = "Recorded intake and Apple Health’s recorded burn were approximately equal."
            }
            observations.append(.init(
                id: "energy",
                title: "Energy context",
                detail: "\(relationship) Both intake and burn are estimates, so treat this as context rather than a target.",
                symbol: "scalemass"
            ))
        }

        if observations.isEmpty {
            observations.append(.init(
                id: "data",
                title: "A useful start",
                detail: "Your meals are saved, but some nutrition details are unavailable. Refine those meals for a more specific review.",
                symbol: "checkmark.circle"
            ))
        }

        return DailyNutritionReview(
            title: "Daily nutrition review",
            overview: "\(meals.count) \(meals.count == 1 ? "meal" : "meals") logged across \(periods.count) \(periods.count == 1 ? "meal period" : "meal periods").",
            observations: Array(observations.prefix(3)),
            closing: "Use this short review to notice patterns—not as a diagnosis or medication guide."
        )
    }
}

enum DailyReviewAvailability {
    static func isAvailable(
        for day: Date,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent,
        reviewHour: Int = 22
    ) -> Bool {
        let dayStart = calendar.startOfDay(for: day)
        let todayStart = calendar.startOfDay(for: now)
        if dayStart < todayStart { return true }
        guard dayStart == todayStart else { return false }
        return calendar.component(.hour, from: now) >= reviewHour
    }
}

protocol DailyReviewReminderScheduling: Sendable {
    func isEnabled() async -> Bool
    func enable(hour: Int) async throws -> Bool
}

final class LocalDailyReviewReminderScheduler: DailyReviewReminderScheduling, @unchecked Sendable {
    private let center: UNUserNotificationCenter
    private let identifier = "diafit.daily-nutrition-review"

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func isEnabled() async -> Bool {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return false
        }
        let pending = await center.pendingNotificationRequests()
        return pending.contains { $0.identifier == identifier }
    }

    func enable(hour: Int = 22) async throws -> Bool {
        let settings = await center.notificationSettings()
        let authorized: Bool
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            authorized = true
        case .notDetermined:
            authorized = try await center.requestAuthorization(options: [.alert, .sound])
        default:
            authorized = false
        }
        guard authorized else { return false }

        let content = UNMutableNotificationContent()
        content.title = "Your daily review is ready"
        content.body = "Open Diafit for a short review of today’s confirmed meals."
        content.sound = .default

        var components = DateComponents()
        components.hour = min(max(hour, 0), 23)
        components.minute = 0
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        )
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        try await center.add(request)
        return true
    }
}
