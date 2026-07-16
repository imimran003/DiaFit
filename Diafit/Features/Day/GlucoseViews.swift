import SwiftUI

struct GlucoseSummaryStrip: View {
    let day: Day
    let preferredUnit: GlucoseUnit
    let log: () -> Void
    let openHistory: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            summaryHeader

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 0) {
                    GlucoseSnapshot(label: "Fasting", reading: day.latestFastingReading, preferredUnit: preferredUnit)
                        .padding(.vertical, 8)
                    Divider().overlay(Color.rule.opacity(0.5))
                    GlucoseSnapshot(label: "Post-meal", reading: day.latestPostMealReading, preferredUnit: preferredUnit)
                        .padding(.vertical, 8)

                    logButton
                        .padding(.top, 10)
                }
            } else {
                HStack(spacing: 14) {
                    GlucoseSnapshot(label: "Fasting", reading: day.latestFastingReading, preferredUnit: preferredUnit)
                    Rectangle()
                        .fill(Color.rule.opacity(0.45))
                        .frame(width: 1, height: 34)
                    GlucoseSnapshot(label: "Post-meal", reading: day.latestPostMealReading, preferredUnit: preferredUnit)
                    Spacer(minLength: 0)
                    logButton
                }
            }
        }
        .padding(.top, 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Daily blood glucose")
    }

    private var summaryHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("GLUCOSE")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(Color.quietInk)
            Spacer(minLength: 8)
            Button("History", action: openHistory)
                .font(DiafitType.caption.weight(.semibold))
                .foregroundStyle(Color.quietInk)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(minHeight: 44)
        }
    }

    private var logButton: some View {
        Button(action: log) {
            Label("Log glucose", systemImage: "plus")
                .font(DiafitType.caption.weight(.semibold))
                .foregroundStyle(Color.ink)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
                .frame(minHeight: 44)
                .background(Color.lime.opacity(0.42), in: Capsule())
        }
        .buttonStyle(PressableStyle(pressedScale: 0.94))
        .accessibilityIdentifier("Log glucose")
    }
}

private struct GlucoseSnapshot: View {
    let label: String
    let reading: GlucoseReading?
    let preferredUnit: GlucoseUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(DiafitType.caption)
                .foregroundStyle(Color.quietInk)
            if let reading {
                Text("\(reading.displayed(in: preferredUnit)) \(preferredUnit.shortName)")
                    .font(DiafitType.body.weight(.bold))
                    .foregroundStyle(Color.ink)
                Text(reading.measuredAt.formatted(.dateTime.hour().minute()))
                    .font(DiafitType.caption)
                    .foregroundStyle(Color.quietInk.opacity(0.76))
            } else {
                Text("—")
                    .font(DiafitType.title.weight(.medium))
                    .foregroundStyle(Color.quietInk.opacity(0.65))
                Text("Not logged")
                    .font(DiafitType.caption)
                    .foregroundStyle(Color.quietInk.opacity(0.76))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reading.map { "\(label) glucose, \($0.accessibilityValue), measured \($0.measuredAt.formatted(date: .omitted, time: .shortened))" } ?? "No \(label.lowercased()) glucose reading")
    }
}

struct GlucoseReadingMoment: View {
    let reading: GlucoseReading

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "drop.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.ink)
                .frame(width: 36, height: 36)
                .background(Color.lime.opacity(0.42), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(reading.type.displayName)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(Color.quietInk)
                Text("\(reading.formattedValue) \(reading.unit.shortName)")
                    .font(DiafitType.title)
                    .foregroundStyle(Color.ink)
                Text(detailText)
                    .font(DiafitType.caption)
                    .foregroundStyle(Color.quietInk)
            }
            Spacer(minLength: 0)
            Text(reading.measuredAt.formatted(.dateTime.hour().minute()))
                .font(DiafitType.caption)
                .foregroundStyle(Color.quietInk)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.lime.opacity(0.13), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.lime.opacity(0.28), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(reading.type.displayName) glucose, \(reading.accessibilityValue), measured at \(reading.measuredAt.formatted(date: .omitted, time: .shortened))")
    }

    private var detailText: String {
        if let minutes = reading.minutesAfterMeal {
            return "\(minutesAfterMealLabel(minutes)) after meal"
        }
        if let note = reading.note, !note.isEmpty { return note }
        return reading.type == .fasting ? "FBS" : "Manual reading"
    }

    private func minutesAfterMealLabel(_ minutes: Int) -> String {
        if minutes % 60 == 0 { return "\(minutes / 60) hr" }
        return "\(minutes) min"
    }
}

