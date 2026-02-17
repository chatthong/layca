import SwiftUI

enum SettingsMicrophonePermissionState: Sendable {
    case granted
    case undetermined
    case denied
    case unknown
}

private enum SettingsStep: Hashable {
    case credits
    case languageFocus
    case languageRegion(LanguageRegion)
    case advancedZone
    case cloudAndPurchases
    case microphoneAccess
}

struct SettingsTabView: View {
    let totalHours: Double
    let usedHours: Double

    @Binding var selectedLanguageCodes: Set<String>
    @Binding var languageSearchText: String

    let filteredFocusLanguages: [FocusLanguage]
    let groupedFocusLanguages: [LanguageRegionGroup]

    @Binding var isICloudSyncEnabled: Bool
    @Binding var whisperCoreMLEncoderEnabled: Bool
    @Binding var whisperGGMLGPUDecodeEnabled: Bool
    @Binding var whisperModelProfile: WhisperModelProfile
    @Binding var mainTimerDisplayStyle: MainTimerDisplayStyle
    let whisperCoreMLEncoderRecommendationText: String
    let whisperGGMLGPUDecodeRecommendationText: String
    let whisperModelRecommendationText: String
    let isRestoringPurchases: Bool
    let restoreStatusMessage: String?

    let onToggleLanguage: (String) -> Void
    let onRestorePurchases: () -> Void

    var body: some View {
        SettingsSheetFlowView(
            totalHours: totalHours,
            usedHours: usedHours,
            selectedLanguageCodes: $selectedLanguageCodes,
            languageSearchText: $languageSearchText,
            filteredFocusLanguages: filteredFocusLanguages,
            groupedFocusLanguages: groupedFocusLanguages,
            isICloudSyncEnabled: $isICloudSyncEnabled,
            whisperCoreMLEncoderEnabled: $whisperCoreMLEncoderEnabled,
            whisperGGMLGPUDecodeEnabled: $whisperGGMLGPUDecodeEnabled,
            whisperModelProfile: $whisperModelProfile,
            mainTimerDisplayStyle: $mainTimerDisplayStyle,
            whisperCoreMLEncoderRecommendationText: whisperCoreMLEncoderRecommendationText,
            whisperGGMLGPUDecodeRecommendationText: whisperGGMLGPUDecodeRecommendationText,
            whisperModelRecommendationText: whisperModelRecommendationText,
            isRestoringPurchases: isRestoringPurchases,
            restoreStatusMessage: restoreStatusMessage,
            onToggleLanguage: onToggleLanguage,
            onRestorePurchases: onRestorePurchases,
            showsMicrophoneMenu: false,
            microphonePermissionState: .unknown,
            onRequestMicrophoneAccess: {},
            onOpenMicrophoneSettings: {}
        )
    }
}

struct SettingsSheetFlowView: View {
    let totalHours: Double
    let usedHours: Double

    @Binding var selectedLanguageCodes: Set<String>
    @Binding var languageSearchText: String

    let filteredFocusLanguages: [FocusLanguage]
    let groupedFocusLanguages: [LanguageRegionGroup]

    @Binding var isICloudSyncEnabled: Bool
    @Binding var whisperCoreMLEncoderEnabled: Bool
    @Binding var whisperGGMLGPUDecodeEnabled: Bool
    @Binding var whisperModelProfile: WhisperModelProfile
    @Binding var mainTimerDisplayStyle: MainTimerDisplayStyle
    let whisperCoreMLEncoderRecommendationText: String
    let whisperGGMLGPUDecodeRecommendationText: String
    let whisperModelRecommendationText: String
    let isRestoringPurchases: Bool
    let restoreStatusMessage: String?

    let onToggleLanguage: (String) -> Void
    let onRestorePurchases: () -> Void
    let showsMicrophoneMenu: Bool
    let microphonePermissionState: SettingsMicrophonePermissionState
    let onRequestMicrophoneAccess: () -> Void
    let onOpenMicrophoneSettings: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var path: [SettingsStep] = []

