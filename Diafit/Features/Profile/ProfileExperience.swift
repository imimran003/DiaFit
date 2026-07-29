import SwiftUI
import PhotosUI
import UIKit

struct ProfileView: View {
    @EnvironmentObject private var profileStore: UserProfileStore
    @State private var showsEditor = false
    @State private var saveMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    ScreenTitle(
                        eyebrow: "YOUR DIAFIT",
                        title: "Profile",
                        detail: "The details that make your diary feel personal."
                    )

                    ProfileIdentityHeader(
                        profile: profileStore.profile,
                        edit: { showsEditor = true }
                    )

                    if let issue = profileStore.persistenceIssue {
                        InlineNotice(text: issue, symbol: "externaldrive.badge.exclamationmark")
                    } else if let saveMessage {
                        InlineNotice(text: saveMessage, symbol: "checkmark")
                    }

                    ProfileInformationSection(
                        profile: profileStore.profile,
                        measurementSystem: profileStore.preferences.measurementSystem
                    )
                    ProfileHealthSection(profile: profileStore.profile)
                    ProfileGoalSection(profile: profileStore.profile)

                    VStack(alignment: .leading, spacing: 7) {
                        Text("PRIVATE BY DESIGN")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(1.4)
                            .foregroundStyle(Color.quietInk)
                        Text("Your profile stays on this device. Diafit uses only the details needed to personalize your experience.")
                            .font(DiafitType.caption)
                            .foregroundStyle(Color.quietInk)
                            .lineSpacing(3)
                    }
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
            }
            .background(Color.paper)
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showsEditor) {
            EditProfileView(profile: profileStore.profile) { profile in
                switch profileStore.save(profile: profile) {
                case .success:
                    saveMessage = "Profile updated"
                    showsEditor = false
                case .failure(let error):
                    saveMessage = error.localizedDescription
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
}

private struct ProfileIdentityHeader: View {
    let profile: UserProfile
    let edit: () -> Void

    var body: some View {
        HStack(spacing: 17) {
            ProfileAvatar(profile: profile, size: 82)

            VStack(alignment: .leading, spacing: 5) {
                Text(profile.preferredName.isEmpty ? "Set up your profile" : profile.preferredName)
                    .font(DiafitType.title)
                    .foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(identityDetail)
                    .font(DiafitType.caption)
                    .foregroundStyle(Color.quietInk)
            }

            Spacer(minLength: 8)

            Button("Edit", action: edit)
                .font(DiafitType.caption.weight(.semibold))
                .foregroundStyle(Color.ink)
                .frame(minWidth: 58, minHeight: 44)
                .diafitGlass(radius: 22, interactive: true)
                .buttonStyle(PressableStyle(pressedScale: 0.94))
                .accessibilityHint("Opens your editable profile details")
        }
        .padding(18)
        .diafitGlass(radius: 30)
        .accessibilityElement(children: .contain)
    }

    private var identityDetail: String {
        if let age = profile.age() {
            return "\(age) years · \(profile.activityLevel.displayName)"
        }
        return profile.isEmpty
            ? "Add a few details when you’re ready."
            : profile.activityLevel.displayName
    }
}

private struct ProfileInformationSection: View {
    let profile: UserProfile
    let measurementSystem: MeasurementSystem

    var body: some View {
        ProfileSection(title: "Personal") {
            ProfileValueRow(label: "Name", value: profile.preferredName.ifBlank("Not provided"))
            ProfileValueRow(label: "Age", value: profile.age().map { "\($0) years" } ?? "Not provided")
            ProfileValueRow(label: "Sex", value: profile.sex.displayName)
            ProfileValueRow(label: "Height", value: profile.heightCentimeters.map(heightDescription) ?? "Not provided")
            ProfileValueRow(label: "Weight", value: profile.weightKilograms.map(weightDescription) ?? "Not provided")
        }
    }

    private func heightDescription(_ centimeters: Double) -> String {
        guard measurementSystem == .imperial else {
            return "\(centimeters.formatted(.number.precision(.fractionLength(0...1)))) cm"
        }
        let totalInches = Int((centimeters / 2.54).rounded())
        return "\(totalInches / 12) ft \(totalInches % 12) in"
    }

    private func weightDescription(_ kilograms: Double) -> String {
        guard measurementSystem == .imperial else {
            return "\(kilograms.formatted(.number.precision(.fractionLength(0...1)))) kg"
        }
        let pounds = kilograms * 2.204_622_621_8
        return "\(pounds.formatted(.number.precision(.fractionLength(0...1)))) lb"
    }
}

private struct ProfileHealthSection: View {
    let profile: UserProfile

    var body: some View {
        ProfileSection(title: "Health & food") {
            ProfileValueRow(label: "Diabetes context", value: profile.diabetesContext.displayName)
            ProfileValueRow(label: "Activity", value: profile.activityLevel.displayName)
            ProfileValueRow(label: "Food pattern", value: profile.dietaryPattern.displayName)
            ProfileValueRow(
                label: "Allergies",
                value: profile.allergies.isEmpty ? "None recorded" : profile.allergies.joined(separator: ", ")
            )
        }
    }
}

private struct ProfileGoalSection: View {
    let profile: UserProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel("Goals")
            HStack(spacing: 10) {
                GoalValue(value: profile.calorieGoal.map(String.init) ?? "—", unit: "kcal", label: "Calories")
                GoalValue(value: profile.carbohydrateGoalGrams.map(String.init) ?? "—", unit: "g", label: "Carbs")
                GoalValue(value: profile.proteinGoalGrams.map(String.init) ?? "—", unit: "g", label: "Protein")
            }
            if let stepGoal = profile.stepGoal {
                ProfileValueRow(label: "Daily movement", value: "\(stepGoal.formatted()) steps")
            }
        }
    }
}

