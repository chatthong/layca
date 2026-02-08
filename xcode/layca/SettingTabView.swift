import SwiftUI

struct SettingTabView: View {
    let totalHours: Double
    let usedHours: Double

    @Binding var selectedLanguageCodes: Set<String>
    @Binding var languageSearchText: String

    let filteredFocusLanguages: [FocusLanguage]
    let modelCatalog: [ModelOption]
    let selectedModelID: String
    let downloadedModelIDs: Set<String>
    let downloadingModelID: String?
    let modelDownloadProgress: Double

    @Binding var isICloudSyncEnabled: Bool
    let isRestoringPurchases: Bool
    let restoreStatusMessage: String?

    let onToggleLanguage: (String) -> Void
    let onSelectModel: (ModelOption) -> Void
    let onRestorePurchases: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient
                LiquidBackdrop()
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        settingsHeader
                        hoursCreditCard
                        languageFocusCard
                        modelSelectionCard
                        iCloudAndPurchaseCard
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 30)
                }
            }
            .navigationBarHidden(true)
        }
    }

    private var remainingHours: Double {
        max(totalHours - usedHours, 0)
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.88, green: 0.95, blue: 1.0),
                Color(red: 0.95, green: 0.98, blue: 1.0),
                Color(red: 0.90, green: 0.96, blue: 0.95)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var settingsHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Setting")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.black.opacity(0.9))
            Text("Language focus, model download, and account sync")
                .font(.subheadline)
                .foregroundStyle(.black.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hoursCreditCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Hours Credit")
                    .font(.headline)
                    .foregroundStyle(.black.opacity(0.8))
                Spacer()
                Text("\(remainingHours, specifier: "%.1f")h left")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.black.opacity(0.88))
            }

            ProgressView(value: usedHours, total: totalHours)
                .tint(.black.opacity(0.65))

            HStack {
                Text("\(usedHours, specifier: "%.1f")h used")
                Spacer()
                Text("Total \(totalHours, specifier: "%.0f")h")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.black.opacity(0.55))

            Text("Refill hours before balance runs low to keep continuous transcription.")
                .font(.subheadline)
                .foregroundStyle(.black.opacity(0.6))
        }
        .padding(18)
        .liquidCard()
    }

    private var languageFocusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Language Focus")
                .font(.headline)
                .foregroundStyle(.black.opacity(0.8))
            Text("Select multiple priority languages for faster and cleaner recognition.")
                .font(.subheadline)
                .foregroundStyle(.black.opacity(0.6))

            HStack {
                Text("\(selectedLanguageCodes.count) selected")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.black.opacity(0.55))
                Spacer()
                Text("\(filteredFocusLanguages.count) shown")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.black.opacity(0.55))
            }

            TextField("Search name / code (en, eng)", text: $languageSearchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.white.opacity(0.58))
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
        .liquidCard()
    }

    private var modelSelectionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Model Change")
                .font(.headline)
                .foregroundStyle(.black.opacity(0.8))
            Text("Select one model. If missing, Layca downloads it from cloud first.")
                .font(.subheadline)
                .foregroundStyle(.black.opacity(0.6))

            ForEach(modelCatalog) { model in
                Button {
                    onSelectModel(model)
                } label: {
                    ModelRow(
                        model: model,
                        isSelected: selectedModelID == model.id,
                        isInstalled: downloadedModelIDs.contains(model.id),
                        isDownloading: downloadingModelID == model.id,
                        downloadProgress: modelDownloadProgress
                    )
                }
                .buttonStyle(.plain)
                .disabled(downloadingModelID != nil && downloadingModelID != model.id)
            }
        }
        .padding(18)
        .liquidCard()
    }

    private var iCloudAndPurchaseCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("iCloud & Purchases")
                .font(.headline)
                .foregroundStyle(.black.opacity(0.8))

            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.title3)
                    .foregroundStyle(.black.opacity(0.7))
                VStack(alignment: .leading, spacing: 2) {
                    Text("iCloud Account")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.black.opacity(0.75))
                    Text("Connected and ready to sync chat sessions")
                        .font(.caption)
                        .foregroundStyle(.black.opacity(0.55))
                }
            }

            Toggle("Sync sessions via iCloud", isOn: $isICloudSyncEnabled)
                .tint(.black.opacity(0.75))

            Button(action: onRestorePurchases) {
                HStack {
                    if isRestoringPurchases {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.black.opacity(0.75))
                    } else {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.body.weight(.semibold))
                    }
                    Text(isRestoringPurchases ? "Restoring..." : "Restore Purchases")
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.black.opacity(0.82))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.white.opacity(0.58))
                )
            }
            .buttonStyle(.plain)

            if let restoreStatusMessage {
                Text(restoreStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.black.opacity(0.58))
            }
        }
        .padding(18)
        .liquidCard()
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
        .foregroundStyle(isSelected ? .white : .black.opacity(0.72))
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? .black.opacity(0.72) : .white.opacity(0.58))
        )
    }
}

private struct ModelRow: View {
    let model: ModelOption
    let isSelected: Bool
    let isInstalled: Bool
    let isDownloading: Bool
    let downloadProgress: Double

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black.opacity(0.82))
                Text(model.sizeLabel)
                    .font(.caption)
                    .foregroundStyle(.black.opacity(0.55))
            }

            Spacer()

            if isDownloading {
                HStack(spacing: 6) {
                    ProgressView(value: max(downloadProgress, 0.05))
                        .progressViewStyle(.circular)
                        .tint(.black.opacity(0.75))
                    Text("\(Int(downloadProgress * 100))%")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.black.opacity(0.55))
                }
            } else if isSelected {
                Label("Active", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green.opacity(0.88))
            } else if isInstalled {
                Text("Installed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.black.opacity(0.55))
            } else {
                Label("Download", systemImage: "icloud.and.arrow.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.black.opacity(0.7))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(isSelected ? 0.64 : 0.50))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.58), lineWidth: 0.8)
        )
    }
}
