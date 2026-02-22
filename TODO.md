# Layca — Task List

> Source: `docs/team-explorer-report.md` (2026-02-21 multi-agent audit)
> Format: `- [ ]` pending · `- [x]` done · blocked tasks noted inline
> Update this file as work completes.

---

## 🚀 Active Priorities — Work On These Now

User-defined priorities. Do these before anything else in the codebase.

- [x] **Real-time speaker interrupt detection** · `Libraries/SpeakerDiarizationCoreMLService.swift` + pipeline
  - ✅ Done 2026-02-21: sliding-window cosine distance fast-path (256ms / 4,096 samples). Dual threshold: 0.35×2 windows for robustness, 0.5×1 for instant cut. `checkForInterrupt()`, `resetInterruptState()`, `cosineSimilarity()` added. Pipeline wired in `AppBackend.swift` `ingest()`.

- [ ] **On-device LLM summary with user prompt** · new `Services/SummaryService.swift`
  - Feature: user taps "Summarize" (in share sheet or toolbar), gets a prompt field to type instructions (e.g. "bullet points", "action items", "formal report"), then Qwen 2.5 runs on-device and produces formatted output
  - Model: Qwen 2.5 7B or 12B via **MLX Swift** (`mlx-swift` package, Apple Silicon only) — same download-on-demand pattern as the existing CoreML model manager
  - Output formats to support: Plain Text, Markdown, Notepad Minutes style, SRT-annotated (match existing `ExportFormat` enum in `ContentView.swift`)
  - UX flow:
    1. "Summarize" button in toolbar / share menu
    2. Sheet slides up: multiline prompt field + format picker + "Generate" button
    3. Generation runs in background actor; progress shown in sheet
    4. Result appears in sheet — copy, share, or export buttons
  - Implementation steps:
    1. Add `mlx-swift` + `mlx-lm` Swift packages
    2. Create `SummaryService` actor: `download(model:)`, `generate(transcript:prompt:format:) async throws -> String`
    3. Add `SummarySheet` SwiftUI view (prompt field, format picker, streaming output display)
    4. Wire "Summarize" button in `ChatTabView` toolbar and share menu
    5. Model storage in `Documents/Models/qwen-2.5-7b-instruct-4bit/` — same pattern as Whisper models
  - Note: 7B 4-bit ≈ 4 GB RAM; 12B 4-bit ≈ 7 GB RAM — add device RAM check, offer 7B as default
  - Effort: L · Agent: `swift-engineer`

---

## 🔴 Critical — Fix Before Anything Else

These are bugs or blockers for all future work. Do them first.

- [x] **Fix ForEach crash risk** · `MacProWorkspaceView.swift:154`
  - ✅ Done 2026-02-21: Fixed 3 instances total — MacProWorkspaceView.swift (×2, lines 154 + 925) and IOSWorkspaceSidebarView.swift (×1, line 232). All use `ForEach(sessions) { session in }` now.

- [x] **Extract `Color` out of `TranscriptRow`** · `Models/Domain/TranscriptRow.swift:14`
  - ✅ Done 2026-02-21: `avatarPalette: [Color]` → `avatarPaletteIndex: Int`. `static let palettes: [[Color]]` added to TranscriptRow.swift. Computed `var avatarColor: Color`. 6 call sites updated in AppBackend.swift. TranscriptRow is now Codable-ready; unblocks SwiftData + @Observable.

---

## 🔴 High Priority — Bugs & Regressions

Small fixes, high impact. Can be done in any order.

- [x] **Set Settings sheet default to `.large` detent** · `App/ContentView.swift`
  - ✅ Done 2026-02-21: Changed `.presentationDetents([.medium, .large])` → `[.large]`.

- [ ] **Fix waveform bars color state** · `Features/Chat/ChatTabView.swift` `waveformPanel`
  - Bars always show `Color.red.opacity(0.78)` — should match recording state
  - Fix: use `recorderActionColor` (already computed) as bar fill
  - Effort: S · Agent: `apple-design-lead`

- [x] **Unify "Pause" vs "Stop" vocabulary**
  - ✅ Done 2026-02-21: Changed in ChatTabView.swift (lines 813, 825, 827). Zero "Pause" labels remain across all Swift files.

- [x] **Add haptic feedback on record start/stop** · `App/AppBackend.swift`
  - ✅ Done 2026-02-21: `.medium` on start/stop, `.heavy` on error. Wrapped in `#if canImport(UIKit)`.