private struct GoalValue: View {
    let value: String
    let unit: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(DiafitType.caption)
                .foregroundStyle(Color.quietInk)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(DiafitType.metric)
                    .foregroundStyle(Color.ink)
                Text(unit)
                    .font(DiafitType.caption)
                    .foregroundStyle(Color.quietInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value) \(unit)")
    }
}

struct SettingsView: View {
    @EnvironmentObject private var profileStore: UserProfileStore
    @Environment(\.appDependencies) private var dependencies
    @Environment(\.openURL) private var openURL
    @State private var reminderEnabled = false
    @State private var reminderStatus: String?
    @State private var showsPrivacy = false
    @State private var confirmsReset = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    ScreenTitle(
                        eyebrow: "DIAFIT",
                        title: "Settings",
                        detail: "A few clear choices. Nothing hidden."
                    )

                    SettingsSection(title: "Units") {
                        SettingsPickerRow(
                            label: "Measurements",
                            symbol: "ruler",
                            selection: measurementSystem
                        )
                        SettingsPickerRow(
                            label: "Glucose",
                            symbol: "drop",
                            selection: glucoseUnit
                        )
                    }

                    SettingsSection(title: "Experience") {
                        Toggle(isOn: hapticsEnabled) {
                            SettingsRowLabel(
                                title: "Gentle haptics",
                                detail: "Only for meaningful actions",
                                symbol: "waveform"
                            )
                        }
                        .tint(Color.lime)
                        .frame(minHeight: 52)
                    }

                    SettingsSection(title: "Health & reminders") {
                        Button {
                            enableReminder()
                        } label: {
                            SettingsNavigationRow(
                                title: reminderEnabled ? "10 PM review enabled" : "Enable 10 PM review",
                                detail: reminderStatus ?? "A quiet reminder after your day is logged",
                                symbol: reminderEnabled ? "bell.badge.fill" : "bell"
                            )
                        }
                        .buttonStyle(PressableStyle())

                        Button {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            openURL(url)
                        } label: {
                            SettingsNavigationRow(
                                title: "Device permissions",
                                detail: "Apple Health, photos, camera, and notifications",
                                symbol: "hand.raised"
                            )
                        }
                        .buttonStyle(PressableStyle())
                    }

                    SettingsSection(title: "Privacy & data") {
                        Button { showsPrivacy = true } label: {
                            SettingsNavigationRow(
                                title: "How your data is handled",
                                detail: "Local storage and your control",
                                symbol: "lock"
                            )
                        }
                        .buttonStyle(PressableStyle())

                        Button(role: .destructive) { confirmsReset = true } label: {
                            SettingsNavigationRow(
                                title: "Reset profile",
                                detail: "Meals, glucose, and activity stay untouched",
                                symbol: "person.crop.circle.badge.xmark",
                                tint: .coral
                            )
                        }
                        .buttonStyle(PressableStyle())
                    }

