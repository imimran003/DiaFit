import SwiftUI

struct DayThreadView: View {
    @EnvironmentObject private var store: DiaryStore
    @Environment(\.appDependencies) private var dependencies
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
    @FocusState private var composerFocused: Bool

    private var day: Day? { store.day(id: dayID) }

    var body: some View {
        Group {
            if let day {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 18) {
                            DayHeader(day: day, openAtlas: openAtlas, logGlucose: { showsGlucoseEntry = true }, openGlucoseHistory: { showsGlucoseHistory = true })
                                .padding(.bottom, 4)

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

        if let parsedGlucose = GlucoseNaturalLanguageParser().parse(note) {
            glucoseDraft = parsedGlucose
            store.append(ThreadItem(id: UUID(), kind: .agent(text: "I found a glucose reading. Check the unit and context before saving it.", tools: ["Needs confirmation"])), to: dayID)
            return
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
    let openAtlas: () -> Void
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

                Button(action: openAtlas) {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.ink)
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.7), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 1))
                }
                .buttonStyle(PressableStyle(pressedScale: 0.9))
                .accessibilityLabel("Open meal atlas")
            }

            DailyRhythm(day: day)
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

private struct DailyRhythm: View {
    let day: Day

    private var caloriesProgress: CGFloat {
        min(CGFloat(day.totalEnergy) / CGFloat(day.energyGoal), 1)
    }

    private var carbProgress: CGFloat {
        min(CGFloat(day.totalCarbs) / CGFloat(day.carbohydrateGoal), 1)
    }

    var body: some View {
        HStack(spacing: 10) {
            MetricTicket(value: "\(day.totalEnergy)", unit: "kcal", progress: caloriesProgress, accent: .ink)
            MetricTicket(value: "\(day.totalCarbs)g", unit: "carbs", progress: carbProgress, accent: .coral)
            Spacer(minLength: 0)
            Text("Swipe for days")
                .font(DiafitType.caption)
                .foregroundStyle(Color.quietInk.opacity(0.72))
                .fixedSize()
        }
    }
}

private struct MetricTicket: View {
    let value: String
    let unit: String
    let progress: CGFloat
    let accent: Color

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().stroke(Color.rule.opacity(0.68), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(accent, style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.system(size: 15, weight: .bold, design: .rounded))
                Text(unit).font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.quietInk)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.white.opacity(0.56), in: Capsule())
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

    private let suggestions = ["My usual breakfast", "I had salmon & rice", "Pasta for dinner"]

    var body: some View {
        VStack(spacing: 9) {
            if !isFocused.wrappedValue && text.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button(suggestion) { text = suggestion }
                                .font(DiafitType.caption)
                                .foregroundStyle(Color.ink)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(.white.opacity(0.75), in: Capsule())
                                .overlay(Capsule().stroke(Color.rule.opacity(0.55), lineWidth: 0.8))
                                .buttonStyle(PressableStyle())
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }

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
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.8), lineWidth: 1))
            .shadow(color: .black.opacity(0.09), radius: 20, y: 8)
            .padding(.horizontal, 20)
        }
        .padding(.top, 9)
        .padding(.bottom, 10)
        .background(Color.paper.opacity(0.82))
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