struct GlucoseEntrySheet: View {
    let day: Day
    let existing: GlucoseReading?
    let initialDraft: GlucoseDraft?
    let onSave: (GlucoseReading) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("diafit.glucose.preferredUnit") private var preferredUnitRaw = GlucoseUnit.milligramsPerDeciliter.rawValue
    @State private var type: GlucoseReadingType
    @State private var valueText: String
    @State private var unit: GlucoseUnit
    @State private var measuredAt: Date
    @State private var selectedMealID: UUID?
    @State private var afterMealChoice: String
    @State private var customAfterMeal: String
    @State private var fastingDuration: String
    @State private var note: String
    @State private var validationMessage: String?
    @State private var unusualReading: GlucoseReading?
    @State private var unusualMessage = "This value is unusual. Check the number and unit before saving."

    init(day: Day, existing: GlucoseReading? = nil, initialDraft: GlucoseDraft? = nil, onSave: @escaping (GlucoseReading) -> Void) {
        self.day = day
        self.existing = existing
        self.initialDraft = initialDraft
        self.onSave = onSave
        let storedUnit = GlucoseUnit(rawValue: UserDefaults.standard.string(forKey: "diafit.glucose.preferredUnit") ?? "") ?? .milligramsPerDeciliter
        let resolvedUnit = existing?.unit ?? initialDraft?.unit ?? storedUnit
        _type = State(initialValue: existing?.type ?? initialDraft?.type ?? .fasting)
        _valueText = State(initialValue: existing.map { resolvedUnit.formatted(resolvedUnit.displayValue(from: $0.normalizedMgPerDl)) } ?? initialDraft.map { (initialDraft?.unit ?? resolvedUnit).formatted($0.value) } ?? "")
        _unit = State(initialValue: resolvedUnit)
        _measuredAt = State(initialValue: existing?.measuredAt ?? initialDraft?.measuredAt ?? .now)
        _selectedMealID = State(initialValue: existing?.mealId)
        _afterMealChoice = State(initialValue: existing?.minutesAfterMeal.map(String.init) ?? initialDraft?.minutesAfterMeal.map(String.init) ?? "none")
        _customAfterMeal = State(initialValue: "")
        _fastingDuration = State(initialValue: existing?.fastingDurationMinutes.map(String.init) ?? "")
        _note = State(initialValue: existing?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Reading type", selection: $type) {
                        Text("Fasting · FBS").tag(GlucoseReadingType.fasting)
                        Text("Post-meal").tag(GlucoseReadingType.postMeal)
                        Text("Before meal").tag(GlucoseReadingType.preMeal)
                        Text("Bedtime").tag(GlucoseReadingType.bedtime)
                        Text("Other").tag(GlucoseReadingType.other)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Glucose reading type")

                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        TextField("Value", text: $valueText)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .accessibilityLabel("Glucose value")
                            .accessibilityIdentifier("Glucose value")
                        Picker("Unit", selection: $unit) {
                            ForEach(GlucoseUnit.allCases, id: \.self) { Text($0.shortName).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .font(DiafitType.body.weight(.semibold))
                        .accessibilityLabel("Glucose unit")
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Reading")
                }

                Section {
                    DatePicker("Date and time", selection: $measuredAt, displayedComponents: [.date, .hourAndMinute])
                } header: {
                    Text("When")
                }

                if type == .postMeal {
                    Section {
                        Menu {
                            Button("No meal association") { selectedMealID = nil }
                            ForEach(day.meals) { meal in
                                Button {
                                    selectedMealID = meal.id
                                } label: {
                                    Label("\(meal.title) · \(meal.time.formatted(.dateTime.hour().minute()))", systemImage: selectedMealID == meal.id ? "checkmark" : "fork.knife")
                                }
                            }
                        } label: {
                            LabeledContent("Meal", value: selectedMealTitle)
                        }
                        Picker("Time after meal", selection: $afterMealChoice) {
                            Text("Choose later").tag("none")
                            Text("30 minutes").tag("30")
                            Text("1 hour").tag("60")
                            Text("90 minutes").tag("90")
                            Text("2 hours").tag("120")
                            Text("3 hours").tag("180")
                            Text("Custom").tag("custom")
                        }
                        if afterMealChoice == "custom" {
                            TextField("Minutes after meal", text: $customAfterMeal)
                                .keyboardType(.numberPad)
                        }
                    } header: {
                        Text("After the meal")
                    } footer: {
                        Text("Choose the timing if you know it. It is never assumed silently.")
                    }
                }

                if type == .fasting {
                    Section {
                        TextField("Fasting duration in minutes (optional)", text: $fastingDuration)
                            .keyboardType(.numberPad)
                    } header: {
                        Text("Fasting context")
                    }
                }

                Section {
                    TextField("Note (optional)", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }

                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .font(DiafitType.caption)
                            .foregroundStyle(Color.coral)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.paper)
            .navigationTitle(existing == nil ? "Log glucose" : "Edit glucose")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .accessibilityIdentifier("Save glucose")
                        .fontWeight(.semibold)
                        .disabled(valueText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("Check this reading", isPresented: Binding(get: { unusualReading != nil }, set: { if !$0 { unusualReading = nil } })) {
                Button("Save anyway") {
                    if let unusualReading { commit(unusualReading) }
                }
                Button("Keep editing", role: .cancel) { unusualReading = nil }
            } message: {
                Text(unusualMessage)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var selectedMealTitle: String {
        guard let selectedMealID, let meal = day.meals.first(where: { $0.id == selectedMealID }) else { return "No meal association" }
        return meal.title
    }

    private func save() {
        let rawValue = valueText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Decimal(string: rawValue, locale: Locale(identifier: "en_US_POSIX")) else {
            validationMessage = GlucoseEntryError.invalidDecimal.localizedDescription
            return
        }
        let minutes = minutesAfterMeal
        let fasting = Int(fastingDuration.trimmingCharacters(in: .whitespacesAndNewlines))
        let factory = GlucoseReadingFactory()
        switch factory.make(value: value, unit: unit, type: type, measuredAt: measuredAt, mealId: selectedMealID, minutesAfterMeal: minutes, fastingDurationMinutes: fasting, note: note, existing: existing) {
        case .failure(let error): validationMessage = error.localizedDescription
        case .success(let reading):
            let validation = DefaultGlucoseValidationService().validate(value: value, unit: unit, type: type, minutesAfterMeal: minutes)
            if validation.requiresConfirmation {
                unusualMessage = validation.message ?? unusualMessage
                unusualReading = reading
            } else {
                commit(reading)
            }
        }
    }

    private var minutesAfterMeal: Int? {
        if afterMealChoice == "custom" { return Int(customAfterMeal) }
        return Int(afterMealChoice)
    }

    private func commit(_ reading: GlucoseReading) {
        preferredUnitRaw = unit.rawValue
        if !reduceMotion { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        onSave(reading)
        dismiss()
    }
}

struct GlucoseHistoryView: View {
    @EnvironmentObject private var store: DiaryStore
    @Environment(\.dismiss) private var dismiss
    @State private var filter: GlucoseReadingType?
    @State private var daysRange = 30
    @State private var editing: EditingGlucose?
    @State private var deleting: EditingGlucose?
    @AppStorage("diafit.glucose.preferredUnit") private var preferredUnitRaw = GlucoseUnit.milligramsPerDeciliter.rawValue

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("GLUCOSE HISTORY")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .tracking(1.3)
                                .foregroundStyle(Color.quietInk)
                            Text("A quiet record of your readings")
                                .font(DiafitType.display)
                                .foregroundStyle(Color.ink)
                        }
                        Spacer()
                    }

                    Picker("Reading filter", selection: Binding(get: { filter?.rawValue ?? "all" }, set: { filter = GlucoseReadingType(rawValue: $0) })) {
                        Text("All").tag("all")
                        Text("Fasting").tag(GlucoseReadingType.fasting.rawValue)
                        Text("Post-meal").tag(GlucoseReadingType.postMeal.rawValue)
                    }
                    .pickerStyle(.segmented)

                    Picker("Date range", selection: $daysRange) {
                        Text("7 days").tag(7)
                        Text("30 days").tag(30)
                        Text("90 days").tag(90)
                    }
                    .pickerStyle(.segmented)

                    if !readings.isEmpty {
                        GlucoseTrendLine(readings: readings, preferredUnit: preferredUnit)
                            .frame(height: 150)
                            .padding(.vertical, 8)
                            .accessibilityLabel("Glucose trend for the selected period")
                        SummaryLine(summary: summary, preferredUnit: preferredUnit)
                    }

                    if readings.isEmpty {
                        Text("No readings in this period yet.")
                            .font(DiafitType.body)
                            .foregroundStyle(Color.quietInk)
                            .padding(.vertical, 32)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(readings) { reading in
                                GlucoseHistoryRow(reading: reading, preferredUnit: preferredUnit, edit: { editing = editingValue(for: reading) }, delete: { deleting = editingValue(for: reading) })
                                if reading.id != readings.last?.id { Divider().overlay(Color.rule.opacity(0.45)) }
                            }
                        }
                        .padding(.horizontal, 15)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }
                }
                .padding(20)
            }
            .background(Color.paper)
            .navigationTitle("Glucose")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .sheet(item: $editing) { value in
            GlucoseEntrySheet(day: value.day, existing: value.reading) { updated in
                _ = DiaryGlucoseReadingRepository().update(updated, in: value.day.id, store: store)
            }
        }
        .alert("Delete this reading?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { value in
            Button("Delete", role: .destructive) {
                _ = DiaryGlucoseReadingRepository().delete(value.reading, from: value.day.id, store: store)
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: { _ in
            Text("The reading will be removed from this diary. This does not make a medical judgement about it.")
        }
    }

    private var preferredUnit: GlucoseUnit { GlucoseUnit(rawValue: preferredUnitRaw) ?? .milligramsPerDeciliter }

    private var readings: [GlucoseReading] {
        GlucoseHistoryService().readings(in: store.days, range: GlucoseHistoryService().dateInterval(days: daysRange), type: filter)
    }

    private var summary: GlucoseDaySummary { GlucoseHistoryService().summary(for: readings) }

    private func editingValue(for reading: GlucoseReading) -> EditingGlucose? {
        guard let day = store.days.first(where: { $0.glucoseReadings.contains(where: { $0.id == reading.id }) }) else { return nil }
        return EditingGlucose(reading: reading, day: day)
    }
}

private struct SummaryLine: View {
    let summary: GlucoseDaySummary
    let preferredUnit: GlucoseUnit

    var body: some View {
        HStack(spacing: 18) {
            SummaryValue(label: "Average", value: summary.averageMgPerDl.map { preferredUnit.formatted(preferredUnit.displayValue(from: $0)) } ?? "—", unit: preferredUnit.shortName)
            SummaryValue(label: "Lowest", value: summary.minimumMgPerDl.map { preferredUnit.formatted(preferredUnit.displayValue(from: $0)) } ?? "—", unit: preferredUnit.shortName)
            SummaryValue(label: "Highest", value: summary.maximumMgPerDl.map { preferredUnit.formatted(preferredUnit.displayValue(from: $0)) } ?? "—", unit: preferredUnit.shortName)
            SummaryValue(label: "Readings", value: "\(summary.count)", unit: "")
        }
    }
}

private struct SummaryValue: View {
    let label: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased()).font(.system(size: 9, weight: .bold, design: .rounded)).tracking(0.7).foregroundStyle(Color.quietInk)
            Text(unit.isEmpty ? value : "\(value) \(unit)").font(DiafitType.body.weight(.semibold)).foregroundStyle(Color.ink)
        }
    }
}