                    Text("Diafit 1.0")
                        .font(DiafitType.caption)
                        .foregroundStyle(Color.quietInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
            }
            .background(Color.paper)
            .navigationBarHidden(true)
        }
        .task {
            reminderEnabled = await dependencies.dailyReviewReminder.isEnabled()
        }
        .sheet(isPresented: $showsPrivacy) {
            PrivacyDetailsView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .alert("Reset your profile?", isPresented: $confirmsReset) {
            Button("Reset profile", role: .destructive) {
                _ = profileStore.resetProfile()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your personal details and photo will be cleared. Logged meals, glucose readings, and Apple Health data are not deleted.")
        }
    }

    private var measurementSystem: Binding<MeasurementSystem> {
        Binding(
            get: { profileStore.preferences.measurementSystem },
            set: { value in
                var preferences = profileStore.preferences
                preferences.measurementSystem = value
                _ = profileStore.updatePreferences(preferences)
            }
        )
    }

    private var glucoseUnit: Binding<GlucoseUnit> {
        Binding(
            get: { profileStore.preferences.preferredGlucoseUnit },
            set: { value in
                var preferences = profileStore.preferences
                preferences.preferredGlucoseUnit = value
                if case .success = profileStore.updatePreferences(preferences) {
                    UserDefaults.standard.set(value.rawValue, forKey: "diafit.glucose.preferredUnit")
                }
            }
        )
    }

    private var hapticsEnabled: Binding<Bool> {
        Binding(
            get: { profileStore.preferences.hapticsEnabled },
            set: { value in
                var preferences = profileStore.preferences
                preferences.hapticsEnabled = value
                _ = profileStore.updatePreferences(preferences)
            }
        )
    }

    private func enableReminder() {
        guard !reminderEnabled else {
            reminderStatus = "Your daily review reminder is active."
            return
        }
        Task { @MainActor in
            do {
                reminderEnabled = try await dependencies.dailyReviewReminder.enable(hour: 22)
                reminderStatus = reminderEnabled
                    ? "Your daily review will be ready at 10 PM."
                    : "Notifications are off. You can enable them in device settings."
            } catch {
                reminderStatus = "The reminder could not be enabled. Try again."
            }
        }
    }
}

struct DiaryOverviewView: View {
    @EnvironmentObject private var store: DiaryStore

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    ScreenTitle(
                        eyebrow: "YOUR DAYS",
                        title: "Diary",
                        detail: "Meals and readings, in the order they happened."
                    )

                    ForEach(store.days.reversed()) { day in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(day.date.formatted(.dateTime.weekday(.wide)))
                                        .font(DiafitType.title)
                                        .foregroundStyle(Color.ink)
                                    Text(day.date.formatted(.dateTime.month(.wide).day()))
                                        .font(DiafitType.caption)
                                        .foregroundStyle(Color.quietInk)
                                }
                                Spacer()
                                Text("\(day.meals.count) \(day.meals.count == 1 ? "meal" : "meals")")
                                    .font(DiafitType.caption)
                                    .foregroundStyle(Color.quietInk)
                            }

                            if day.meals.isEmpty {
                                Text("No meals logged")
                                    .font(DiafitType.body)
                                    .foregroundStyle(Color.quietInk)
                                    .padding(.vertical, 7)
                            } else {
                                ForEach(day.meals.sorted(by: { $0.time < $1.time })) { meal in
                                    HStack(spacing: 12) {
                                        FoodArtwork(meal: meal, treatment: .thread)
                                            .frame(width: 58, height: 58)
                                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(meal.title)
                                                .font(DiafitType.body.weight(.semibold))
                                                .foregroundStyle(Color.ink)
                                                .lineLimit(1)
                                            Text("\(meal.period.displayName) · \(meal.energy) kcal")
                                                .font(DiafitType.caption)
                                                .foregroundStyle(Color.quietInk)
                                        }
                                        Spacer()
                                        Text(meal.time.formatted(.dateTime.hour().minute()))
                                            .font(DiafitType.caption)
                                            .foregroundStyle(Color.quietInk)
                                    }
                                    .accessibilityElement(children: .combine)
                                }
                            }
                        }
                        .padding(.bottom, 18)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Color.rule.opacity(0.65)).frame(height: 0.7)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .background(Color.paper)
            .navigationBarHidden(true)
        }
    }
}

