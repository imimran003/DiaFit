import Charts
import HealthKit
import SwiftUI

struct WeightInsightsCard: View {
    @EnvironmentObject private var store: DiaryStore
    @EnvironmentObject private var profileStore: UserProfileStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("diafit.weightHealthEnabled") private var healthEnabled = false
    @State private var healthReadings: [WeightReading] = []
    @State private var healthMessage: String?
    @State private var syncing = false
    @State private var expanded = false
    @State private var showingEntry = false
    @State private var window = 30
    private let health = HKHealthStore()
    private let type = HKQuantityType(.bodyMass)

    private var imperial: Bool { profileStore.preferences.measurementSystem == .imperial }
    private var unit: String { imperial ? "lb" : "kg" }
    private func displayWeight(_ kilograms: Double) -> Double {
        imperial ? kilograms / 0.45359237 : kilograms
    }

    private var visibleReadings: [WeightReading] {
        let calendar = Calendar.autoupdatingCurrent
        let now = Date.now
        guard let start = calendar.date(byAdding: .day, value: 1 - window, to: calendar.startOfDay(for: now)) else {
            return []
        }
        let eligible = (healthReadings + store.weighIns).filter { $0.date >= start && $0.date <= now }
        // The latest Apple Health sample represents its day. A local entry takes
        // precedence because the user entered it explicitly in Diafit.
        var byDay: [Date: WeightReading] = [:]
        for reading in eligible {
            byDay[calendar.startOfDay(for: reading.date)] = reading
        }
        return byDay.values.sorted { $0.date < $1.date }
    }

    private var chartDomain: ClosedRange<Double> {
        let weights = visibleReadings.map { displayWeight($0.kilograms) }
        return ((weights.min() ?? 0) - 1)...((weights.max() ?? 0) + 1)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Weight history period", selection: $window) {
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                }
                .pickerStyle(.segmented)

                if visibleReadings.isEmpty {
                    Text("No weigh-ins in this period. Add one here or connect Apple Health.")
                        .font(.footnote)
                        .foregroundStyle(Color.quietInk)
                } else {
                    if let latest = visibleReadings.last {
                        Text("\(displayWeight(latest.kilograms).formatted(.number.precision(.fractionLength(0...1)))) \(unit)")
                            .font(DiafitType.title)
                            .accessibilityLabel("Latest weight")
                            .accessibilityValue("\(displayWeight(latest.kilograms).formatted()) \(unit)")
                    }
                    Chart(visibleReadings) { reading in
                        LineMark(x: .value("Date", reading.date), y: .value(unit, displayWeight(reading.kilograms)))
                        PointMark(x: .value("Date", reading.date), y: .value(unit, displayWeight(reading.kilograms)))
                    }
                    .chartYScale(domain: chartDomain)
                    .frame(height: 150)
                    .accessibilityLabel("Weight history in \(unit)")
                    Text("One recorded weight per day. Missing days have no point.")
                        .font(.footnote)
                        .foregroundStyle(Color.quietInk)
                }

                if let goal = profileStore.profile.weightGoalKilograms {
                    Text("Weight goal · \(displayWeight(goal).formatted(.number.precision(.fractionLength(0...1)))) \(unit)")
                        .font(.subheadline)
                }

                Button("Add weigh-in", systemImage: "plus") { showingEntry = true }
                    .frame(minHeight: 44)

                if HKHealthStore.isHealthDataAvailable() {
                    Button(syncing ? "Syncing…" : healthEnabled ? "Refresh Apple Health" : "Connect Apple Health") {
                        Task { await refreshHealth(requestAccess: !healthEnabled) }
                    }
                    .disabled(syncing)
                    if let healthMessage {
                        Text(healthMessage).font(.footnote).foregroundStyle(Color.quietInk)
                    }
                }

                ForEach(store.weighIns.filter { entry in visibleReadings.contains { $0.id == entry.id } }.sorted { $0.date > $1.date }) { entry in
                    HStack {
                        Text(entry.date.formatted(.dateTime.month().day()))
                        Spacer()
                        Text("\(displayWeight(entry.kilograms).formatted(.number.precision(.fractionLength(0...1)))) \(unit)")
                        Button("Remove weigh-in", systemImage: "trash", role: .destructive) {
                            store.removeWeighIn(entry.id)
                        }
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                    }
                    .font(.footnote)
                }
                if let issue = store.persistenceIssue {
                    Text(issue).font(.footnote)
                }
            }
            .padding(.top, 14)
        } label: {
            Label("Weight progress", systemImage: "chart.xyaxis.line")
                .font(DiafitType.title)
                .foregroundStyle(Color.ink)
        }
        .padding(18)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 22))
        .task(id: expanded) {
            if expanded && healthEnabled { await refreshHealth() }
        }
        .onChange(of: healthEnabled) { _, enabled in
            if !enabled {
                healthReadings = []
                healthMessage = nil
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && expanded && healthEnabled {
                Task { await refreshHealth() }
            }
        }
        .sheet(isPresented: $showingEntry) {
            WeighInSheet(imperial: imperial)
        }
    }

    @MainActor
    private func refreshHealth(requestAccess: Bool = false) async {
        guard !syncing, HKHealthStore.isHealthDataAvailable() else { return }
        syncing = true
        defer { syncing = false }
        do {
            if requestAccess {
                try await health.requestAuthorization(toShare: [], read: [type])
                healthEnabled = true
            }
            let now = Date.now
            let calendar = Calendar.autoupdatingCurrent
            guard let start = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now)) else { return }
            let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictStartDate)
            let query = HKSampleQueryDescriptor(
                predicates: [.quantitySample(type: type, predicate: predicate)],
                sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
            )
            let samples = try await query.result(for: health)
            guard !Task.isCancelled, healthEnabled else { return }
            healthReadings = samples.compactMap { sample in
                let kilograms = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
                guard kilograms.isFinite, kilograms > 0 else { return nil }
                return WeightReading(id: sample.uuid, date: sample.startDate, kilograms: kilograms)
            }
            healthMessage = healthReadings.isEmpty
                ? "No weight readings available from Apple Health in the last 30 days."
                : "Apple Health weight readings updated."
        } catch {
            guard !Task.isCancelled else { return }
            healthMessage = "Couldn’t refresh Apple Health. Try again."
        }
    }
}

private struct WeighInSheet: View {
    @EnvironmentObject private var store: DiaryStore
    @Environment(\.dismiss) private var dismiss
    let imperial: Bool
    @State private var amount = ""
    @State private var date = Date.now
    @State private var error: String?

    private var kilograms: Double? {
        guard let value = try? Double(amount, format: .number) else { return nil }
        return imperial ? value * 0.45359237 : value
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(imperial ? "Weight in lb" : "Weight in kg", text: $amount)
                    .keyboardType(.decimalPad)
                DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                Text("A new weigh-in replaces your previous Diafit entry for that day.")
                    .font(.footnote)
                if let error { Text(error).font(.footnote) }
            }
            .navigationTitle("Add weigh-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let kilograms else { return }
                        if store.saveWeighIn(WeightReading(date: date, kilograms: kilograms)) {
                            dismiss()
                        } else {
                            error = store.persistenceIssue ?? "Enter a weight between 20 and 500 kg (44–1,102 lb)."
                        }
                    }
                    .disabled(kilograms == nil)
                }
            }
        }
    }
}
