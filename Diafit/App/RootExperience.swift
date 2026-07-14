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
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.985)),
                    removal: .opacity
                ))
                .zIndex(2)
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

struct RootExperience_Previews: PreviewProvider {
    static var previews: some View {
        RootExperience()
            .environmentObject(DiaryStore.preview)
    }
}