struct InsightsOverviewView: View {
    @EnvironmentObject private var store: DiaryStore

    private var recordedDays: [Day] {
        Array(store.days.filter { !$0.meals.isEmpty }.suffix(7))
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    ScreenTitle(
                        eyebrow: "RECENT PATTERNS",
                        title: "Insights",
                        detail: "Simple facts from what you have actually logged."
                    )

                    if recordedDays.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("No patterns yet")
                                .font(DiafitType.title)
                                .foregroundStyle(Color.ink)
                            Text("Insights will appear after you confirm a few meals.")
                                .font(DiafitType.body)
                                .foregroundStyle(Color.quietInk)
                        }
                        .padding(20)
                        .diafitGlass(radius: 28)
                    } else {
                        HStack(spacing: 10) {
                            InsightMetric(label: "Logged days", value: "\(recordedDays.count)", unit: "")
                            InsightMetric(label: "Meals", value: "\(recordedDays.reduce(0) { $0 + $1.meals.count })", unit: "")
                            InsightMetric(label: "Avg carbs", value: "\(averageCarbohydrates)", unit: "g")
                        }

                        ProfileSection(title: "Seven-day view") {
                            ProfileValueRow(label: "Average energy", value: "\(averageEnergy) kcal")
                            ProfileValueRow(label: "Average protein", value: "\(averageProtein) g")
                            ProfileValueRow(label: "Glucose readings", value: "\(recordedDays.reduce(0) { $0 + $1.glucoseReadings.count })")
                        }

                        Text("These are summaries of recorded entries, not medical conclusions.")
                            .font(DiafitType.caption)
                            .foregroundStyle(Color.quietInk)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
            }
            .background(Color.paper)
            .navigationBarHidden(true)
        }
    }

    private var averageEnergy: Int {
        recordedDays.isEmpty ? 0 : recordedDays.reduce(0) { $0 + $1.totalEnergy } / recordedDays.count
    }

    private var averageCarbohydrates: Int {
        recordedDays.isEmpty ? 0 : recordedDays.reduce(0) { $0 + $1.totalCarbs } / recordedDays.count
    }

    private var averageProtein: Int {
        recordedDays.isEmpty ? 0 : recordedDays.reduce(0) { $0 + $1.totalProtein } / recordedDays.count
    }
}

