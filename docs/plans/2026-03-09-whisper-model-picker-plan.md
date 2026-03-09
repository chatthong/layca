# Whisper Model Picker Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace bundled Whisper GGML binaries with on-demand HuggingFace downloads, backed by a rich per-model picker sheet that gates recording for new users.

**Architecture:** A new `@MainActor` `WhisperModelDownloadManager` class owns all download state (progress, cancellation, filesystem checks) and is held by `AppBackend`. A new `WhisperModelPickerView` presents model cards with Download/Progress/Use/Active controls. `AppBackend.toggleRecording` checks for any downloaded model and shows the picker sheet if none exists.

**Tech Stack:** Swift 5.10, SwiftUI, URLSession AsyncBytes (progress streaming), existing `WhisperGGMLCoreMLService` cache dir (`~/Library/Caches/WhisperGGML/`).

---

## Task 1: Add HuggingFace URLs for Q5 and Q8

**Files:**
- Modify: `xcode/layca/Libraries/WhisperGGMLCoreMLService.swift:752,763`

**Step 1: Add download URLs**

In `modelSpec(for:)`, replace the two `downloadURL: nil` lines:

```swift
// .quick case — line 752
downloadURL: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin?download=true"

// .normal case — line 763
downloadURL: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q8_0.bin?download=true"
```

**Step 2: Expose cache directory and model check publicly**

Add these two `internal` (not `private`) methods to `WhisperGGMLCoreMLService` (place after `isValidModelFile`):

```swift
/// Returns the URL where a model profile's binary is cached, if present and valid.
func cachedModelURL(for profile: WhisperModelProfile) -> URL? {
    let spec = modelSpec(for: profile)
    let url = rootDirectory.appendingPathComponent(spec.cacheFileName)
    guard isValidModelFile(at: url, minimumFileSizeBytes: spec.minimumFileSizeBytes) else {
        return nil
    }
    return url
}

/// Returns the HuggingFace download URL for a profile, or nil if bundled-only.
func remoteDownloadURL(for profile: WhisperModelProfile) -> URL? {
    guard let str = modelSpec(for: profile).downloadURL else { return nil }
    return URL(string: str)
}

/// Returns the local cache URL (may not exist yet) and minimum file size for a profile.
func cacheDestination(for profile: WhisperModelProfile) -> (url: URL, minimumBytes: Int64) {
    let spec = modelSpec(for: profile)
    return (rootDirectory.appendingPathComponent(spec.cacheFileName), spec.minimumFileSizeBytes)
}
```

**Step 3: Ensure cache directory creation is accessible**

Add this public helper (the existing `createDirectory` call is buried in `ensureModelFile`):

```swift
func prepareCacheDirectory() throws {
    try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
}
```

**Step 4: Commit**

```bash
git add xcode/layca/Libraries/WhisperGGMLCoreMLService.swift
git commit -m "feat: add HuggingFace download URLs for Q5 and Q8 Whisper models"
```

---

## Task 2: Create WhisperModelDownloadManager

**Files:**
- Create: `xcode/layca/Features/Models/WhisperModelDownloadManager.swift`

This `@MainActor` class is the single source of truth for model download state. It is owned by `AppBackend`.

