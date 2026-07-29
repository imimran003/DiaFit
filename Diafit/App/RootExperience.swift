import SwiftUI

struct RootExperience: View {
    @EnvironmentObject private var store: DiaryStore
    @State private var selectedSection: AppSection = .today
    @State private var selectedDayID: Day.ID?
    @State private var atlasIsOpen = false
    @Namespace private var mealNamespace

    var body: some View {
        ZStack {
            Color.paper.ignoresSafeArea()

            TabView(selection: $selectedSection) {
                todayExperience
                    .tag(AppSection.today)
                    .tabItem {
                        Label(AppSection.today.title, systemImage: AppSection.today.symbol)
                    }

                DiaryOverviewView()
                    .tag(AppSection.diary)
                    .tabItem {
                        Label(AppSection.diary.title, systemImage: AppSection.diary.symbol)
                    }

                InsightsOverviewView()
                    .tag(AppSection.insights)
                    .tabItem {
                        Label(AppSection.insights.title, systemImage: AppSection.insights.symbol)
                    }

                ProfileView()
                    .tag(AppSection.profile)
                    .tabItem {
                        Label(AppSection.profile.title, systemImage: AppSection.profile.symbol)
                    }

                SettingsView()
                    .tag(AppSection.settings)
                    .tabItem {
                        Label(AppSection.settings.title, systemImage: AppSection.settings.symbol)
                    }
            }
            .tint(Color.ink)
            .accessibilityLabel("Diafit sections")

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

            if selectedSection == .today, selectedDayID == nil {
                LaunchMark()
                    .transition(.opacity)
                    .zIndex(4)
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

    private var todayExperience: some View {
        ZStack {
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
        }
    }
}

private enum AppSection: Hashable {
    case today
    case diary
    case insights
    case profile
    case settings

    var title: String {
        switch self {
        case .today: return "Today"
        case .diary: return "Diary"
        case .insights: return "Insights"
        case .profile: return "Profile"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .today: return "sun.max"
        case .diary: return "book.pages"
        case .insights: return "chart.line.uptrend.xyaxis"
        case .profile: return "person"
        case .settings: return "gearshape"
        }
    }
}

private struct LaunchMark: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.ink)
                .frame(width: 56, height: 56)
                .background(Color.lime.opacity(0.72), in: Circle())
            Text("DIAFIT")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(2.2)
                .foregroundStyle(Color.ink)
        }
        .accessibilityHidden(true)
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
            .environmentObject(UserProfileStore())
    }
}
