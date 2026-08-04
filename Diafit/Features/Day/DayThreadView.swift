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
    @State private var dailyReviewReminderEnabled = false
    @State private var isEnablingDailyReviewReminder = false
    @State private var dailyReviewReminderMessage: String?
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
                                .padding(.bottom, day.meals.isEmpty ? 0 : 2)
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
                            } else {
                                MealStreamHeader(day: day)
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
                                    retryDraftAnalysis: { draft in
                                        retryPhotoAnalysis(draft, itemID: item.id)
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

                            DailyNutritionReviewSection(
                                day: day,
                                activity: healthActivitySummary,
                                reminderEnabled: dailyReviewReminderEnabled,
                                isEnablingReminder: isEnablingDailyReviewReminder,
                                reminderMessage: dailyReviewReminderMessage,
                                enableReminder: enableDailyReviewReminder
                            )

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
                            draft: MealAnalysisDraft(result: analysis, mealPeriod: meal.period),
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
            dailyReviewReminderEnabled = await dependencies.dailyReviewReminder.isEnabled()
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

    private var healthActivitySummary: HealthActivitySummary? {
        if case .ready(let summary) = healthActivityState { return summary }
        return nil
    }

    private func enableDailyReviewReminder() {
        guard !isEnablingDailyReviewReminder else { return }
        isEnablingDailyReviewReminder = true
        dailyReviewReminderMessage = nil
        Task { @MainActor in
            do {
                let enabled = try await dependencies.dailyReviewReminder.enable(hour: 22)
                dailyReviewReminderEnabled = enabled
                dailyReviewReminderMessage = enabled
                    ? "10 PM reminder enabled."
                    : "Notifications are off. You can enable them in Settings."
            } catch {
                dailyReviewReminderMessage = "The reminder could not be scheduled. Try again."
            }
            isEnablingDailyReviewReminder = false
        }
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
            let usesStaticRendering = ProcessInfo.processInfo.arguments.contains("UITestMode")
            if animated && !usesStaticRendering {
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

        if let day {
            switch PreviousDayMealReferenceService().resolve(
                note,
                currentDay: day,
                allDays: store.days
            ) {
            case .notAReference:
                break
            case .unavailable(let message):
                store.append(
                    ThreadItem(id: UUID(), kind: .agent(text: message, tools: ["Nothing added"])),
                    to: dayID
                )
                return
            case .review(let review, let sourceDescription):
                let reviewItemID = UUID()
                store.append(ThreadItem(id: reviewItemID, kind: .mealAnalysis(review)), to: dayID)
                store.append(
                    ThreadItem(
                        id: UUID(),
                        kind: .agent(
                            text: "I found \(sourceDescription). Check that today’s portions match, then confirm to log a new meal.",
                            tools: ["Copied for review", "Not saved yet"]
                        )
                    ),
                    to: dayID
                )
                return
            }
        }

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
            switch ConversationCoordinator.nutrition.resolve(note: note, at: .now) {
            case .saved(let meal):
                store.append(ThreadItem(id: UUID(), kind: .meal(meal)), to: dayID)
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
                let selectedDate = store.day(id: dayID)?.date ?? .now
                let review = MealAnalysisDraft(
                    result: resolvedResult,
                    mealPeriod: .suggested(for: selectedDate)
                )
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

    private func retryPhotoAnalysis(_ draft: MealAnalysisDraft, itemID: ThreadItem.ID) {
        guard let imageData = draft.transientImageData else { return }
        composerFocused = false

        Task { @MainActor in
            do {
                let prepared = try AppleImagePreparationService().prepare(imageData: imageData)
                let result = await dependencies.photoAnalysis.analyse(
                    image: prepared,
                    description: ""
                )
                store.update(
                    MealAnalysisDraft(result: result, transientImageData: prepared.data),
                    for: itemID,
                    in: dayID
                )
            } catch {
                var failedDraft = draft
                failedDraft.result.warnings = SemanticQuestionDeduplicator.uniqueStrings(
                    [error.localizedDescription] + failedDraft.result.warnings
                )
                store.update(failedDraft, for: itemID, in: dayID)
            }
        }
    }

    private func confirm(_ draft: MealAnalysisDraft, replacing itemID: ThreadItem.ID) {
        let originalPhotoData = draft.transientImageData
        let meal = DiaryMealLoggingService(userFoodMemory: dependencies.userFoodMemory)
            .confirm(draft, replacing: itemID, in: store, dayID: dayID)
        if let originalPhotoData {
            Task {
                await dependencies.mealVisuals.retainOriginalPhoto(
                    originalPhotoData,
                    mealID: meal.id,
                    in: store,
                    dayID: dayID
                )
            }
        }
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
        updated.period = draft.mealPeriod
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
        return day.date.formatted(.dateTime.weekday(.wide))
    }

    private var dateEyebrow: String {
        if Calendar.current.isDateInToday(day.date) { return "YOUR DAY" }
        if Calendar.current.isDateInYesterday(day.date) { return "RECENTLY" }
        return day.date.formatted(.dateTime.month(.abbreviated).day()).uppercased()
    }

    private var dayPulse: String {
        if day.meals.isEmpty { return "A clear slate" }
        let mealLabel = day.meals.count == 1 ? "meal" : "meals"
        return "\(day.meals.count) \(mealLabel) logged"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(dateEyebrow)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.7)
                        .foregroundStyle(Color.quietInk)
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

            HStack(spacing: 8) {
                Circle()
                    .fill(Color.lime)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                Text(dayPulse)
                    .font(DiafitType.caption.weight(.semibold))
                    .foregroundStyle(Color.ink)
                Spacer(minLength: 8)
                Text(day.meals.isEmpty ? "Ready when you are" : "\(day.totalEnergy) kcal so far")
                    .font(DiafitType.caption)
                    .foregroundStyle(Color.quietInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(day.meals.isEmpty ? "No meals logged yet" : "\(day.meals.count) meals logged, \(day.totalEnergy) kilocalories so far")

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

private struct MealStreamHeader: View {
    let day: Day

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("MEALS")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.8)
                    .foregroundStyle(Color.quietInk)
                Text("Your day in plates")
                    .font(DiafitType.title)
                    .foregroundStyle(Color.ink)
            }
            Spacer(minLength: 8)
            Text(day.meals.count == 1 ? "1 entry" : "\(day.meals.count) entries")
                .font(DiafitType.caption.weight(.semibold))
                .foregroundStyle(Color.quietInk)
        }
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Meals, \(day.meals.count) \(day.meals.count == 1 ? "entry" : "entries")")
    }
}

private enum HealthActivityViewState: Equatable {
    case disconnected
    case loading
    case ready(HealthActivitySummary)
    case unavailable
    case failed(String)
}

private struct DailyNutritionReviewSection: View {
    let day: Day
    let activity: HealthActivitySummary?
    let reminderEnabled: Bool
    let isEnablingReminder: Bool
    let reminderMessage: String?
    let enableReminder: () -> Void

    private let reviewer = DailyNutritionReviewService()

    var body: some View {
        if !day.meals.isEmpty {
            if DailyReviewAvailability.isAvailable(for: day.date),
               let review = reviewer.review(for: day, activity: activity) {
                DailyNutritionReviewCard(review: review)
            } else if Calendar.autoupdatingCurrent.isDateInToday(day.date) {
                EveningReviewPending(
                    reminderEnabled: reminderEnabled,
                    isEnabling: isEnablingReminder,
                    message: reminderMessage,
                    enable: enableReminder
                )
            }
        }
    }
}

private struct EveningReviewPending: View {
    let reminderEnabled: Bool
    let isEnabling: Bool
    let message: String?
    let enable: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Image(systemName: reminderEnabled ? "bell.badge.fill" : "moon.stars")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .frame(width: 38, height: 38)
                    .background(Color.lime.opacity(0.42), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Daily review · 10 PM")
                        .font(DiafitType.body.weight(.semibold))
                        .foregroundStyle(Color.ink)
                    Text("A brief review appears here after your day is logged.")
                        .font(DiafitType.caption)
                        .foregroundStyle(Color.quietInk)
                }
                Spacer(minLength: 4)
                if !reminderEnabled {
                    Button(action: enable) {
                        if isEnabling {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Remind me")
                                .font(DiafitType.caption.weight(.semibold))
                        }
                    }
                    .foregroundStyle(Color.ink)
                    .frame(minHeight: 44)
                    .disabled(isEnabling)
                    .accessibilityHint("Requests permission for a private daily notification at 10 PM")
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.ink)
                        .accessibilityLabel("Reminder enabled")
                }
            }
            if let message {
                Text(message)
                    .font(DiafitType.caption)
                    .foregroundStyle(Color.quietInk)
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("daily-review-pending")
    }
}

private struct DailyNutritionReviewCard: View {
    let review: DailyNutritionReview
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 11) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.ink)
                        .frame(width: 38, height: 38)
                        .background(Color.lime.opacity(0.55), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(review.title)
                            .font(DiafitType.title)
                            .foregroundStyle(Color.ink)
                        Text(review.overview)
                            .font(DiafitType.caption)
                            .foregroundStyle(Color.quietInk)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.quietInk)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(expanded ? "Collapses the daily review" : "Expands the daily review")

            if expanded {
                VStack(alignment: .leading, spacing: 15) {
                    ForEach(Array(review.observations.enumerated()), id: \.element.id) { index, observation in
                        HStack(alignment: .top, spacing: 11) {
                            Text("\(index + 1)")
                                .font(DiafitType.caption.weight(.bold))
                                .foregroundStyle(Color.ink)
                                .frame(width: 26, height: 26)
                                .background(Color.mist.opacity(0.9), in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(observation.title)
                                    .font(DiafitType.body.weight(.semibold))
                                    .foregroundStyle(Color.ink)
                                Text(observation.detail)
                                    .font(DiafitType.caption)
                                    .foregroundStyle(Color.quietInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    Text(review.closing)
                        .font(DiafitType.caption)
                        .foregroundStyle(Color.quietInk)
                        .padding(.top, 2)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(Color.mist.opacity(0.4), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.rule.opacity(0.78), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("daily-nutrition-review")
    }
}

private struct EnergyAndMovementSection: View {
    let intakeKilocalories: Int
    let state: HealthActivityViewState
    let connect: () -> Void
    let refresh: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 9) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.ink)
                    .frame(width: 28, height: 28)
                    .background(Color.lime.opacity(0.46), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("ENERGY & MOVEMENT")
                        .font(DiafitType.caption.weight(.bold))
                        .tracking(1.6)
                        .foregroundStyle(Color.quietInk)
                    Text("A quiet read on today’s balance")
                        .font(DiafitType.caption)
                        .foregroundStyle(Color.quietInk.opacity(0.84))
                }
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
        .padding(15)
        .background(Color.mist.opacity(0.34), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.rule.opacity(0.52), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var trailingAction: some View {
        switch state {
        case .disconnected:
            EmptyView()
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
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("TODAY'S INTAKE")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.7)
                    .foregroundStyle(Color.quietInk)
                Spacer(minLength: 8)
                if !day.meals.isEmpty {
                    Text(day.proteinTotalIsComplete ? "Known totals" : "Partial totals")
                        .font(DiafitType.caption.weight(.semibold))
                        .foregroundStyle(day.proteinTotalIsComplete ? Color.quietInk : Color.saffron)
                }
            }

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
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 17)
        .background(Color.surface.opacity(0.82), in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .stroke(Color.surfaceStroke.opacity(0.75), lineWidth: 1)
        }
        .overlay(alignment: .leading) {
            Capsule()
                .fill(Color.lime)
                .frame(width: 3, height: 33)
                .padding(.leading, 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Today’s nutrition intake")
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
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "fork.knife")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .frame(width: 36, height: 36)
                    .background(Color.lime.opacity(0.58), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("No meals logged yet")
                        .font(DiafitType.title)
                        .foregroundStyle(Color.ink)
                    Text("Start your day with one simple note or a photo.")
                        .font(DiafitType.body)
                        .foregroundStyle(Color.quietInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
        .padding(17)
        .background(Color.mist.opacity(0.3), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.rule.opacity(0.5), lineWidth: 1)
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
                            .fill(Color.ink.opacity(index == 1 ? 0.9 : 0.32))
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
                                .fill(Color.ink.opacity(index == phase ? 0.9 : 0.32))
                                .frame(width: 5, height: 5)
                                .offset(y: index == phase ? -2 : 0)
                        }
                    }
                }
            }
            Text(label)
                .font(DiafitType.caption)
                .foregroundStyle(Color.ink)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .background(Color.surface, in: Capsule())
        .overlay(Capsule().stroke(Color.surfaceStroke.opacity(0.72), lineWidth: 0.8))
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

                TextField(
                    text: $text,
                    prompt: Text("Tell me what you ate").foregroundStyle(Color.quietInk)
                ) {
                    EmptyView()
                }
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
        .background(Color.mist.opacity(0.92), in: Capsule())
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
