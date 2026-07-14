import SwiftUI

struct RootExperience: View {
    @EnvironmentObject private var store: DiaryStore
    @State private var selectedDayID: Day.ID
    @State private var atlasIsOpen = false
    @Namespace private var mealNamespace

    init() {
        _selectedDayID = State(initialValue: DiaryStore.preview.days.last?.id ?? UUID())
    }

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
                    .tag(day.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .accessibilityLabel("Daily diary")

            if atlasIsOpen, let day = store.day(id: selectedDayID) {
                MealAtlasView(
                    day: day,
                    isPresented: $atlasIsOpen,
                    mealNamespace: mealNamespace
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.985)),
                    removal: .opacity
                ))
                .zIndex(2)
            }
        }
        .animation(.spring(response: 0.52, dampingFraction: 0.86), value: atlasIsOpen)
    }
}

struct RootExperience_Previews: PreviewProvider {
    static var previews: some View {
        RootExperience()
            .environmentObject(DiaryStore.preview)
    }
}
