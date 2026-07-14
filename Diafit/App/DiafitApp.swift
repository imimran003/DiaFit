import SwiftUI

@main
struct DiafitApp: App {
    @StateObject private var store = DiaryStore(days: SampleDiary.days)

    var body: some Scene {
        WindowGroup {
            RootExperience()
                .environmentObject(store)
                .environment(\.appDependencies, .local)
                .preferredColorScheme(.light)
        }
    }
}
