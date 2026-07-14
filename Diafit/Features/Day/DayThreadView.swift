import SwiftUI

struct DayThreadView: View {
    @EnvironmentObject private var store: DiaryStore
    let dayID: Day.ID
    @Binding var isAtlasOpen: Bool
    let mealNamespace: Namespace.ID

    @State private var draft = ""
    @State private var isThinking = false
    @State private var scrollTarget: UUID?
    @FocusState private var composerFocused: Bool

    private var day: Day? { store.day(id: dayID) }

    var body: some View {
        Group {
            if let day {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 18) {
                            DayHeader(day: day, openAtlas: openAtlas)
                                .padding(.bottom, 4)

                            ForEach(day.messages) { item in
                                ThreadItemView(
                                    item: item,
                                    isAtlasOpen: $isAtlasOpen,
                                    mealNamespace: mealNamespace
                                )
                                .id(item.id)
                            }

                            if isThinking {
                                ThinkingBubble()
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
                            submit: submit
                        )
                    }
                    .onAppear { scrollToTail(proxy, animated: false) }
                    .onChange(of: day.messages.count) { _, _ in
                        scrollToTail(proxy)
                    }
                    .onChange(of: isThinking) { _, _ in
                        scrollToTail(proxy)
                    }
                }
            }
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
        isThinking = true

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(720))
            let meal = ConversationCoordinator.nutrition.estimate(for: note, at: .now)
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
            isThinking = false
        }
    }
}

private struct DayHeader: View {
    let day: Day
    let openAtlas: () -> Void

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
    var body: some View {
        HStack(spacing: 9) {
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
            Text("Looking that up")
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
                TextField("Tell me what you ate", text: $text, axis: .vertical)
                    .font(DiafitType.body)
                    .foregroundStyle(Color.ink)
                    .focused(isFocused)
                    .lineLimit(1...4)
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
