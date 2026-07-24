import SwiftUI

struct DayThreadView: View {
    @EnvironmentObject private var store: DiaryStore
    @Environment(\.appDependencies) private var dependencies
    @Environment(\.scenePhase) private var scenePhase
    let dayID: Day.ID
    @Binding var isAtlasOpen: Bool
    let mealNamespace: Namespace.ID

    @State private var draft = ""
    @State private var isThinking = false
    @State private var thinkingLabel = "Looking that up"
    @State private var showsPhotoInput = false
    @State private var mealBeingEdited: Meal?
    @State private var mealPendingDeletion: Meal?
    @State private var showsGlucoseEntry = false
    @State private var showsGlucoseHistory = false
    @State private var glucoseDraft: GlucoseDraft?
    @State private var healthActivityState: HealthActivityViewState = .disconnected
    @FocusState private var composerFocused: Bool

    private var day: Day? { store.day(id: dayID) }

    var body: some View {
        Group {
            if let day {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 18) {
                            DayHeader(
                                day: day,
                                healthActivityState: healthActivityState,
                                openAtlas: openAtlas,
                                connectHealth: connectHealth,
                                refreshHealth: refreshHealth,
                                logGlucose: { showsGlucoseEntry = true },
                                openGlucoseHistory: { showsGlucoseHistory = true }
                            )
                                .padding(.bottom, day.meals.isEmpty ? 0 : 4)
                                // Preserve a large accessibility presentation
                                // without allowing editorial display type to
                                // consume the entire viewport at AX5.
                                .dynamicTypeSize(...DynamicTypeSize.accessibility2)

                            if day.meals.isEmpty {
                                EmptyMealState(
                                    addFood: { composerFocused = true },
                                    openPhoto: { showsPhotoInput = true }
                                )
                                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                            }

                            ForEach(day.messages) { item in
                                ThreadItemView(
                                    item: item,
                                    isAtlasOpen: $isAtlasOpen,
                                    mealNamespace: mealNamespace,
                                    updateDraft: { draft in
                                        store.update(draft, for: item.id, in: dayID)
                                    },
                                    confirmDraft: { draft in
                                        confirm(draft, replacing: item.id)
                                    },
                                    discardDraft: {
                                        store.remove(itemID: item.id, from: dayID)
                                    },
                                    retryDraftVisual: { draft in
                                        Task {
                                            await dependencies.mealVisuals.prepare(
                                                draft: draft,
                                                itemID: item.id,
                                                in: store,
                                                dayID: dayID
                                            )
                                        }
                                    },
                                    editMeal: { meal in
                                        mealBeingEdited = meal
                                    },
                                    deleteMeal: { meal in
                                        mealPendingDeletion = meal
                                    },
                                    associatedGlucoseReadings: {
                                        if case .meal(let meal) = item.kind {
                                            return day.glucoseReadings.filter { $0.mealId == meal.id }
                                        }
                                        return []
                                    }()
                                )
                                .id(item.id)
                            }

                            if isThinking {
                                ThinkingBubble(label: thinkingLabel)
                                    .id("thinking")
                            }

                            Color.clear.frame(height: 112).id("tail")
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        Composer(
                            text: $draft,
                            isThinking: isThinking,
                            isFocused: $composerFocused,
                            openPhoto: { showsPhotoInput = true },
                            submit: submit
                        )
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    }
                    .onChange(of: day.messages.count) { _, _ in
                        scrollToTail(proxy)
                    }
                    .onChange(of: isThinking) { _, _ in
                        scrollToTail(proxy)
                    }
                }
            }
        }
        .sheet(isPresented: $showsPhotoInput) {
            PhotoMealInput(onContinue: beginPhotoReview)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsGlucoseEntry) {
            if let day {
                GlucoseEntrySheet(day: day) { reading in
                    saveGlucose(reading, in: dayID)
                }
            }
        }
        .sheet(item: $glucoseDraft) { draft in
            if let day {
                GlucoseEntrySheet(day: day, initialDraft: draft) { reading in
                    saveGlucose(reading, in: dayID)
                }
            }
        }
        .sheet(isPresented: $showsGlucoseHistory) {
            GlucoseHistoryView()
                .environmentObject(store)
        }
        .sheet(item: $mealBeingEdited) { meal in
            if let analysis = meal.analysis {
                NavigationStack {
                    ScrollView(showsIndicators: false) {
                        MealAnalysisReviewCard(
                            draft: MealAnalysisDraft(result: analysis),
                            onUpdate: { _ in },
                            onConfirm: { draft in update(meal, from: draft) },
                            onDiscard: { mealBeingEdited = nil },
                            onRetryVisual: { draft in
                                guard let itemID = store.day(id: dayID)?.messages.first(where: { item in
                                    if case .meal(let saved) = item.kind { return saved.id == meal.id }
                                    return false
                                })?.id else { return }
                                Task {
                                    await dependencies.mealVisuals.prepare(
                                        draft: draft,
                                        itemID: itemID,
                                        in: store,
                                        dayID: dayID
                                    )
                                }
                            },
                            confirmationTitle: "Save changes"
                        )
                        .padding(20)
                    }
                    .background(Color.paper)
                    .navigationTitle("Refine estimate")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
        .alert("Delete this meal?", isPresented: Binding(
            get: { mealPendingDeletion != nil },
            set: { if !$0 { mealPendingDeletion = nil } }
        ), presenting: mealPendingDeletion) { meal in
            Button("Delete", role: .destructive) {
                Task { await dependencies.mealVisuals.delete(meal: meal) }
                DiaryMealLoggingService().delete(mealID: meal.id, in: store, dayID: dayID)
                mealPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { mealPendingDeletion = nil }
        } message: { meal in
            Text("\(meal.title) will be removed from this day. This can’t be undone in the current session.")
        }
        .task(id: dayID) {
            await loadHealthActivity()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, dependencies.healthActivity.hasRequestedAccess else { return }
            Task { await loadHealthActivity() }
        }
    }

    private func connectHealth() {
        Task { @MainActor in
            healthActivityState = .loading
            do {
                try await dependencies.healthActivity.requestAccess()
                await loadHealthActivity()
            } catch {
                healthActivityState = dependencies.healthActivity.isAvailable
                    ? .failed("Health access wasn’t completed. You can try again.")
                    : .unavailable
            }
        }
    }

    private func refreshHealth() {
        Task { await loadHealthActivity() }
    }

    @MainActor
    private func loadHealthActivity() async {
        let health = dependencies.healthActivity
        guard health.isAvailable else {
            healthActivityState = .unavailable
            return
        }
        guard health.hasRequestedAccess else {
            healthActivityState = .disconnected
            return
        }
        healthActivityState = .loading
        do {
            let date = store.day(id: dayID)?.date ?? .now
            healthActivityState = .ready(try await health.summary(for: date, calendar: .autoupdatingCurrent))
        } catch {
            healthActivityState = .failed("Apple Health data couldn’t be refreshed.")
        }
    }

    private func scrollToTail(_ proxy: ScrollViewProxy, animated: Bool = true) {
        DispatchQueue.main.async {
            if animated {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    proxy.scrollTo("tail", anchor: .bottom)
                }
            } else {
                proxy.scrollTo("tail", anchor: .bottom)
            }
        }
    }

    private func openAtlas() {
        composerFocused = false
        isAtlasOpen = true
    }

    private func submit() {
        let note = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty, !isThinking else { return }
        draft = ""
        composerFocused = false
        store.append(ThreadItem(id: UUID(), kind: .person(text: note)), to: dayID)

        switch dependencies.conversationInputRouter.route(note) {
        case .glucose(let parsedGlucose):
            glucoseDraft = parsedGlucose
            store.append(ThreadItem(id: UUID(), kind: .agent(text: "I found a glucose reading. Check the unit and context before saving it.", tools: ["Needs confirmation"])), to: dayID)
            return
        case .clarification(let question):
            store.append(ThreadItem(id: UUID(), kind: .agent(text: question, tools: ["Clarify intent"])), to: dayID)
            return
        case .food:
            break
        }

        isThinking = true
        thinkingLabel = "Checking nutrition"

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(720))
            switch ConversationCoordinator.nutrition.resolve(note: note, at: .now) {
            case .saved(let meal):
                store.append(ThreadItem(id: UUID(), kind: .meal(meal)), to: dayID)
                try? await Task.sleep(for: .milliseconds(420))
                store.append(
                    ThreadItem(
                        id: UUID(),
                        kind: .agent(
                            text: ConversationCoordinator.acknowledgement(for: meal),
                            tools: ["Nutrition checked", "Day totals updated"]
                        )
                    ),
                    to: dayID
                )
            case .review(_):
                let resolvedResult = await dependencies.textMealAnalysis.analyse(text: note)
                let review = MealAnalysisDraft(result: resolvedResult)
                let reviewItemID = UUID()
                store.append(ThreadItem(id: reviewItemID, kind: .mealAnalysis(review)), to: dayID)
                Task {
                    await dependencies.mealVisuals.prepare(
                        draft: review,
                        itemID: reviewItemID,
                        in: store,
                        dayID: dayID
                    )
                }
                try? await Task.sleep(for: .milliseconds(260))
                store.append(
                    ThreadItem(
                        id: UUID(),
                        kind: .agent(
                            text: ConversationCoordinator.acknowledgement(for: review),
                            tools: ["Nutrition review", "No totals saved yet"]
                        )
                    ),
                    to: dayID
                )
            }
            isThinking = false
        }
    }

    private func saveGlucose(_ reading: GlucoseReading, in dayID: Day.ID) {
        let result = DiaryGlucoseReadingRepository().save(reading, to: dayID, in: store)
        switch result {
        case .success:
            store.append(ThreadItem(id: UUID(), kind: .agent(text: "Saved your \(reading.type.displayName.lowercased()) glucose reading. I kept it informational and tied it to the selected time.", tools: ["Saved", "Glucose history updated"])), to: dayID)
        case .failure(let error):
            store.append(ThreadItem(id: UUID(), kind: .agent(text: error.localizedDescription, tools: ["Needs review"])), to: dayID)
        }
    }

    private func beginPhotoReview(_ image: PreparedFoodImage, description: String) {
        guard !isThinking else { return }
        composerFocused = false
        store.append(ThreadItem(id: UUID(), kind: .person(text: "Photo note · \(description)")), to: dayID)
        isThinking = true
        thinkingLabel = "Identifying meal components"

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(520))
            thinkingLabel = "Checking nutrition data"
            let result = await dependencies.photoAnalysis.analyse(image: image, description: description)
            let review = MealAnalysisDraft(result: result, transientImageData: image.data)
            let reviewItemID = UUID()
            store.append(ThreadItem(id: reviewItemID, kind: .mealAnalysis(review)), to: dayID)
            Task {
                await dependencies.mealVisuals.prepare(
                    draft: review,
                    itemID: reviewItemID,
                    in: store,
                    dayID: dayID
                )
            }
            isThinking = false
        }
    }

    private func confirm(_ draft: MealAnalysisDraft, replacing itemID: ThreadItem.ID) {
        let meal = DiaryMealLoggingService(userFoodMemory: dependencies.userFoodMemory)
            .confirm(draft, replacing: itemID, in: store, dayID: dayID)
        store.append(
            ThreadItem(
                id: UUID(),
                kind: .agent(
                    text: "Saved \(meal.title) as an estimate. I kept the serving and recipe assumptions with it, so you can revisit them any time.",
                    tools: ["Saved", "Day totals updated"]
                )
            ),
            to: dayID
        )
    }

    private func update(_ meal: Meal, from draft: MealAnalysisDraft) {
        var updated = meal
        updated.energy = Int(draft.result.mealTotals.caloriesKcal?.rounded() ?? 0)
        updated.carbs = Int(draft.result.mealTotals.carbohydrateGrams?.rounded() ?? 0)
        updated.protein = Int(draft.result.mealTotals.proteinGrams?.rounded() ?? 0)
        updated.fat = Int(draft.result.mealTotals.fatGrams?.rounded() ?? 0)
        updated.subtitle = "Confirmed estimate · \(draft.result.nutritionProvenance.dataSource)"
        updated.analysis = draft.result
        DiaryMealLoggingService().update(updated, in: store, dayID: dayID)
        mealBeingEdited = nil
        if let itemID = store.day(id: dayID)?.messages.first(where: { item in
            if case .meal(let saved) = item.kind { return saved.id == meal.id }
            return false
        })?.id {
            Task {
                await dependencies.mealVisuals.prepare(
                    draft: draft,
                    itemID: itemID,
                    in: store,
                    dayID: dayID
                )
            }
        }
    }
}

