import SwiftUI

struct SettingsTabView: View {
    let totalHours: Double
    let usedHours: Double

    @Binding var selectedLanguageCodes: Set<String>
    @Binding var languageSearchText: String
    @Binding var focusContextKeywords: String

    let filteredFocusLanguages: [FocusLanguage]

    @Binding var isICloudSyncEnabled: Bool
    @Binding var whisperCoreMLEncoderEnabled: Bool
    @Binding var whisperGGMLGPUDecodeEnabled: Bool
    @Binding var whisperModelProfile: WhisperModelProfile
    let whisperCoreMLEncoderRecommendationText: String
    let whisperGGMLGPUDecodeRecommendationText: String
    let whisperModelRecommendationText: String
    let isRestoringPurchases: Bool
    let restoreStatusMessage: String?

    let onToggleLanguage: (String) -> Void
    let onRestorePurchases: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundFill

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        settingsHeader
                        hoursCreditCard
                        languageFocusCard
                        advancedZoneCard
                        iCloudAndPurchaseCard
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 30)
                }
            }
            .laycaHideNavigationBar()
        }
    }

    private var remainingHours: Double {
        max(totalHours - usedHours, 0)
    }

    @ViewBuilder
    private var backgroundFill: some View {
#if os(macOS)
        LinearGradient(
            colors: [
                Color(red: 0.91, green: 0.94, blue: 0.98),
                Color(red: 0.95, green: 0.96, blue: 0.99),
                Color(red: 0.90, green: 0.94, blue: 0.96)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
#else
        Color(uiColor: .systemBackground)
            .ignoresSafeArea()
#endif
    }

    private var settingsHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Setting")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text("Language focus and account sync")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hoursCreditCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Hours Credit")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(remainingHours, specifier: "%.1f")h left")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            ProgressView(value: usedHours, total: totalHours)
                .tint(.accentColor)

            HStack {
                Text("\(usedHours, specifier: "%.1f")h used")
                Spacer()
                Text("Total \(totalHours, specifier: "%.0f")h")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            Text("Refill hours before balance runs low to keep continuous transcription.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
        )
    }

    private var languageFocusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Language Focus")
                .font(.headline)
                .foregroundStyle(.primary)
            Text("Select multiple priority languages for faster and cleaner recognition.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Text("\(selectedLanguageCodes.count) selected")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(filteredFocusLanguages.count) shown")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            TextField("Search name / code (en, eng)", text: $languageSearchText)
                .laycaApplyTextInputAutocorrectionPolicy()
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.regularMaterial)
                )

            TextField("Context keywords (product names, people, jargon)", text: $focusContextKeywords)
                .laycaApplyTextInputAutocorrectionPolicy()
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.regularMaterial)
                )

            ScrollView(showsIndicators: true) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                    ForEach(filteredFocusLanguages) { language in
                        Button {
                            onToggleLanguage(language.code)
                        } label: {
                            LanguageChip(
                                language: language,
                                isSelected: selectedLanguageCodes.contains(language.code)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 230)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
        )
    }

    private var iCloudAndPurchaseCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("iCloud & Purchases")
                .font(.headline)
                .foregroundStyle(.primary)

            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("iCloud Account")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Connected and ready to sync chat sessions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Toggle("Sync sessions via iCloud", isOn: $isICloudSyncEnabled)
                .tint(.accentColor)

            Button(action: onRestorePurchases) {
                HStack {
                    if isRestoringPurchases {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.accentColor)
                    } else {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.body.weight(.semibold))
                    }
                    Text(isRestoringPurchases ? "Restoring..." : "Restore Purchases")
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.regularMaterial)
                )
            }
            .buttonStyle(.plain)

            if let restoreStatusMessage {
                Text(restoreStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
        )
    }

    private var advancedZoneCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Advanced Zone")
                .font(.headline)
                .foregroundStyle(.primary)

            Text("Initial values are auto-detected for this device. You can override them anytime.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Whisper ggml GPU Decode", isOn: $whisperGGMLGPUDecodeEnabled)
                    .tint(.accentColor)
                Text(whisperGGMLGPUDecodeRecommendationText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Whisper CoreML Encoder", isOn: $whisperCoreMLEncoderEnabled)
                    .tint(.accentColor)
                Text(whisperCoreMLEncoderRecommendationText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Model Switch")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

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
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
        )
    }
}

private struct LanguageChip: View {
    let language: FocusLanguage
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(language.name)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(language.code.uppercased()) • \(language.iso3.uppercased())")
                .font(.caption2)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(isSelected ? .white : .primary)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor : unselectedBackgroundColor)
        )
    }

    private var unselectedBackgroundColor: Color {
#if os(macOS)
        Color.white.opacity(0.45)
#else
        Color(uiColor: .secondarySystemBackground)
#endif
    }
}