private struct GlucoseHistoryRow: View {
    let reading: GlucoseReading
    let preferredUnit: GlucoseUnit
    let edit: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(reading.type.displayName).font(DiafitType.caption.weight(.semibold)).foregroundStyle(Color.ink)
                Text(reading.measuredAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())).font(DiafitType.caption).foregroundStyle(Color.quietInk)
            }
            Spacer()
            Text("\(reading.displayed(in: preferredUnit)) \(preferredUnit.shortName)").font(DiafitType.body.weight(.bold)).foregroundStyle(Color.ink)
            Menu {
                Button("Edit", systemImage: "pencil") { edit() }
                Button("Delete", systemImage: "trash", role: .destructive) { delete() }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(Color.quietInk)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Actions for \(reading.type.displayName) reading")
        }
        .padding(.vertical, 9)
    }
}

private struct GlucoseTrendLine: View {
    let readings: [GlucoseReading]
    let preferredUnit: GlucoseUnit

    var body: some View {
        GeometryReader { proxy in
            let values = readings.map { NSDecimalNumber(decimal: preferredUnit.displayValue(from: $0.normalizedMgPerDl)).doubleValue }
            let minValue = values.min() ?? 0
            let maxValue = max(values.max() ?? 1, minValue + 1)
            Path { path in
                for (index, value) in values.enumerated() {
                    let x = values.count == 1 ? proxy.size.width / 2 : CGFloat(index) / CGFloat(values.count - 1) * proxy.size.width
                    let y = proxy.size.height - CGFloat((value - minValue) / (maxValue - minValue)) * proxy.size.height
                    let point = CGPoint(x: x, y: y)
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }
            .stroke(Color.ink.opacity(0.82), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            .overlay {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    let x = values.count == 1 ? proxy.size.width / 2 : CGFloat(index) / CGFloat(values.count - 1) * proxy.size.width
                    let y = proxy.size.height - CGFloat((value - minValue) / (maxValue - minValue)) * proxy.size.height
                    Circle().fill(Color.lime).frame(width: 8, height: 8).position(x: x, y: y)
                }
            }
        }
        .padding(.horizontal, 6)
        .overlay(alignment: .leading) {
            Text("recent readings")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(Color.quietInk)
                .rotationEffect(.degrees(-90))
                .offset(x: -24)
        }
    }
}

private struct EditingGlucose: Identifiable {
    let reading: GlucoseReading
    let day: Day
    var id: UUID { reading.id }
}