    var body: some View {
        NavigationStack(path: $path) {
            rootList
                .navigationTitle("Settings")
                .applyRootTitleDisplayMode()
                .navigationDestination(for: SettingsStep.self) { step in
                    switch step {
                    case .credits:
                        SettingsCreditsStepView(totalHours: totalHours, usedHours: usedHours)
                            .applySettingsSubstepCloseControl {
                                dismiss()
                            }
                    case .languageFocus:
                        SettingsLanguageFocusStepView(
                            selectedLanguageCodes: $selectedLanguageCodes,
                            languageSearchText: $languageSearchText,
                            filteredFocusLanguages: filteredFocusLanguages,
                            groupedFocusLanguages: groupedFocusLanguages
                        )
                        .applySettingsSubstepCloseControl {
                            dismiss()
                        }
                    case .languageRegion(let region):
                        SettingsLanguageRegionStepView(
                            region: region,
                            groupedFocusLanguages: groupedFocusLanguages,
                            selectedLanguageCodes: $selectedLanguageCodes,
                            onToggleLanguage: onToggleLanguage
                        )
                        .applySettingsSubstepCloseControl {
                            dismiss()
                        }
                    case .advancedZone:
                        SettingsAdvancedZoneStepView(
                            whisperCoreMLEncoderEnabled: $whisperCoreMLEncoderEnabled,
                            whisperGGMLGPUDecodeEnabled: $whisperGGMLGPUDecodeEnabled,
                            whisperModelProfile: $whisperModelProfile,
                            whisperCoreMLEncoderRecommendationText: whisperCoreMLEncoderRecommendationText,
                            whisperGGMLGPUDecodeRecommendationText: whisperGGMLGPUDecodeRecommendationText,
                            whisperModelRecommendationText: whisperModelRecommendationText
                        )
                        .applySettingsSubstepCloseControl {
                            dismiss()
                        }
                    case .cloudAndPurchases:
                        SettingsCloudAndPurchasesStepView(
                            isICloudSyncEnabled: $isICloudSyncEnabled,
                            isRestoringPurchases: isRestoringPurchases,
                            restoreStatusMessage: restoreStatusMessage,
                            onRestorePurchases: onRestorePurchases
                        )
                        .applySettingsSubstepCloseControl {
                            dismiss()
                        }
                    case .microphoneAccess:
                        SettingsMicrophoneAccessStepView(
                            permissionState: microphonePermissionState,
                            onRequestMicrophoneAccess: onRequestMicrophoneAccess,
                            onOpenMicrophoneSettings: onOpenMicrophoneSettings
                        )
                        .applySettingsSubstepCloseControl {
                            dismiss()
                        }
                    }
                }
#if os(iOS)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        settingsSheetCloseButton {
                            dismiss()
                        }
                    }
                }