---

## 🟡 High Priority — Accessibility (VoiceOver)

- [ ] **Add accessibilityLabel to waveform panel** · `ChatTabView.swift` `waveformPanel`
  - VoiceOver reads nothing useful on the waveform
  - Fix: `.accessibilityLabel("Audio waveform, \(isRecording ? "recording active" : "idle")")`
  - Add `.accessibilityHidden(true)` on individual bar capsules
  - Effort: S · Agent: `accessibility-lead`

- [ ] **Group transcript bubbles for VoiceOver** · `ChatTabView.swift` `messageBubble(for:)`
  - Speaker name, timestamp, language badge, text are separate VoiceOver elements
  - Fix: `.accessibilityElement(children: .combine)` on the bubble VStack
  - Add `.accessibilityHint("Double tap to play")` when `isTranscriptBubblePlayable`
  - Effort: S · Agent: `accessibility-lead`

- [ ] **Add accessibilityLabel to avatar circles** · `ChatTabView.swift` `avatarView(for:)`
  - VoiceOver reads raw SF Symbol name ("person fill") instead of speaker name
  - Fix: `.accessibilityLabel("Speaker: \(item.speaker)")`
  - Effort: S · Agent: `accessibility-lead`

- [ ] **Fix language badge VoiceOver label** · `ChatTabView.swift` `speakerMeta(for:)`
  - Language badge reads "globe EN" — no semantic meaning
  - Fix: `.accessibilityLabel("Language: \(resolvedLanguageName(item.language))")` on HStack
  - Add `.accessibilityHidden(true)` on globe Image
  - Effort: S · Agent: `accessibility-lead`

- [ ] **Replace hardcoded font sizes with Dynamic Type** · `ChatTabView.swift`
  - `size: 46` → `.system(.largeTitle, design: .rounded, weight: .semibold)`
  - `size: 22` → `.system(.title2, design: .rounded, weight: .bold)`
  - `size: 19` → `.system(.title3, design: .rounded, weight: .semibold)`
  - Also: `waveformPanel frame(width: 120, height: 126)` → flexible height
  - Effort: S · Agent: `accessibility-lead`

---

## 🟡 High Priority — Design & HIG

- [x] **Replace hardcoded RGB colors with adaptive Color assets**
  - ✅ Done 2026-02-21 (partial): `RecordingSpectrumBubble.swift` — all hardcoded blues → `Color.accentColor`.
  - ⏳ Remaining: `ChatTabView` macOS background gradient `Color(red: 0.91, ...)` — pending ChatTabView pass.

- [ ] **Replace `titleDisplayCharacterWidth` pixel hack** · `ChatTabView.swift:8`
  - `titleDisplayCharacterWidth: CGFloat = 9` breaks for Thai, Arabic, CJK (wider chars)
  - Fix: use `ViewThatFits` or natural button sizing with `.frame(maxWidth:)` cap
  - Effort: M · Agent: `apple-design-lead`

- [x] **Fix iPadOS layout — use NavigationSplitView** · `App/ContentView.swift`
  - ✅ Done 2026-02-21: Added `horizontalSizeClass == .regular` check → `ipadSplitLayout` using `NavigationSplitView` with `IOSWorkspaceSidebarView` (min 230, ideal 280, max 360).

- [x] **Fix DispatchQueue focus retries** · `MacProWorkspaceView.swift` `requestTitleFieldFocus()`
  - ✅ Done 2026-02-21 (MacProWorkspaceView portion): Replaced 3×asyncAfter + NSApp hacks with `.task(id: isEditingTitle)`. Function deleted entirely.
  - ⏳ Remaining: `ChatTabView.swift` `beginTitleRename()` — pending ChatTabView pass.

- [ ] **Add play affordance to transcript bubbles**
  - No visual hint that bubbles are tappable for playback
  - Fix: show a subtle `play.circle` icon on bubbles where `isTranscriptBubblePlayable`
  - Effort: S · Agent: `apple-design-lead`

---

## 🟡 Medium — Code Quality & Architecture

- [x] **Move MasterAudioRecorder file I/O off @MainActor** · `App/AppBackend.swift`
  - ✅ Done 2026-02-21: `mergeAudioFilesWithRetries` + `mergeAudioFiles` made `private static` (nonisolated). Called via `Task.detached(priority: .userInitiated)` in `stop()`.