private struct DayHeader: View {
    let day: Day
    let healthActivityState: HealthActivityViewState
    let openAtlas: () -> Void
    let connectHealth: () -> Void
    let refreshHealth: () -> Void
    let logGlucose: () -> Void
    let openGlucoseHistory: () -> Void

    private var dateTitle: String {
        if Calendar.current.isDateInToday(day.date) { return "Today" }
        if Calendar.current.isDateInYesterday(day.date) { return "Yesterday" }
        return day.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(dateTitle)
                        .font(DiafitType.display)
                        .foregroundStyle(Color.ink)
                    Text(day.date.formatted(.dateTime.month(.wide).day()))
                        .font(DiafitType.caption)
                        .foregroundStyle(Color.quietInk)
                }

                Spacer()

                if !day.meals.isEmpty {
                    Button(action: openAtlas) {
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.ink)
                            .frame(width: 44, height: 44)
                            .background(Color.mist.opacity(0.72), in: Circle())
                    }
                    .buttonStyle(PressableStyle(pressedScale: 0.9))
                    .accessibilityLabel("Open meal atlas")
                }
            }

            DailyRhythm(day: day)
            EnergyAndMovementSection(
                intakeKilocalories: day.totalEnergy,
                state: healthActivityState,
                connect: connectHealth,
                refresh: refreshHealth
            )
            GlucoseSummaryStrip(
                day: day,
                preferredUnit: GlucoseUnit(rawValue: UserDefaults.standard.string(forKey: "diafit.glucose.preferredUnit") ?? "") ?? .milligramsPerDeciliter,
                log: logGlucose,
                openHistory: openGlucoseHistory
            )
        }
        .padding(.top, 8)
    }
}

