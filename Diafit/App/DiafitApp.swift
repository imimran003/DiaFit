import SwiftUI

@main
struct DiafitApp: App {
    @StateObject private var store: DiaryStore
    @StateObject private var profileStore: UserProfileStore

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

        let profiles: UserProfileStore
        if usesTransientFixtures {
            profiles = UserProfileStore()
        } else if usesPersistentUITestDiary {
            let rawIdentifier = process.environment["DIAFIT_UI_TEST_DIARY_ID"] ?? UUID().uuidString
            let identifier = rawIdentifier.filter { $0.isLetter || $0.isNumber || $0 == "-" }
            profiles = UserProfileStore(
                persistence: FileUserProfilePersistence.live(fileName: "ui-test-profile-\(identifier).json")
            )
        } else {
            profiles = UserProfileStore(persistence: FileUserProfilePersistence.live())
        }
        _profileStore = StateObject(wrappedValue: profiles)
    }

    var body: some Scene {
        WindowGroup {
            RootExperience()
                .environmentObject(store)
                .environmentObject(profileStore)
                .environment(\.appDependencies, .local)
        }
    }
}
