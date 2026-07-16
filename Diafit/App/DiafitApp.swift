import SwiftUI

@main
struct DiafitApp: App {
    @StateObject private var store: DiaryStore

    init() {
        let process = ProcessInfo.processInfo
        let usesPersistentUITestDiary = process.arguments.contains("UITestPersistentDiary")
        let usesTransientFixtures = process.arguments.contains("UITestMode") && !usesPersistentUITestDiary
        let diary: DiaryStore
        if usesTransientFixtures {
            diary = DiaryStore(days: RuntimeDiaryDefaults.days())
        } else if usesPersistentUITestDiary {
            let rawIdentifier = process.environment["DIAFIT_UI_TEST_DIARY_ID"] ?? UUID().uuidString
            let identifier = rawIdentifier.filter { $0.isLetter || $0.isNumber || $0 == "-" }
            diary = DiaryStore(
                seedDays: RuntimeDiaryDefaults.days(),
                persistence: FileDiaryPersistence.live(fileName: "ui-test-\(identifier).json")
            )
        } else {
            diary = DiaryStore(seedDays: RuntimeDiaryDefaults.days(), persistence: FileDiaryPersistence.live())
        }
        _store = StateObject(wrappedValue: diary)
    }

    var body: some Scene {
        WindowGroup {
            RootExperience()
                .environmentObject(store)
                .environment(\.appDependencies, .local)
        }
    }
}
