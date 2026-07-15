import SwiftUI

struct RootExperience: View {
    @EnvironmentObject private var store: DiaryStore
    @State private var selectedDayID: Day.ID?
    @State private var atlasIsOpen = false
    @Namespace private var mealNamespace

    var body: some View {
        ZStack {
            Color.paper.ignoresSafeArea()

            TabView(selection: $selectedDayID) {
                ForEach(store.days) { day in
                    DayThreadView(
                        dayID: day.id,
                        isAtlasOpen: $atlasIsOpen,
                        mealNamespace: mealNamespace
                    )
                    .tag(Optional(day.id))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .accessibilityLabel("Daily diary")

            if atlasIsOpen, let day = activeDay {
                MealAtlasView(
                    day: day,
                    isPresented: $atlasIsOpen,
                    mealNamespace: mealNamespace
                )
                .transition(.atlasReveal)
                .zIndex(2)
            }

            if let persistenceIssue = store.persistenceIssue {
                VStack {
                    PersistenceIssueBanner(
                        message: persistenceIssue,
                        retry: store.retryPersistence
                    )
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .zIndex(3)
            }
        }
        .onAppear {
            selectedDayID = selectedDayID ?? store.days.last?.id
        }
        .animation(.spring(response: 0.52, dampingFraction: 0.86), value: atlasIsOpen)
    }

    private var activeDay: Day? {
        if let selectedDayID, let selected = store.day(id: selectedDayID) {
            return selected
        }
        return store.days.last
    }
}

private struct PersistenceIssueBanner: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.coral)
                .accessibilityHidden(true)
            Text(message)
                .font(DiafitType.caption)
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("Retry", action: retry)
                .font(DiafitType.caption.weight(.semibold))
                .foregroundStyle(Color.ink)
                .frame(minWidth: 44, minHeight: 44)
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(Color.paper, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.coral.opacity(0.5), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Diary storage problem. \(message)")
    }
}

struct RootExperience_Previews: PreviewProvider {
    static var previews: some View {
        RootExperience()
            .environmentObject(DiaryStore.preview)
    }
}
