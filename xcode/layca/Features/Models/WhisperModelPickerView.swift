import SwiftUI

// MARK: - Context

enum WhisperModelPickerContext {
    case gate       // new user — shown automatically when Record tapped with no model
    case settings   // Settings → Offline Models
}

// MARK: - Descriptor (view-layer only, not persisted)

struct WhisperModelDescriptor: Identifiable {
    let profile: WhisperModelProfile
    let displayName: String
    let fileSize: String
    let description: String
    let badges: [ModelBadge]
    let symbolName: String
    let iconTint: Color

    var id: WhisperModelProfile { profile }

    static let all: [WhisperModelDescriptor] = [
        WhisperModelDescriptor(
            profile: .quick,
            displayName: "Whisper Fast",
            fileSize: "547 MB",
            description: "Fastest transcription with good accuracy. Great for shorter meetings and older devices. Recommended for iPhone 13 and newer.",
            badges: [.languages, .coreML, .gpu, .fast],
            symbolName: "waveform",
            iconTint: .blue
        ),
        WhisperModelDescriptor(
            profile: .normal,
            displayName: "Whisper Balanced",
            fileSize: "834 MB",
            description: "Best balance of speed and accuracy. Suitable for most meeting lengths. Recommended for iPhone 14 and newer.",
            badges: [.languages, .coreML, .gpu],
            symbolName: "waveform.badge.magnifyingglass",
            iconTint: .accentColor
        ),
        WhisperModelDescriptor(
            profile: .pro,
            displayName: "Whisper Pro",
            fileSize: "1.5 GB",
            description: "Highest accuracy transcription using the full Turbo model. Recommended for iPhone 15 Pro and newer.",
            badges: [.languages, .coreML, .gpu, .bestQuality],
            symbolName: "waveform.badge.plus",
            iconTint: .purple
        )
    ]
}

// MARK: - Badges

enum ModelBadge: String, Identifiable {
    case languages = "96 Languages"
    case coreML = "CoreML"
    case gpu = "GPU"
    case fast = "Fast"
    case bestQuality = "Best Quality"

    var id: String { rawValue }
    var label: String { rawValue }

    var tint: Color {
        switch self {
        case .languages: return .blue
        case .coreML: return .purple
        case .gpu: return .orange
        case .fast: return .green
        case .bestQuality: return Color(hue: 0.11, saturation: 0.85, brightness: 0.70)
        }
    }
}

// MARK: - Layout Constants

private enum PickerLayout {
    static let iconSize: CGFloat = 44
    static let iconCorner: CGFloat = 10
    static let iconSymbolSize: CGFloat = 20
    static let rowVerticalPad: CGFloat = 12
    static let actionControlWidth: CGFloat = 88
    static let progressRingSize: CGFloat = 36
    static let progressRingLineWidth: CGFloat = 3
}

// MARK: - Main View

struct WhisperModelPickerView: View {
    let context: WhisperModelPickerContext
    let activeProfile: WhisperModelProfile
    @ObservedObject var manager: WhisperModelDownloadManager
    var onActivate: (WhisperModelProfile) -> Void
    var onDismiss: () -> Void

    var body: some View {
        Group {
            #if os(macOS)
            Form {
                if context == .gate {
                    gateBannerSection
                }
                modelCardsSection
            }
            .formStyle(.grouped)
            #else
            List {
                if context == .gate {
                    gateBannerSection
                }
                modelCardsSection
            }
            .listStyle(.insetGrouped)
            #endif
        }
        .navigationTitle(context == .gate ? "Choose a Model" : "Whisper Models")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { toolbarContent }
        .interactiveDismissDisabled(context == .gate)
        .task {
            await manager.refreshStates(activeProfile: activeProfile)
        }
        #if os(iOS)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #elseif os(macOS)
        .frame(minWidth: 560, minHeight: 520)
        #endif
    }

    // MARK: Gate Banner

