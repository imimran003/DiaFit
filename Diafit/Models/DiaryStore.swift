import Foundation
import Combine

final class DiaryStore: ObservableObject {
    @Published var days: [Day]

    init(days: [Day]) {
        self.days = days
    }

    func day(id: Day.ID) -> Day? {
        days.first { $0.id == id }
    }

    func append(_ item: ThreadItem, to dayID: Day.ID) {
        guard let index = days.firstIndex(where: { $0.id == dayID }) else { return }
        days[index].messages.append(item)
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