```swift
import Foundation
import Observation

enum WhisperModelDownloadState: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded
    case active
}

@MainActor
final class WhisperModelDownloadManager: ObservableObject {

    @Published private(set) var states: [WhisperModelProfile: WhisperModelDownloadState] = [:]
    @Published private(set) var downloadErrors: [WhisperModelProfile: String] = [:]

    private let service: WhisperGGMLCoreMLService
    private var downloadTasks: [WhisperModelProfile: Task<Void, Never>] = [:]

    init(service: WhisperGGMLCoreMLService) {
        self.service = service
    }

    // MARK: - Public API

    /// Call on app launch and after any download completes to sync filesystem state.
    func refreshStates(activeProfile: WhisperModelProfile) async {
        for profile in WhisperModelProfile.allCases {
            guard downloadTasks[profile] == nil else { continue } // keep .downloading state
            let downloaded = await service.cachedModelURL(for: profile) != nil
            if profile == activeProfile && downloaded {
                states[profile] = .active
            } else if downloaded {
                states[profile] = .downloaded
            } else {
                states[profile] = .notDownloaded
            }
        }
    }

    /// Starts downloading the model binary from HuggingFace with progress reporting.
    func download(profile: WhisperModelProfile) {
        guard downloadTasks[profile] == nil else { return }
        downloadErrors[profile] = nil
        states[profile] = .downloading(progress: 0)

        downloadTasks[profile] = Task {
            do {
                try await service.prepareCacheDirectory()
                guard let remoteURL = await service.remoteDownloadURL(for: profile) else {
                    await MainActor.run {
                        self.states[profile] = .notDownloaded
                        self.downloadErrors[profile] = "No download URL available for this model."
                        self.downloadTasks[profile] = nil
                    }
                    return
                }
                let (destination, minimumBytes) = await service.cacheDestination(for: profile)

                // Stream bytes for live progress reporting.
                let (asyncBytes, response) = try await URLSession.shared.bytes(from: remoteURL)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }

                let totalBytes = response.expectedContentLength  // -1 if unknown
                let tempURL = destination.deletingLastPathComponent()
                    .appendingPathComponent(destination.lastPathComponent + ".tmp")

                FileManager.default.createFile(atPath: tempURL.path, contents: nil)
                let handle = try FileHandle(forWritingTo: tempURL)
                var receivedBytes: Int64 = 0

                for try await byte in asyncBytes {
                    try handle.write(contentsOf: [byte])
                    receivedBytes += 1
                    if receivedBytes % 65536 == 0 {  // update UI every 64 KB
                        let progress = totalBytes > 0 ? Double(receivedBytes) / Double(totalBytes) : 0
                        await MainActor.run {
                            self.states[profile] = .downloading(progress: progress)
                        }
                    }
                    if Task.isCancelled { break }
                }
                try handle.close()

                if Task.isCancelled {
                    try? FileManager.default.removeItem(at: tempURL)
                    await MainActor.run {
                        self.states[profile] = .notDownloaded
                        self.downloadTasks[profile] = nil
                    }
                    return
                }

                // Validate and move into place.
                let attrs = try FileManager.default.attributesOfItem(atPath: tempURL.path)
                let size = attrs[.size] as? Int64 ?? 0
                guard size >= minimumBytes else {
                    try? FileManager.default.removeItem(at: tempURL)
                    throw URLError(.cannotDecodeContentData)
                }

                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: tempURL, to: destination)

                await MainActor.run {
                    self.states[profile] = .downloaded
                    self.downloadTasks[profile] = nil
                }
            } catch {
                let cancelled = error is CancellationError || (error as? URLError)?.code == .cancelled
                await MainActor.run {
                    self.states[profile] = .notDownloaded
                    if !cancelled {
                        self.downloadErrors[profile] = error.localizedDescription
                    }
                    self.downloadTasks[profile] = nil
                }
            }
        }
    }

    /// Cancels an in-flight download.
    func cancel(profile: WhisperModelProfile) {
        downloadTasks[profile]?.cancel()
        downloadTasks[profile] = nil
        states[profile] = .notDownloaded
    }

    /// Marks profile as active. Call after updating AppBackend.whisperModelProfile.
    func markActive(_ profile: WhisperModelProfile) {
        for p in WhisperModelProfile.allCases {
            if states[p] == .active {
                states[p] = .downloaded
            }
        }
        states[profile] = .active
    }

    /// True if any profile has a downloaded or active model.
    var hasAnyDownloadedModel: Bool {
        states.values.contains { $0 == .downloaded || $0 == .active }
    }
}
```

**Step 2: Add to Xcode target**

In Xcode, add `WhisperModelDownloadManager.swift` to the `layca` target (drag into the `Features/Models` group, tick the target checkbox).

**Step 3: Commit**