    private var gateBannerSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "mic.fill")
                    .foregroundStyle(.orange)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("A model is required to start recording")
                        .font(.subheadline.weight(.semibold))
                    Text("Download one now — it stays on your device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .accessibilityAddTraits(.isHeader)
        }
        .listRowSeparator(.hidden)
    }

    // MARK: Model Cards

    private var modelCardsSection: some View {
        Section {
            ForEach(WhisperModelDescriptor.all) { model in
                WhisperModelCardRow(
                    model: model,
                    state: manager.states[model.profile] ?? .notDownloaded,
                    errorMessage: manager.downloadErrors[model.profile],
                    onDownload: { manager.download(profile: model.profile) },
                    onCancel: { manager.cancel(profile: model.profile) },
                    onActivate: {
                        onActivate(model.profile)
                        if context == .gate {
                            onDismiss()
                        }
                    },
                    onDelete: { manager.delete(profile: model.profile) }
                )
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        #if os(iOS)
        if context == .settings {
            ToolbarItem(placement: .topBarTrailing) {
                Button { onDismiss() } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Close")
            }
        }
        #else
        ToolbarItem(placement: .automatic) { EmptyView() }
        #endif
    }
}

// MARK: - Model Card Row

private struct WhisperModelCardRow: View {
    let model: WhisperModelDescriptor
    let state: WhisperModelDownloadState
    let errorMessage: String?
    let onDownload: () -> Void
    let onCancel: () -> Void
    let onActivate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(model.displayName)
                            .font(.body.weight(.semibold))
                        Text(model.fileSize)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                    Text(model.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 8)
                actionControl
                    .frame(width: PickerLayout.actionControlWidth, alignment: .trailing)
            }
            HStack(alignment: .center, spacing: 0) {
                badgePills
                Spacer(minLength: 0)
                if state == .downloaded || state == .active {
                    deleteButton
                }
            }
        }
        .padding(.vertical, PickerLayout.rowVerticalPad)
        .accessibilityElement(children: .combine)
    }

    private var modelIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: PickerLayout.iconCorner)
                .fill(model.iconTint.opacity(0.12))
                .frame(width: PickerLayout.iconSize, height: PickerLayout.iconSize)
            Image(systemName: model.symbolName)
                .font(.system(size: PickerLayout.iconSymbolSize, weight: .semibold))
                .foregroundStyle(model.iconTint)
        }
    }

    private var badgePills: some View {
        HStack(spacing: 4) {
            ForEach(model.badges) { badge in
                Text(badge.label)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(badge.tint.opacity(0.12)))
                    .overlay(Capsule().strokeBorder(badge.tint.opacity(0.22), lineWidth: 0.5))
                    .foregroundStyle(badge.tint)
                    .accessibilityHidden(true)
            }
        }
        .padding(.top, 2)
    }

    private var deleteButton: some View {
        Button(action: onDelete) {
            Text("Remove")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove \(model.displayName)")
    }

    @ViewBuilder
    private var actionControl: some View {
        switch state {
        case .notDownloaded:
            Button(action: onDownload) {
                Image(systemName: "arrow.down")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Download \(model.displayName)")

        case .downloading(let progress):
            Button(action: onCancel) {
                ZStack {
                    Circle()
                        .stroke(Color.accentColor.opacity(0.25),
                                lineWidth: PickerLayout.progressRingLineWidth)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.accentColor,
                                style: StrokeStyle(lineWidth: PickerLayout.progressRingLineWidth,
                                                   lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.25), value: progress)
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Downloading \(model.displayName), \(Int(progress * 100)) percent. Tap to cancel.")

        case .downloaded:
            Button("Use", action: onActivate)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.regular)
                .padding(.vertical, -3)
                .accessibilityLabel("Use \(model.displayName)")

        case .active:
            Button("Active") {}
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.regular)
                .padding(.vertical, -3)
                .tint(.green)
                .allowsHitTesting(false)
                .accessibilityLabel("\(model.displayName) is active")
        }
    }
}