private enum HealthActivityViewState: Equatable {
    case disconnected
    case loading
    case ready(HealthActivitySummary)
    case unavailable
    case failed(String)
}

private struct EnergyAndMovementSection: View {
    let intakeKilocalories: Int
    let state: HealthActivityViewState
    let connect: () -> Void
    let refresh: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("ENERGY & MOVEMENT")
                    .font(DiafitType.caption.weight(.bold))
                    .tracking(1.8)
                    .foregroundStyle(Color.quietInk)
                Spacer()
                trailingAction
            }

            switch state {
            case .disconnected:
                connectionPrompt
            case .loading:
                loading
            case .ready(let summary):
                activity(summary)
            case .unavailable:
                statusMessage("Apple Health isn’t available on this device.")
            case .failed(let message):
                failure(message)
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var trailingAction: some View {
        switch state {
        case .disconnected:
            Button("Connect Health", action: connect)
                .font(DiafitType.caption.weight(.semibold))
                .foregroundStyle(Color.ink)
                .frame(minHeight: 44)
                .accessibilityHint("Choose which activity information Diafit may read")
        case .ready, .failed:
            Button(action: refresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .foregroundStyle(Color.ink)
            .accessibilityLabel("Refresh Apple Health activity")
        case .loading:
            ProgressView()
                .controlSize(.small)
                .frame(width: 44, height: 44)
                .accessibilityLabel("Refreshing Apple Health activity")
        case .unavailable:
            EmptyView()
        }
    }

    private var connectionPrompt: some View {
        Button(action: connect) {
            HStack(spacing: 13) {
                Image(systemName: "heart.text.square")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .frame(width: 40, height: 40)
                    .background(Color.lime.opacity(0.58), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("Add activity from Apple Health")
                        .font(DiafitType.body.weight(.semibold))
                        .foregroundStyle(Color.ink)
                    Text("Steps, distance, calories burned, and your daily balance.")
                        .font(DiafitType.caption)
                        .foregroundStyle(Color.quietInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.quietInk)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(pressedScale: 0.98))
        .accessibilityLabel("Connect Apple Health")
        .accessibilityHint("Reads steps, distance, active energy, and resting energy")
    }

    private var loading: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text("Refreshing today’s movement…")
                .font(DiafitType.caption)
                .foregroundStyle(Color.quietInk)
        }
        .frame(minHeight: 52, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func activity(_ summary: HealthActivitySummary) -> some View {
        let balance = DailyEnergyBalance.calculate(
            intakeKilocalories: intakeKilocalories,
            burnedKilocalories: summary.totalEnergyBurnedKilocalories
        )

        VStack(alignment: .leading, spacing: 12) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 0) {
                        energyRows(summary: summary, balance: balance)
                    }
                } else {
                    HStack(alignment: .top, spacing: 0) {
                        energyColumns(summary: summary, balance: balance)
                    }
                }
            }

            HStack(spacing: 10) {
                MovementLabel(
                    icon: "figure.walk",
                    text: summary.steps.map { $0.formatted() + " steps" } ?? "Steps —"
                )
                Text("·").foregroundStyle(Color.rule)
                MovementLabel(
                    icon: "point.topleft.down.to.point.bottomright.curvepath",
                    text: summary.walkingRunningKilometres.map { $0.formatted(.number.precision(.fractionLength(1))) + " km" } ?? "Distance —"
                )
            }
            .font(DiafitType.caption)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("health-summary-movement")
            .accessibilityLabel(movementAccessibilityLabel(summary))

            if summary.totalEnergyBurnedKilocalories == nil {
                Text(summary.hasAnyData
                     ? "Daily balance needs both active and resting energy from Apple Health."
                     : "No Apple Health activity was found for this day.")
                    .font(DiafitType.caption)
                    .foregroundStyle(Color.quietInk)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Burned combines active and resting energy. Balance is intake minus burned.")
                    .font(DiafitType.caption)
                    .foregroundStyle(Color.quietInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func energyColumns(summary: HealthActivitySummary, balance: DailyEnergyBalance?) -> some View {
        HealthMetric(label: "Eaten", value: "\(intakeKilocalories)", unit: "kcal", identifier: "health-summary-eaten")
        SummaryDivider()
        HealthMetric(
            label: "Burned",
            value: summary.totalEnergyBurnedKilocalories.map { "\(Int($0.rounded()))" } ?? "—",
            unit: summary.totalEnergyBurnedKilocalories == nil ? "" : "kcal",
            identifier: "health-summary-burned"
        )
        SummaryDivider()
        HealthMetric(
            label: balance?.kind.displayName ?? "Balance",
            value: balance.map { "\($0.differenceKilocalories)" } ?? "—",
            unit: balance == nil ? "" : "kcal",
            identifier: "health-summary-balance"
        )
    }

    @ViewBuilder
    private func energyRows(summary: HealthActivitySummary, balance: DailyEnergyBalance?) -> some View {
        HealthMetric(label: "Eaten", value: "\(intakeKilocalories)", unit: "kcal", identifier: "health-summary-eaten", horizontal: true)
        Divider().overlay(Color.rule.opacity(0.65))
        HealthMetric(
            label: "Burned",
            value: summary.totalEnergyBurnedKilocalories.map { "\(Int($0.rounded()))" } ?? "—",
            unit: summary.totalEnergyBurnedKilocalories == nil ? "" : "kcal",
            identifier: "health-summary-burned",
            horizontal: true
        )
        Divider().overlay(Color.rule.opacity(0.65))
        HealthMetric(
            label: balance?.kind.displayName ?? "Balance",
            value: balance.map { "\($0.differenceKilocalories)" } ?? "—",
            unit: balance == nil ? "" : "kcal",
            identifier: "health-summary-balance",
            horizontal: true
        )
    }

    private func statusMessage(_ message: String) -> some View {
        Text(message)
            .font(DiafitType.caption)
            .foregroundStyle(Color.quietInk)
            .frame(minHeight: 44, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func movementAccessibilityLabel(_ summary: HealthActivitySummary) -> String {
        let steps = summary.steps.map { "\($0.formatted()) steps" } ?? "Steps unavailable"
        let distance = summary.walkingRunningKilometres.map {
            "\($0.formatted(.number.precision(.fractionLength(1)))) kilometers"
        } ?? "Distance unavailable"
        return "\(steps), \(distance)"
    }

    private func failure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(message)
                .font(DiafitType.caption)
                .foregroundStyle(Color.quietInk)
            Button("Try again", action: refresh)
                .font(DiafitType.caption.weight(.semibold))
                .foregroundStyle(Color.ink)
                .frame(minHeight: 44)
        }
    }
}

private struct HealthMetric: View {
    let label: String
    let value: String
    let unit: String
    let identifier: String
    var horizontal = false

    var body: some View {
        Group {
            if horizontal {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(label)
                        .font(DiafitType.caption)
                        .foregroundStyle(Color.quietInk)
                    Spacer(minLength: 12)
                    valueView
                }
                .padding(.vertical, 10)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    Text(label)
                        .font(DiafitType.caption)
                        .foregroundStyle(Color.quietInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    valueView
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(unit.isEmpty ? "\(label), unavailable" : "\(label), \(value) kilocalories")
        .accessibilityIdentifier(identifier)
    }

    private var valueView: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(DiafitType.metric)
                .fontWeight(.semibold)
                .monospacedDigit()
            if !unit.isEmpty {
                Text(unit)
                    .font(DiafitType.caption)
                    .foregroundStyle(Color.quietInk)
            }
        }
        .foregroundStyle(Color.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
    }
}

private struct MovementLabel: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .foregroundStyle(Color.quietInk)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

private struct DailyRhythm: View {
    let day: Day

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 0) {
                    metricRows
                }
            } else {
                HStack(alignment: .top, spacing: 0) {
                    metricColumns
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var metricColumns: some View {
        NutritionMetric(
            label: "Calories", value: day.totalEnergy, unit: "kcal",
            spokenUnit: "kilocalories", identifier: "daily-summary-calories"
        )
        SummaryDivider()
        NutritionMetric(
            label: "Carbohydrates", value: day.totalCarbs, unit: "g",
            spokenUnit: "grams", identifier: "daily-summary-carbohydrates"
        )
        SummaryDivider()
        NutritionMetric(
            label: "Protein", value: day.totalProtein, unit: "g",
            spokenUnit: "grams", identifier: "daily-summary-protein",
            isComplete: day.proteinTotalIsComplete
        )
    }

    @ViewBuilder
    private var metricRows: some View {
        NutritionMetric(
            label: "Calories", value: day.totalEnergy, unit: "kcal",
            spokenUnit: "kilocalories", identifier: "daily-summary-calories", horizontal: true
        )
        Divider().overlay(Color.rule.opacity(0.65))
        NutritionMetric(
            label: "Carbohydrates", value: day.totalCarbs, unit: "g",
            spokenUnit: "grams", identifier: "daily-summary-carbohydrates", horizontal: true
        )
        Divider().overlay(Color.rule.opacity(0.65))
        NutritionMetric(
            label: "Protein", value: day.totalProtein, unit: "g",
            spokenUnit: "grams", identifier: "daily-summary-protein",
            isComplete: day.proteinTotalIsComplete, horizontal: true
        )
    }
}

private struct NutritionMetric: View {
    let label: String
    let value: Int
    let unit: String
    let spokenUnit: String
    let identifier: String
    var isComplete = true
    var horizontal = false

    var body: some View {
        Group {
            if horizontal {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(label)
                        .font(DiafitType.caption)
                        .foregroundStyle(Color.quietInk)
                    Spacer(minLength: 12)
                    valueLabel
                }
                .padding(.vertical, 11)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    Text(label)
                        .font(DiafitType.caption)
                        .foregroundStyle(Color.quietInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)
                    valueLabel
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(value) \(spokenUnit)\(isComplete ? "" : ", known amount; some meal data is unavailable")")
        .accessibilityIdentifier(identifier)
    }

    private var valueLabel: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(value)")
                .font(DiafitType.metric)
                .fontWeight(.semibold)
                .monospacedDigit()
            Text(unit)
                .font(DiafitType.caption)
                .foregroundStyle(Color.quietInk)
        }
        .foregroundStyle(Color.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
    }
}

private struct SummaryDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.rule.opacity(0.72))
            .frame(width: 1, height: 42)
            .padding(.horizontal, 12)
            .accessibilityHidden(true)
    }
}

private struct EmptyMealState: View {
    let addFood: () -> Void
    let openPhoto: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 0) {
                Text("No meals logged yet")
                    .font(DiafitType.title)
                    .foregroundStyle(Color.ink)
                Text("Add what you ate when you’re ready.")
                    .font(DiafitType.body)
                    .foregroundStyle(Color.quietInk)
                    .padding(.top, 5)
            }

            HStack(spacing: 12) {
                Button(action: addFood) {
                    Label("Add food", systemImage: "plus")
                        .font(DiafitType.body.weight(.semibold))
                        .foregroundStyle(Color.paper)
                        .frame(minHeight: 48)
                        .padding(.horizontal, 18)
                        .background(Color.ink, in: Capsule())
                }
                .buttonStyle(PressableStyle(pressedScale: 0.96))

                Button(action: openPhoto) {
                    Image(systemName: "camera")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.ink)
                        .frame(width: 48, height: 48)
                        .background(Color.mist.opacity(0.76), in: Circle())
                }
                .buttonStyle(PressableStyle(pressedScale: 0.92))
                .accessibilityLabel("Add meal photo")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.rule.opacity(0.58))
                .frame(height: 1)
        }
    }
}