```bash
git add xcode/layca/Features/Models/WhisperModelDownloadManager.swift
git commit -m "feat: add WhisperModelDownloadManager with progress streaming"
```

---

## Task 3: Wire Download Manager into AppBackend

**Files:**
- Modify: `xcode/layca/App/AppBackend.swift`

**Step 1: Add published properties near line 2984**

```swift
// Near the other @Published vars:
@Published var showModelPickerSheet = false
let modelDownloadManager: WhisperModelDownloadManager  // set in init
```

**Step 2: Initialize in AppBackend.init**

Find the existing `init` of `AppBackend` (search for `init(` near `settingsStore`). Add:

```swift
self.modelDownloadManager = WhisperModelDownloadManager(service: whisperTranscriber)
```

Note: `whisperTranscriber` is the existing `WhisperGGMLCoreMLService` instance at line ~3075.

**Step 3: Gate check in `toggleRecording` (line 3335)**

Replace:

```swift
func toggleRecording() {
    if isRecording {
        Task { await stopRecording() }
    } else if isTranscriptChunkPlaying {
        stopChunkPlayback()
    } else {
        Task { await startRecording() }
    }
}
```

With:

```swift
func toggleRecording() {
    if isRecording {
        Task { await stopRecording() }
    } else if isTranscriptChunkPlaying {
        stopChunkPlayback()
    } else if !modelDownloadManager.hasAnyDownloadedModel {
        showModelPickerSheet = true
    } else {
        Task { await startRecording() }
    }
}
```

**Step 4: Refresh download states on launch**

In the existing `prepareIfNeeded()` or `onAppear` call chain (search for `func prepareIfNeeded` in AppBackend), add after the existing setup:

```swift
Task {
    await modelDownloadManager.refreshStates(activeProfile: whisperModelProfile)
}
```

**Step 5: Keep active state in sync when profile changes**

Find where `whisperModelProfile` is set from settings (search for `whisperModelProfile =`). After each assignment, call:

```swift
modelDownloadManager.markActive(whisperModelProfile)
```

**Step 6: Commit**

```bash
git add xcode/layca/App/AppBackend.swift
git commit -m "feat: wire WhisperModelDownloadManager into AppBackend, gate recording on model presence"
```

---

## Task 4: Create WhisperModelPickerView

**Files:**
- Create: `xcode/layca/Features/Models/WhisperModelPickerView.swift`

This is the main UI task. Full implementation:

```swift
import SwiftUI

// MARK: - Context

enum WhisperModelPickerContext {
    case gate       // new user, no model — sheet shown automatically on Record tap
    case settings   // Settings → Offline Models
}

// MARK: - Descriptor (view-layer data, not persisted)

struct WhisperModelDescriptor {
    let profile: WhisperModelProfile
    let displayName: String
    let fileSize: String
    let description: String
    let badges: [ModelBadge]
    let symbolName: String
    let iconTint: Color

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

// MARK: - Constants

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
    @ObservedObject var manager: WhisperModelDownloadManager
    var onActivate: (WhisperModelProfile) -> Void
    var onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if context == .gate {
                    gateBannerSection
                }
                modelCardsSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle(context == .gate ? "Choose a Model" : "Whisper Models")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .interactiveDismissDisabled(context == .gate)
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 520)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
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
    }

    // MARK: Model Cards

    private var modelCardsSection: some View {
        Section {
            ForEach(WhisperModelDescriptor.all, id: \.profile) { model in
                WhisperModelCardRow(
                    model: model,
                    state: manager.states[model.profile] ?? .notDownloaded,
                    errorMessage: manager.downloadErrors[model.profile],
                    onDownload: { manager.download(profile: model.profile) },
                    onCancel: { manager.cancel(profile: model.profile) },
                    onActivate: {
                        onActivate(model.profile)
                        if context == .gate { onDismiss() }
                    }
                )
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if context == .settings {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Close")
            }
        }
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

    var body: some View {
        HStack(alignment: .top, spacing: PickerLayout.iconSize / 3) {
            modelIcon
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
                badgePills
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
                .alignmentGuide(.top) { d in d[.top] + 2 }
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

    @ViewBuilder
    private var actionControl: some View {
        switch state {
        case .notDownloaded:
            Button(action: onDownload) {
                Text("Download")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.accentColor))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Download \(model.displayName)")

        case .downloading(let progress):
            VStack(alignment: .center, spacing: 4) {
                Button(action: onCancel) {
                    ZStack {
                        Circle()
                            .stroke(Color.accentColor.opacity(0.2), lineWidth: PickerLayout.progressRingLineWidth)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(Color.accentColor,
                                    style: StrokeStyle(lineWidth: PickerLayout.progressRingLineWidth, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 0.25), value: progress)
                        Image(systemName: "stop.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .frame(width: PickerLayout.progressRingSize, height: PickerLayout.progressRingSize)
                }
                .buttonStyle(.plain)
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .accessibilityLabel("Downloading \(model.displayName), \(Int(progress * 100)) percent. Tap to cancel.")

        case .downloaded:
            Button(action: onActivate) {
                Text("Use")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().strokeBorder(Color.accentColor, lineWidth: 1.5))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Use \(model.displayName)")

        case .active:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.green)
                Text("Active")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }
            .accessibilityLabel("\(model.displayName) is active")
        }
    }
}
```