#endif
        }
        .onDisappear {
            path.removeAll()
        }
        .applySettingsSheetCloseControl {
            dismiss()
        }
    }

    private var rootList: some View {
        List {
            Section("General") {
                NavigationLink(value: SettingsStep.credits) {
                    settingsRowLabel(
                        title: "Hours Credit",
                        subtitle: "Usage and balance",
                        symbol: "clock.badge.checkmark"
                    )
                }

                NavigationLink(value: SettingsStep.languageFocus) {
                    settingsRowLabel(
                        title: "Language Focus",
                        subtitle: "Priority recognition languages",
                        symbol: "globe"
                    )
                }

                if showsMicrophoneMenu {
                    NavigationLink(value: SettingsStep.microphoneAccess) {
                        settingsRowLabel(
                            title: "Microphone Access",
                            subtitle: "Permission status and actions",
                            symbol: "mic"
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Time Display")
                        .font(.subheadline.weight(.semibold))

                    Picker("Time Display", selection: $mainTimerDisplayStyle) {
                        ForEach(MainTimerDisplayStyle.allCases, id: \.self) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)

                    Text("Main timer only: \(mainTimerDisplayStyle.sampleText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Runtime") {
                NavigationLink(value: SettingsStep.advancedZone) {
                    settingsRowLabel(
                        title: "Advanced Zone",
                        subtitle: "Runtime and model behavior",
                        symbol: "gearshape.2"
                    )
                }
            }

            Section("Account") {
                NavigationLink(value: SettingsStep.cloudAndPurchases) {
                    settingsRowLabel(
                        title: "Cloud and Purchases",
                        subtitle: "iCloud sync and restore",
                        symbol: "icloud"
                    )
                }
            }
        }
        .applySettingsListStyle()
    }

    private func settingsRowLabel(title: String, subtitle: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 20, height: 20)
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SettingsCreditsStepView: View {
    let totalHours: Double
    let usedHours: Double

    private var remainingHours: Double {
        max(totalHours - usedHours, 0)
    }

    var body: some View {
        SettingsStepContainer {
            Section {
                HStack(alignment: .firstTextBaseline) {
                    Text("Remaining")
                    Spacer()
                    Text("\(remainingHours, specifier: "%.1f")h")
                        .font(.title3.weight(.semibold))
                }

                ProgressView(value: usedHours, total: totalHours)

                HStack {
                    Text("\(usedHours, specifier: "%.1f")h used")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Total \(totalHours, specifier: "%.1f")h")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            } footer: {
                Text("Refill hours before balance runs low to keep continuous transcription.")
            }
        }
        .navigationTitle("Hours Credit")
        .applyStepTitleDisplayMode()
    }
}

private struct SettingsLanguageFocusStepView: View {
    @Binding var selectedLanguageCodes: Set<String>
    @Binding var languageSearchText: String
    let filteredFocusLanguages: [FocusLanguage]
    let groupedFocusLanguages: [LanguageRegionGroup]

    var body: some View {
        SettingsStepContainer {
            Section {
                Text("Choose focus languages by region for a cleaner multi-step flow.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Selected")
                    Spacer()
                    Text("\(selectedLanguageCodes.count)")
                        .fontWeight(.semibold)
                }

                HStack {
                    Text("Shown")
                    Spacer()
                    Text("\(filteredFocusLanguages.count)")
                        .fontWeight(.semibold)
                }
            }

            Section("Search") {
                TextField("Search name / code (en, eng)", text: $languageSearchText)
                    .laycaApplyTextInputAutocorrectionPolicy()
            }

            Section("Regions") {
                if groupedFocusLanguages.isEmpty {
                    Text("No languages match your current search.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(groupedFocusLanguages) { group in
                        NavigationLink(value: SettingsStep.languageRegion(group.region)) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.region.rawValue)
                                        .font(.subheadline.weight(.semibold))
                                    Text("\(group.languages.count) languages")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Language Focus")
        .applyStepTitleDisplayMode()
    }
}

private struct SettingsLanguageRegionStepView: View {
    let region: LanguageRegion
    let groupedFocusLanguages: [LanguageRegionGroup]
    @Binding var selectedLanguageCodes: Set<String>
    let onToggleLanguage: (String) -> Void

    private var languagesInRegion: [FocusLanguage] {
        groupedFocusLanguages.first(where: { $0.region == region })?.languages ?? []
    }

    var body: some View {
        List {
            if languagesInRegion.isEmpty {
                ContentUnavailableView(
                    "No Matches",
                    systemImage: "magnifyingglass",
                    description: Text("Adjust search to see languages in this region.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(Array(languagesInRegion), id: \.id) { (language: FocusLanguage) in
                    Button {
                        onToggleLanguage(language.code)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(language.name)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text("\(language.hello) (\(language.code))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selectedLanguageCodes.contains(language.code) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .applySettingsListStyle()
        .navigationTitle(region.rawValue)
        .applyStepTitleDisplayMode()
    }
}

private struct SettingsAdvancedZoneStepView: View {
    @Binding var whisperCoreMLEncoderEnabled: Bool
    @Binding var whisperGGMLGPUDecodeEnabled: Bool
    @Binding var whisperModelProfile: WhisperModelProfile
    let whisperCoreMLEncoderRecommendationText: String
    let whisperGGMLGPUDecodeRecommendationText: String
    let whisperModelRecommendationText: String

    var body: some View {
        SettingsStepContainer {
            Section {
                Text("Initial values are auto-detected for this device. You can override them anytime.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Acceleration") {
                Toggle("Whisper ggml GPU Decode", isOn: $whisperGGMLGPUDecodeEnabled)
                Text(whisperGGMLGPUDecodeRecommendationText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Whisper CoreML Encoder", isOn: $whisperCoreMLEncoderEnabled)
                Text(whisperCoreMLEncoderRecommendationText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Model Switch") {
                Picker("Model Switch", selection: $whisperModelProfile) {
                    ForEach(WhisperModelProfile.allCases, id: \.self) { profile in
                        Text(profile.title).tag(profile)
                    }
                }
                .pickerStyle(.segmented)

                Text(whisperModelRecommendationText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(whisperModelProfile.detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Advanced Zone")
        .applyStepTitleDisplayMode()
    }
}

private struct SettingsCloudAndPurchasesStepView: View {
    @Binding var isICloudSyncEnabled: Bool
    let isRestoringPurchases: Bool
    let restoreStatusMessage: String?
    let onRestorePurchases: () -> Void

    var body: some View {
        SettingsStepContainer {
            Section("iCloud") {
                Toggle("Sync sessions via iCloud", isOn: $isICloudSyncEnabled)
            }

            Section("Purchases") {
                Button(action: onRestorePurchases) {
                    HStack(spacing: 8) {
                        if isRestoringPurchases {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isRestoringPurchases ? "Restoring..." : "Restore Purchases")
                    }
                }
                .disabled(isRestoringPurchases)

                if let restoreStatusMessage {
                    Text(restoreStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Cloud and Purchases")
        .applyStepTitleDisplayMode()
    }
}

private struct SettingsMicrophoneAccessStepView: View {
    let permissionState: SettingsMicrophonePermissionState
    let onRequestMicrophoneAccess: () -> Void
    let onOpenMicrophoneSettings: () -> Void

    var body: some View {
        SettingsStepContainer {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: permissionState.symbol)
                        .foregroundStyle(permissionState.color)
                    Text(permissionState.title)
                        .font(.subheadline.weight(.semibold))
                }

                Text(permissionState.hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Actions") {
                switch permissionState {
                case .granted, .denied, .unknown:
                    Button("Open System Settings", action: onOpenMicrophoneSettings)
                case .undetermined:
                    Button("Allow Microphone Access", action: onRequestMicrophoneAccess)
                }
            }
        }
        .navigationTitle("Microphone Access")
        .applyStepTitleDisplayMode()
    }
}

private struct SettingsStepContainer<Content: View>: View {
    @ViewBuilder private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
#if os(macOS)
        List {
            content
        }
        .listStyle(.inset)
#else
        Form {
            content
        }
#endif
    }
}

private struct SettingsSheetCloseControlModifier: ViewModifier {
    let onClose: () -> Void

    func body(content: Content) -> some View {
#if os(macOS)
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack {
                    Spacer()
                    Button("Cancel", action: onClose)
                        .keyboardShortcut(.cancelAction)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(.regularMaterial)
                .overlay(alignment: .top) {
                    Divider()
                }
            }
#else
        content
#endif
    }
}

private extension View {
    func applySettingsSheetCloseControl(onClose: @escaping () -> Void) -> some View {
        modifier(SettingsSheetCloseControlModifier(onClose: onClose))
    }

    @ViewBuilder
    func applySettingsSubstepCloseControl(onClose: @escaping () -> Void) -> some View {
#if os(iOS)
        toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                settingsSheetCloseButton(action: onClose)
            }
        }
#else
        self
#endif
    }

    @ViewBuilder
    func applyRootTitleDisplayMode() -> some View {
#if os(iOS)
        navigationBarTitleDisplayMode(.inline)
#else
        self
#endif
    }

    @ViewBuilder
    func applyStepTitleDisplayMode() -> some View {
#if os(iOS)
        navigationBarTitleDisplayMode(.inline)
#else
        self
#endif
    }

    @ViewBuilder
    func applySettingsListStyle() -> some View {
#if os(macOS)
        listStyle(.inset)
#else
        listStyle(.insetGrouped)
#endif
    }
}

@ViewBuilder
private func settingsSheetCloseButton(action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: "xmark")
    }
    .accessibilityLabel("Cancel")
}

private extension SettingsMicrophonePermissionState {
    var title: String {
        switch self {
        case .granted:
            return "Microphone access granted"
        case .undetermined:
            return "Microphone access not requested yet"
        case .denied:
            return "Microphone access denied"
        case .unknown:
            return "Microphone access status unknown"
        }
    }

    var hint: String {
        switch self {
        case .granted:
            return "Layca can record normally."
        case .undetermined:
            return "Allow access once to start recording."
        case .denied:
            return "Recording is blocked until access is enabled in System Settings."
        case .unknown:
            return "Open System Settings to verify microphone access."
        }
    }

    var symbol: String {
        switch self {
        case .granted:
            return "checkmark.circle.fill"
        case .undetermined:
            return "questionmark.circle"
        case .denied:
            return "xmark.circle.fill"
        case .unknown:
            return "exclamationmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .granted:
            return .green
        case .undetermined:
            return .orange
        case .denied:
            return .red
        case .unknown:
            return .secondary
        }
    }
}