private struct ThinkingBubble: View {
    let label: String

    private var usesStaticRendering: Bool {
        ProcessInfo.processInfo.arguments.contains("UITestMode")
    }

    var body: some View {
        HStack(spacing: 9) {
            if usesStaticRendering {
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(Color.quietInk.opacity(index == 1 ? 0.9 : 0.25))
                            .frame(width: 5, height: 5)
                            .offset(y: index == 1 ? -2 : 0)
                    }
                }
            } else {
                TimelineView(.animation(minimumInterval: 0.6)) { context in
                    let phase = Int(context.date.timeIntervalSinceReferenceDate * 2) % 3
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { index in
                            Circle()
                                .fill(Color.quietInk.opacity(index == phase ? 0.9 : 0.25))
                                .frame(width: 5, height: 5)
                                .offset(y: index == phase ? -2 : 0)
                        }
                    }
                }
            }
            Text(label)
                .font(DiafitType.caption)
                .foregroundStyle(Color.quietInk)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .background(.white.opacity(0.65), in: Capsule())
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Composer: View {
    @Binding var text: String
    let isThinking: Bool
    var isFocused: FocusState<Bool>.Binding
    let openPhoto: () -> Void
    let submit: () -> Void

    var body: some View {
        HStack(spacing: 11) {
                Button(action: openPhoto) {
                    Image(systemName: "camera")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.ink)
                        .frame(width: 36, height: 36)
                        .background(Color.mist.opacity(0.72), in: Circle())
                }
                .buttonStyle(PressableStyle(pressedScale: 0.88))
                .accessibilityLabel("Add meal photo")

                TextField("Tell me what you ate", text: $text)
                    .font(DiafitType.body)
                    .foregroundStyle(Color.ink)
                    .focused(isFocused)
                    .lineLimit(1)
                    .submitLabel(.send)
                    .onSubmit(submit)

                Button(action: submit) {
                    Image(systemName: isThinking ? "ellipsis" : "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.quietInk : Color.paper)
                        .frame(width: 36, height: 36)
                        .background(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.mist : Color.ink, in: Circle())
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isThinking)
                .buttonStyle(PressableStyle(pressedScale: 0.86))
                .accessibilityLabel("Send food note")
        }
        .padding(.leading, 18)
        .padding(.trailing, 7)
        .padding(.vertical, 7)
        .background(Color.mist.opacity(0.82), in: Capsule())
        .overlay(Capsule().stroke(Color.rule.opacity(0.58), lineWidth: 0.8))
        .padding(.horizontal, 20)
        .padding(.top, 9)
        .padding(.bottom, 10)
        .background(Color.paper)
    }
}

struct DayThreadView_Previews: PreviewProvider {
    static var previews: some View { DayThreadPreview() }

    private struct DayThreadPreview: View {
        @Namespace private var namespace

        var body: some View {
            DayThreadView(
                dayID: DiaryStore.preview.days.last!.id,
                isAtlasOpen: .constant(false),
                mealNamespace: namespace
            )
            .environmentObject(DiaryStore.preview)
        }
    }
}