private struct InsightMetric: View {
    let label: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(DiafitType.caption)
                .foregroundStyle(Color.quietInk)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(DiafitType.metric)
                    .foregroundStyle(Color.ink)
                if !unit.isEmpty {
                    Text(unit)
                        .font(DiafitType.caption)
                        .foregroundStyle(Color.quietInk)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ProfileEditDraft
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var errorMessage: String?
    let onSave: (UserProfile) -> Void

    init(profile: UserProfile, onSave: @escaping (UserProfile) -> Void) {
        _draft = State(initialValue: ProfileEditDraft(profile: profile))
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(spacing: 10) {
                        ProfileAvatar(profile: draft.previewProfile, size: 96)
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Text(draft.avatarJPEGData == nil ? "Add photo" : "Change photo")
                                .font(DiafitType.caption.weight(.semibold))
                                .foregroundStyle(Color.ink)
                                .frame(minWidth: 100, minHeight: 44)
                                .diafitGlass(radius: 22, interactive: true)
                        }
                        if draft.avatarJPEGData != nil {
                            Button("Remove photo") { draft.avatarJPEGData = nil }
                                .font(DiafitType.caption)
                                .foregroundStyle(Color.quietInk)
                                .frame(minHeight: 44)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    EditSection(title: "Personal") {
                        EditTextField(label: "Preferred name", text: $draft.preferredName, keyboard: .default)

                        Toggle("Add date of birth", isOn: $draft.includesDateOfBirth)
                            .font(DiafitType.body)
                            .tint(Color.lime)
                            .frame(minHeight: 50)
                        if draft.includesDateOfBirth {
                            DatePicker(
                                "Date of birth",
                                selection: $draft.dateOfBirth,
                                in: ...Date.now,
                                displayedComponents: .date
                            )
                            .font(DiafitType.body)
                            .datePickerStyle(.compact)
                            .frame(minHeight: 50)
                        }

                        EditPicker(label: "Sex", selection: $draft.sex)
                        EditTextField(label: "Gender identity (optional)", text: $draft.genderIdentity, keyboard: .default)
                        EditTextField(label: "Height in centimetres", text: $draft.height, keyboard: .decimalPad)
                        EditTextField(label: "Weight in kilograms", text: $draft.weight, keyboard: .decimalPad)
                    }

                    EditSection(title: "Health & food") {
                        EditPicker(label: "Diabetes context", selection: $draft.diabetesContext)
                        EditPicker(label: "Activity level", selection: $draft.activityLevel)
                        EditPicker(label: "Food pattern", selection: $draft.dietaryPattern)
                        EditTextField(
                            label: "Allergies, separated by commas",
                            text: $draft.allergies,
                            keyboard: .default
                        )
                    }

                    EditSection(title: "Daily goals") {
                        EditTextField(label: "Calories", text: $draft.calorieGoal, keyboard: .numberPad)
                        EditTextField(label: "Carbohydrates in grams", text: $draft.carbohydrateGoal, keyboard: .numberPad)
                        EditTextField(label: "Protein in grams", text: $draft.proteinGoal, keyboard: .numberPad)
                        EditTextField(label: "Steps", text: $draft.stepGoal, keyboard: .numberPad)
                    }

                    if let errorMessage {
                        InlineNotice(text: errorMessage, symbol: "exclamationmark.circle")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.paper)
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!draft.canSave)
                }
            }
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                Task { await loadAvatar(item) }
            }
        }
    }

    private func save() {
        guard let profile = draft.makeProfile() else {
            errorMessage = "Check the highlighted numbers before saving."
            return
        }
        switch UserProfileValidator().validate(profile) {
        case .success:
            errorMessage = nil
            onSave(profile)
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func loadAvatar(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            errorMessage = "That photo could not be read."
            return
        }
        let size = CGSize(width: 320, height: 320)
        let renderer = UIGraphicsImageRenderer(size: size)
        let avatar = renderer.image { _ in
            let scale = max(size.width / image.size.width, size.height / image.size.height)
            let drawingSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let origin = CGPoint(
                x: (size.width - drawingSize.width) / 2,
                y: (size.height - drawingSize.height) / 2
            )
            image.draw(in: CGRect(origin: origin, size: drawingSize))
        }
        draft.avatarJPEGData = avatar.jpegData(compressionQuality: 0.78)
        errorMessage = nil
    }
}

private struct ProfileEditDraft {
    var preferredName: String
    var includesDateOfBirth: Bool
    var dateOfBirth: Date
    var sex: ProfileSex
    var genderIdentity: String
    var height: String
    var weight: String
    var diabetesContext: DiabetesContext
    var activityLevel: ProfileActivityLevel
    var dietaryPattern: DietaryPattern
    var allergies: String
    var calorieGoal: String
    var carbohydrateGoal: String
    var proteinGoal: String
    var stepGoal: String
    var avatarJPEGData: Data?
    private let original: UserProfile

    init(profile: UserProfile) {
        original = profile
        preferredName = profile.preferredName
        includesDateOfBirth = profile.dateOfBirth != nil
        dateOfBirth = profile.dateOfBirth
            ?? Calendar.current.date(from: DateComponents(year: 1990, month: 1, day: 1))
            ?? .now
        sex = profile.sex
        genderIdentity = profile.genderIdentity ?? ""
        height = Self.decimalString(profile.heightCentimeters)
        weight = Self.decimalString(profile.weightKilograms)
        diabetesContext = profile.diabetesContext
        activityLevel = profile.activityLevel
        dietaryPattern = profile.dietaryPattern
        allergies = profile.allergies.joined(separator: ", ")
        calorieGoal = profile.calorieGoal.map(String.init) ?? ""
        carbohydrateGoal = profile.carbohydrateGoalGrams.map(String.init) ?? ""
        proteinGoal = profile.proteinGoalGrams.map(String.init) ?? ""
        stepGoal = profile.stepGoal.map(String.init) ?? ""
        avatarJPEGData = profile.avatarJPEGData
    }