**Step 2: Add to Xcode target** — add file to `layca` target in `Features/Models` group.

**Step 3: Commit**

```bash
git add xcode/layca/Features/Models/WhisperModelPickerView.swift
git commit -m "feat: add WhisperModelPickerView with per-model download cards"
```

---

## Task 5: Wire Gate Sheet into ContentView

**Files:**
- Modify: `xcode/layca/App/ContentView.swift`

**Step 1: Find the iOS chat workspace binding site (~line 391)**

The record button calls `backend.toggleRecording`. Add a `.sheet` modifier to the appropriate view — the iOS `ChatTabView` or its container — driven by `backend.showModelPickerSheet`.

Find the view that wraps the `onRecordTap: backend.toggleRecording` call. Add:

```swift
.sheet(isPresented: $backend.showModelPickerSheet) {
    WhisperModelPickerView(
        context: .gate,
        manager: backend.modelDownloadManager,
        onActivate: { profile in
            backend.whisperModelProfile = profile
            backend.modelDownloadManager.markActive(profile)
        },
        onDismiss: {
            backend.showModelPickerSheet = false
        }
    )
}
```

**Step 2: Repeat for macOS workspace (~line 465)**

Add the same `.sheet` modifier to the macOS workspace container. On macOS the gate context won't fire (gate only triggers on iOS/visionOS where recording is the primary flow) but the sheet binding is safe to attach everywhere — it will simply never be triggered on macOS via the gate path.

**Step 3: Commit**

```bash
git add xcode/layca/App/ContentView.swift
git commit -m "feat: attach model picker gate sheet to record button flow"
```

---

## Task 6: Replace SettingsOfflineModelSwitchStepView

**Files:**
- Modify: `xcode/layca/Features/Share/SettingsSheetFlowView.swift:195-198,627-658`

**Step 1: Replace the navigation destination (~line 195)**

Change:

```swift
case .offlineModelSwitch:
    SettingsOfflineModelSwitchStepView(
        whisperModelProfile: $whisperModelProfile,
        whisperModelRecommendationText: whisperModelRecommendationText
    )
```

To:

```swift
case .offlineModelSwitch:
    WhisperModelPickerView(
        context: .settings,
        manager: manager,   // passed in as a parameter (see Step 2)
        onActivate: { profile in
            whisperModelProfile = profile
            manager.markActive(profile)
        },
        onDismiss: {
            // NavigationStack handles back navigation; no-op here.
        }
    )
    .navigationBarBackButtonHidden(false)
```

**Step 2: Thread `WhisperModelDownloadManager` through SettingsSheetFlowView**