- [ ] **Extract ExportService from ContentView** · `App/ContentView.swift`
  - ~200 lines of export logic (SRT, Markdown, NotepadMinutes, PlainText) in ContentView
  - Fix: new file `Services/ExportService.swift` with a pure struct — makes it testable
  - Effort: M · Agent: `swift-engineer` · ⏳ In progress Sprint 7

- [x] **Extract focusLanguages catalog** · `App/ContentView.swift`
  - ✅ Done 2026-02-21: 96-language array moved to `static let all: [FocusLanguage]` in `FocusLanguage.swift`. `var focusLanguages` computed property deleted from ContentView (100 lines removed).

- [ ] **Replace NotificationCenter rename-cancel with environment** · `ChatTabView.swift:198`
  - `NotificationCenter.publisher(for: "LaycaCancelTitleRenameEditing")` is fragile coupling
  - Fix: UUID nonce `@State` on ContentView, passed to ChatTabView + sidebar; `.onChange` replaces `.onReceive`
  - Effort: S · Agent: `swift-engineer` · ⏳ Queued Sprint 7

---

## 🟢 Features — Revenue & Retention

These unlock monetization and long-term user retention. Work in order.

- [ ] **Implement StoreKit 2 IAP** · new file `Services/StoreService.swift`
  - Products: `com.layca.base` ($14.99 one-time) + `com.layca.pro` ($24.99 one-time IAP)
  - Replace credit deduction system with entitlement checks
  - Free tier: 30 min/month for non-purchasers
  - Effort: L · Agent: `product-strategist` (design) + `swift-engineer` (implementation)

- [ ] **Implement full-text search across sessions**
  - Build in-memory index from all loaded TranscriptRow.text values
  - UI: search field in sidebar, results grouped by session with snippet + timestamp
  - Later: migrate to SwiftData predicate queries
  - Effort: L · Agent: `swift-engineer`

- [ ] **Add Apple Shortcuts + Control Center widget**
  - `AppIntent` conformance: StartRecording, StopRecording, GetSessionTitle
  - `ControlWidget` for iOS 18 lock screen / Control Center
  - Effort: M · Agent: `swift-engineer`

- [x] **Implement iCloud sync (iCloud Drive)** · `Services/ICloudSyncService.swift` + `App/AppBackend.swift`
  - ✅ Done 2026-02-22: iCloud Drive (ubiquitous container) approach — no CloudKit, no third-party. `ICloudSyncService` actor: push/pull/merge/NSMetadataQuery. Per-row last-write-wins via `updatedAt` on `TranscriptRow` and `StoredSession`. Audio sync user-toggle (default OFF). `iCloudSyncStatus` + `isAudioSyncEnabled` wired through AppBackend + Settings UI. macOS entitlements updated. Smoke test on real devices still needed (Task 11).

- [ ] **Speaker profile persistence across sessions** · ~~blocked by: Extract Color from TranscriptRow~~ (blocker resolved ✅)
  - Persist speaker voice embeddings + user-assigned names in shared `profiles.json`
  - Match incoming embeddings against known profiles at session start
  - Effort: L · Agent: `swift-engineer`

---

## 🟢 Features — Platform & Polish

- [ ] **Migrate AppBackend to @Observable macro** · ~~blocked by: Extract Color from TranscriptRow~~ (blocker resolved ✅)
  - Replace `@MainActor ObservableObject` + prop drilling with `@Observable` + `.environment()`
  - Eliminates the 20+ parameter init in ChatTabView
  - Effort: L · Agent: `swift-engineer`

- [ ] **Add SwiftData persistence layer**
  - Mirror filesystem JSON to SwiftData for search, filtering, and CloudKit sync
  - Requires: Color extracted from TranscriptRow (no SwiftUI types in models) ✅ resolved
  - Effort: XL · Agent: `swift-engineer`

- [ ] **RTL layout support for Arabic/Hebrew/Persian/Urdu**
  - Custom drawer sidebar and chat layout use hardcoded `.leading` — won't mirror for RTL
  - Fix: use `.layoutDirectionAware` modifiers and environment `layoutDirection`
  - Effort: M · Agent: `accessibility-lead`

- [ ] **Localize app UI to Thai, Spanish, Arabic**
  - App UI is English-only despite 96-language transcript support
  - These 3 locales cover the highest-value user segments
  - Effort: M · Agent: `product-strategist` (strings) + `swift-engineer` (Localizable.strings)