    var previewProfile: UserProfile {
        var value = original
        value.preferredName = preferredName
        value.avatarJPEGData = avatarJPEGData
        return value
    }

    var canSave: Bool {
        makeProfile() != nil && !preferredName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func makeProfile() -> UserProfile? {
        guard let heightValue = Self.optionalDouble(height),
              let weightValue = Self.optionalDouble(weight),
              let calorieValue = Self.optionalInt(calorieGoal),
              let carbohydrateValue = Self.optionalInt(carbohydrateGoal),
              let proteinValue = Self.optionalInt(proteinGoal),
              let stepValue = Self.optionalInt(stepGoal) else { return nil }

        var value = original
        value.preferredName = preferredName
        value.dateOfBirth = includesDateOfBirth ? dateOfBirth : nil
        value.sex = sex
        value.genderIdentity = genderIdentity
        value.heightCentimeters = heightValue
        value.weightKilograms = weightValue
        value.diabetesContext = diabetesContext
        value.activityLevel = activityLevel
        value.dietaryPattern = dietaryPattern
        value.allergies = allergies.split(separator: ",").map(String.init)
        value.calorieGoal = calorieValue
        value.carbohydrateGoalGrams = carbohydrateValue
        value.proteinGoalGrams = proteinValue
        value.stepGoal = stepValue
        value.avatarJPEGData = avatarJPEGData
        return value
    }

    private static func decimalString(_ value: Double?) -> String {
        value?.formatted(.number.precision(.fractionLength(0...1))) ?? ""
    }

    private static func optionalDouble(_ value: String) -> Double?? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .some(nil) }
        return Double(trimmed.replacingOccurrences(of: ",", with: ".")).map(Optional.some)
    }

    private static func optionalInt(_ value: String) -> Int?? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .some(nil) }
        return Int(trimmed).map(Optional.some)
    }
}

private struct ProfileAvatar: View {
    let profile: UserProfile
    let size: CGFloat

    var body: some View {
        Group {
            if let data = profile.avatarJPEGData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(profile.initials)
                    .font(.system(size: size * 0.27, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.ink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.lime.opacity(0.64))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white.opacity(0.72), lineWidth: 1))
        .accessibilityLabel(profile.avatarJPEGData == nil ? "Profile initials \(profile.initials)" : "Profile photo")
    }
}

private struct ScreenTitle: View {
    let eyebrow: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(eyebrow)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(Color.quietInk)
            Text(title)
                .font(DiafitType.display)
                .foregroundStyle(Color.ink)
            Text(detail)
                .font(DiafitType.body)
                .foregroundStyle(Color.quietInk)
                .lineSpacing(3)
        }
    }
}

private struct SectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .tracking(1.5)
            .foregroundStyle(Color.quietInk)
    }
}

private struct ProfileSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(title)
                .padding(.bottom, 7)
            content
        }
    }
}

private struct ProfileValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            Text(label)
                .font(DiafitType.body)
                .foregroundStyle(Color.quietInk)
            Spacer()
            Text(value)
                .font(DiafitType.body.weight(.semibold))
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.rule.opacity(0.55)).frame(height: 0.7)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(title)
                .padding(.bottom, 7)
            content
        }
    }
}

private struct SettingsPickerRow<Value: Hashable & CaseIterable>: View where Value.AllCases: RandomAccessCollection {
    let label: String
    let symbol: String
    @Binding var selection: Value

    init(label: String, symbol: String, selection: Binding<Value>) {
        self.label = label
        self.symbol = symbol
        _selection = selection
    }

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.ink)
                .frame(width: 30)
            Text(label)
                .font(DiafitType.body)
                .foregroundStyle(Color.ink)
            Spacer()
            Picker(label, selection: $selection) {
                ForEach(Array(Value.allCases), id: \.self) { value in
                    Text(displayName(value)).tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(Color.quietInk)
        }
        .frame(minHeight: 54)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.rule.opacity(0.55)).frame(height: 0.7)
        }
    }

    private func displayName(_ value: Value) -> String {
        if let value = value as? MeasurementSystem { return value.displayName }
        if let value = value as? GlucoseUnit { return value.shortName }
        return String(describing: value)
    }
}