`SettingsSheetFlowView` is currently initialized with `whisperModelProfile` and `whisperModelRecommendationText`. Add `manager: WhisperModelDownloadManager` as a parameter and thread it through to the navigation destination. Find the call site in `ContentView` (search for `SettingsSheetFlowView(`) and pass `backend.modelDownloadManager`.

**Step 3: Delete `SettingsOfflineModelSwitchStepView`**

Delete the entire private struct `SettingsOfflineModelSwitchStepView` (lines 627–658). It is fully replaced by `WhisperModelPickerView`.

**Step 4: Commit**

```bash
git add xcode/layca/Features/Share/SettingsSheetFlowView.swift
git commit -m "feat: replace segmented model picker with WhisperModelPickerView in settings"
```

---

## Task 7: Remove Bundled .bin Files from Xcode Project

**Files:**
- Modify: Xcode project file (via Xcode UI)

**Step 1: Remove from Copy Bundle Resources**

In Xcode:
1. Select the `layca` target → Build Phases → Copy Bundle Resources
2. Remove all three files:
   - `ggml-large-v3-turbo-q5_0.bin`
   - `ggml-large-v3-turbo-q8_0.bin`
   - `ggml-large-v3-turbo.bin`
3. Do NOT delete from disk yet (keep for testing offline fallback)

**Step 2: Update bundledFileNames in WhisperGGMLCoreMLService**

Since bundled files no longer ship, clear the `bundledFileNames` arrays so the code skips the bundled-file check and goes straight to cache/download:

```swift
// .quick case
bundledFileNames: []

// .normal case
bundledFileNames: []

// .pro case
bundledFileNames: []
```

This makes `bundledModelFileURL` always return `nil`, sending every profile through the download path.

**Step 3: Commit**

```bash
git add xcode/layca.xcodeproj/project.pbxproj
git add xcode/layca/Libraries/WhisperGGMLCoreMLService.swift
git commit -m "feat: remove bundled Whisper GGML binaries — all models now download on demand"
```

---

## Task 8: Refresh Download States on Settings Open

**Files:**
- Modify: `xcode/layca/Features/Share/SettingsSheetFlowView.swift` (or wherever settings sheet appears)

**Step 1: Add `.task` on sheet appearance**

When `WhisperModelPickerView` appears in settings context, refresh states so "Active" indicators are accurate:

Inside `WhisperModelPickerView.body`, add:

```swift
.task {
    await manager.refreshStates(activeProfile: /* current active profile */)
}
```

The `onActivate` closure already has the profile. To pass the current active profile into the picker, add a `activeProfile: WhisperModelProfile` parameter to `WhisperModelPickerView` and thread it from `backend.whisperModelProfile`.

**Step 2: Commit**

```bash
git add xcode/layca/Features/Models/WhisperModelPickerView.swift
git add xcode/layca/Features/Share/SettingsSheetFlowView.swift
git commit -m "fix: refresh model download states when picker sheet opens"
```

---

## Task 9: Update Memory

After all tasks pass a manual test (record gate + settings picker + download + active state):

```bash
# Update MEMORY.md to note the new architecture
```

Add to memory: "Whisper models now all download on demand from HuggingFace. `WhisperModelDownloadManager` in `Features/Models/` owns download state. Gate check is in `AppBackend.toggleRecording`."

---

## Manual Test Checklist

- [ ] Fresh install: tap Record → picker sheet appears, can't swipe to dismiss
- [ ] Download Fast model → progress ring animates, % updates
- [ ] Cancel mid-download → state reverts to "Download"
- [ ] Download completes → "Use" button appears, tap it → sheet dismisses, back on main screen
- [ ] Tap Record again → recording starts normally
- [ ] Settings → Offline Models → picker shows Fast as Active, other two as Download
- [ ] Download a second model → "Use" button appears, tap → Fast becomes Downloaded, new one becomes Active
- [ ] macOS: Settings → Offline Models → same picker appears, no gate banner
- [ ] Network error during download → inline error text on card, Download button re-appears
