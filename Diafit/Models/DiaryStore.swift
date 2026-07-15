import Foundation
import Combine

final class DiaryStore: ObservableObject {
    @Published private(set) var days: [Day]
    @Published private(set) var persistenceIssue: String?
    private let persistence: any DiaryPersisting
    private var canPersist: Bool

    init(days: [Day]) {
        self.days = days
        persistence = TransientDiaryPersistence()
        canPersist = true
    }

    init(seedDays: [Day], persistence: any DiaryPersisting) {
        self.persistence = persistence
        canPersist = true
        do {
            if let archive = try persistence.load() {
                days = archive.days
                persistenceIssue = nil
            } else {
                days = seedDays
                try persistence.save(DiaryArchive(days: seedDays))
                persistenceIssue = nil
            }
        } catch {
            // Never overwrite an unreadable archive. The seed remains usable,
            // while the visible issue prevents the app claiming changes are
            // durable until storage is repaired.
            days = seedDays
            canPersist = false
            persistenceIssue = Self.userMessage(for: error, operation: "load")
        }
    }

    func day(id: Day.ID) -> Day? {
        days.first { $0.id == id }
    }

    func append(_ item: ThreadItem, to dayID: Day.ID) {
        guard let index = days.firstIndex(where: { $0.id == dayID }) else { return }
        transact { $0[index].messages.append(item) }
    }

    func update(_ meal: Meal, in dayID: Day.ID) {
        guard let dayIndex = days.firstIndex(where: { $0.id == dayID }),
              let messageIndex = days[dayIndex].messages.firstIndex(where: { item in
                  if case .meal(let existing) = item.kind { return existing.id == meal.id }
                  return false
              }) else { return }
        transact { $0[dayIndex].messages[messageIndex].kind = .meal(meal) }
    }

    func removeMeal(id: Meal.ID, from dayID: Day.ID) {
        guard let dayIndex = days.firstIndex(where: { $0.id == dayID }) else { return }
        transact { days in
            days[dayIndex].messages.removeAll { item in
                if case .meal(let meal) = item.kind { return meal.id == id }
                return false
            }
        }
    }

    func update(_ draft: MealAnalysisDraft, for itemID: ThreadItem.ID, in dayID: Day.ID) {
        guard let dayIndex = days.firstIndex(where: { $0.id == dayID }),
              let messageIndex = days[dayIndex].messages.firstIndex(where: { $0.id == itemID }) else { return }
        transact { $0[dayIndex].messages[messageIndex].kind = .mealAnalysis(draft) }
    }

    func replace(itemID: ThreadItem.ID, with kind: ThreadItem.Kind, in dayID: Day.ID) {
        guard let dayIndex = days.firstIndex(where: { $0.id == dayID }),
              let messageIndex = days[dayIndex].messages.firstIndex(where: { $0.id == itemID }) else { return }
        transact { $0[dayIndex].messages[messageIndex].kind = kind }
    }

    func remove(itemID: ThreadItem.ID, from dayID: Day.ID) {
        guard let dayIndex = days.firstIndex(where: { $0.id == dayID }) else { return }
        transact { $0[dayIndex].messages.removeAll { $0.id == itemID } }
    }

    func retryPersistence() {
        do {
            try persistence.save(DiaryArchive(days: days))
            canPersist = true
            persistenceIssue = nil
        } catch {
            persistenceIssue = Self.userMessage(for: error, operation: "save")
        }
    }

    private func transact(_ mutation: (inout [Day]) -> Void) {
        guard canPersist else { return }
        var candidate = days
        mutation(&candidate)
        guard candidate != days else { return }
        do {
            try persistence.save(DiaryArchive(days: candidate))
            days = candidate
            persistenceIssue = nil
        } catch {
            persistenceIssue = Self.userMessage(for: error, operation: "save")
        }
    }

    private static func userMessage(for error: Error, operation: String) -> String {
        if operation == "load" {
            return "Your saved diary could not be opened. The original data was left untouched."
        }
        return "This change could not be saved on this device. Check available storage, then retry."
    }

    static let preview = DiaryStore(days: SampleDiary.days)
}

enum SampleDiary {
    private static let calendar = Calendar.current

    static var days: [Day] {
        [
            makeDay(offset: -2, messages: [
                .agent("A lighter day, with a lovely long lunch. I kept the meal estimates tidy for you.", ["Reviewed diary"]),
                .meal("Garden lentil bowl", "lentils, fennel, herbs", "Lunch", 612, 53, 25, 18, .bowl),
                .agent("That lentil bowl was beautifully balanced. I saved it as a pattern worth repeating.", ["Pattern saved"])
            ]),
            makeDay(offset: -1, messages: [
                .agent("Good morning, Imran. Yesterday’s afternoon was steady. Want to keep lunch similarly calm today?", ["Checked yesterday"]),
                .meal("Soft eggs & rye", "rye toast, eggs, tomato", "Breakfast", 382, 27, 23, 17, .toast),
                .checkpoint(112, "Before lunch", "A comfortable pre-lunch check-in."),
                .agent("Your usual breakfast is in. The rye keeps this one more gradual than white toast.", ["Used saved meal", "Nutrition checked"])
            ]),
            makeDay(offset: 0, messages: [
                .agent("Hi Imran. Let’s make today feel easy. Tell me what you eat in your own words—I’ll take care of the details.", ["Ready when you are"]),
                .meal("Yogurt, berries & seeds", "Greek yogurt, blueberries, chia", "Breakfast", 318, 24, 24, 13, .berry),
                .agent("A bright, protein-forward start. I counted the berries and chia; the rest came from your usual bowl.", ["Nutrition checked", "Used history"]),
                .meal("Miso salmon plate", "salmon, brown rice, greens", "Lunch", 548, 49, 37, 21, .green),
                .checkpoint(124, "90 min after lunch", "Within the range you chose for yourself."),
                .agent("Lunch is logged. There’s still room for a generous dinner—no need to micromanage it.", ["Day totals updated"])
            ])
        ]
    }

    private static func makeDay(offset: Int, messages: [ThreadItem]) -> Day {
        let date = calendar.date(byAdding: .day, value: offset, to: .now)!
        return Day(id: UUID(), date: date, messages: messages, energyGoal: 2_100, carbohydrateGoal: 180)
    }
}

private extension ThreadItem {
    static func agent(_ text: String, _ tools: [String]) -> ThreadItem {
        ThreadItem(id: UUID(), kind: .agent(text: text, tools: tools))
    }

    static func meal(
        _ title: String, _ subtitle: String, _ type: String,
        _ energy: Int, _ carbs: Int, _ protein: Int, _ fat: Int, _ artwork: Meal.Artwork
    ) -> ThreadItem {
        ThreadItem(id: UUID(), kind: .meal(Meal(
            id: UUID(), title: title, subtitle: subtitle, mealType: type, time: .now,
            energy: energy, carbs: carbs, protein: protein, fat: fat,
            artwork: artwork, confidence: .estimated
        )))
    }

    static func checkpoint(_ value: Int, _ label: String, _ note: String) -> ThreadItem {
        ThreadItem(id: UUID(), kind: .checkpoint(GlucoseCheckpoint(id: UUID(), value: value, unit: "mg/dL", label: label, note: note)))
    }
}