- [ ] **visionOS ornament UI** · `App/ContentView.swift` `mobileTabLayout`
  - Currently gets a TabView fallback — should use ornaments for spatial UI
  - Effort: L · Agent: `apple-design-lead`

- [ ] **Calendar integration (EventKit) — auto-title sessions**
  - On record start, check EventKit for current/recent calendar event
  - Auto-title session with meeting name if permission granted
  - Effort: M · Agent: `swift-engineer`

- [ ] **Apple Watch app — remote record start/stop**
  - WatchKit / SwiftUI Watch target
  - Start/stop recording from wrist; show elapsed time + last transcript line
  - Effort: L · Agent: `swift-engineer`

---

## 🗓 Launch Checklist (When App Is Ready)

- [ ] App Store screenshots: privacy hero, multilingual badge switch, SRT export, macOS split view, airplane mode + working transcript
- [ ] App Store keywords: "meeting transcription offline", "multilingual transcript", "voice to text no cloud", "speaker diarization"
- [ ] TestFlight beta: 50–100 users from Twitter/X + indie dev communities (Week 1–2)
- [ ] ProductHunt launch: Tuesday midnight, "Privacy-first, offline, polyglot meeting recorder" (Week 3)
- [ ] HackerNews Show HN: technical framing around Whisper.cpp + CoreML stack (Week 4)
- [ ] Short-form video: language badge switching EN→TH→EN in real-time (ongoing)

---

## Dependency Graph

```
Extract Color from TranscriptRow ✅ RESOLVED
    ├── Speaker profile persistence — now unblocked
    └── @Observable migration — now unblocked
            └── SwiftData layer — now unblocked
```

---

## 🟡 Medium — ML Model Improvements (Future Sprint)

- [ ] **Re-export WeSpeaker CoreML model with batch=1** · `wespeaker_v2.mlmodelc`
  - Current model has hardcoded batch=3 (`hasShapeFlexibility: "0"`). Rows 1 and 2 of both inputs are computed then immediately discarded by `slice_by_index` in the MIL graph
  - Cost: 4.89 MB wasted per inference × ~4 calls/sec during recording = ~19.6 MB/sec unnecessary allocation
  - Fix: re-export with `coremltools` using `ct.TensorType(shape=(1, 160000))`. Update `waveformBatch = 1` in `SpeakerDiarizationCoreMLService`, simplify `fillBatch`/`fillMask` to single-row
  - Requires: original PyTorch WeSpeaker checkpoint + Python env with `coremltools>=8.3` + validation of embedding quality on new model
  - Effort: M · Agent: `ml-inference-lead`

- [ ] **Add thermal throttling to live pipeline** · `App/AppBackend.swift` + `LiveSessionPipeline`
  - No thermal detection during long meetings — ANE/GPU throttling silently degrades Whisper accuracy
  - Design: `ProcessInfo.thermalStateDidChangeNotification` observer in pipeline; 3 tiers: nominal/fair (full), serious (switch Whisper Normal/Q8, double interrupt window), critical (disable interrupt detection, switch Whisper Fast/Q5)
  - Add `@Published var isThermallyThrottled: Bool` on AppBackend; UI shows subtle indicator when throttled
  - Use 10-second hysteresis to prevent rapid toggling
  - Effort: M · Agent: `ml-inference-lead`

---

## 🟡 Medium — Audio Pipeline Improvements (Queued)

- [ ] **Auto-retranscribe from M4A on session end** · `App/AppBackend.swift`
  - Root cause of "Transcribe Again gives better results": live path sends raw PCM (noisy) to Whisper; M4A path sends AAC-decoded audio (naturally noise-filtered by codec). Prompts and Whisper params are identical — purely audio quality difference
  - Fix: after `masterRecorder.stop()` resolves and M4A is finalized, automatically queue all transcript rows via `queueAutomaticQualityRetranscription(rowID:sessionID:)` — reuses existing M4A path with no new infrastructure
  - Skip if session has 0 rows; existing "Queued for Transcribe Again..." UI handles busy state
  - Effort: S · Agent: `swift-engineer` · ⏳ Queued Sprint 7

---

*Last updated: 2026-02-22 · Sprint 7 in progress — ML audit (vDSP cosine, VAD pre-alloc, resetInterruptState fix, interrupt window 8192, route-change handling), ExportService extraction, NotificationCenter refactor queued*