private struct SettingsRowLabel: View {
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(DiafitType.body).foregroundStyle(Color.ink)
                Text(detail).font(DiafitType.caption).foregroundStyle(Color.quietInk)
            }
        }
    }
}

private struct SettingsNavigationRow: View {
    let title: String
    let detail: String
    let symbol: String
    var tint: Color = .ink

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(DiafitType.body).foregroundStyle(tint)
                Text(detail).font(DiafitType.caption).foregroundStyle(Color.quietInk)
                    .multilineTextAlignment(.leading)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.quietInk)
        }
        .frame(minHeight: 62)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.rule.opacity(0.55)).frame(height: 0.7)
        }
    }
}

private struct EditSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(title).padding(.bottom, 7)
            content
        }
    }
}

private struct EditTextField: View {
    let label: String
    @Binding var text: String
    let keyboard: UIKeyboardType

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(DiafitType.caption)
                .foregroundStyle(Color.quietInk)
            TextField("Not provided", text: $text)
                .font(DiafitType.body)
                .foregroundStyle(Color.ink)
                .keyboardType(keyboard)
                .textInputAutocapitalization(keyboard == .default ? .words : .never)
                .frame(minHeight: 38)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.rule.opacity(0.55)).frame(height: 0.7)
        }
    }
}

private struct EditPicker<Value: Hashable & CaseIterable>: View where Value.AllCases: RandomAccessCollection {
    let label: String
    @Binding var selection: Value

    var body: some View {
        HStack {
            Text(label)
                .font(DiafitType.body)
                .foregroundStyle(Color.ink)
            Spacer()
            Picker(label, selection: $selection) {
                ForEach(Array(Value.allCases), id: \.self) { value in
                    Text(displayName(value)).tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(Color.quietInk)
        }
        .frame(minHeight: 52)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.rule.opacity(0.55)).frame(height: 0.7)
        }
    }

    private func displayName(_ value: Value) -> String {
        if let value = value as? ProfileSex { return value.displayName }
        if let value = value as? DiabetesContext { return value.displayName }
        if let value = value as? ProfileActivityLevel { return value.displayName }
        if let value = value as? DietaryPattern { return value.displayName }
        return String(describing: value)
    }
}

private struct InlineNotice: View {
    let text: String
    let symbol: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(DiafitType.caption)
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.mist.opacity(0.62), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .accessibilityElement(children: .combine)
    }
}

private struct PrivacyDetailsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    ScreenTitle(
                        eyebrow: "PRIVACY",
                        title: "Your data is yours",
                        detail: "Diafit stores only what is needed for your diary and profile."
                    )
                    PrivacyPoint(
                        title: "Stored on this device",
                        detail: "Your profile, meals, and glucose readings use protected local storage.",
                        symbol: "iphone"
                    )
                    PrivacyPoint(
                        title: "Photos are your choice",
                        detail: "A meal photo is sent only when you explicitly choose AI recognition.",
                        symbol: "photo"
                    )
                    PrivacyPoint(
                        title: "You stay in control",
                        detail: "You can edit or delete readings, meals, and your profile.",
                        symbol: "hand.raised"
                    )
                }
                .padding(20)
            }
            .background(Color.paper)
            .navigationTitle("Privacy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct PrivacyPoint: View {
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.ink)
                .frame(width: 42, height: 42)
                .diafitGlass(radius: 21)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(DiafitType.title).foregroundStyle(Color.ink)
                Text(detail).font(DiafitType.body).foregroundStyle(Color.quietInk).lineSpacing(3)
            }
        }
    }
}

private extension String {
    func ifBlank(_ fallback: String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : self
    }
}

private extension View {
    @ViewBuilder
    func diafitGlass(radius: CGFloat, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(
                interactive ? Glass.regular.interactive() : Glass.regular,
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
        } else {
            background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(.white.opacity(0.62), lineWidth: 0.8)
                }
        }
    }
}
