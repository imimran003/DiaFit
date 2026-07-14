import SwiftUI

@main
struct DiafitApp: App {
    @State private var store = DiaryStore.preview

    var body: some Scene {
        WindowGroup {
            RootExperience()
                .environment(store)
                .preferredColorScheme(.light)
        }
    }
}
