# Layca — Task List

> Source: `docs/team-explorer-report.md` (2026-02-21 multi-agent audit)
> Format: `- [ ]` pending · `- [x]` done · blocked tasks noted inline
> Update this file as work completes.

---

## 🚀 Active Priorities — Work On These Now

User-defined priorities. Do these before anything else in the codebase.

- [ ] **Real-time speaker interrupt detection** · `Libraries/SpeakerDiarizationCoreMLService.swift` + pipeline
  - Current behavior: speaker boundary cut uses a 1.0s backtrack + stability guard, and `minSamplesForInference = 24_000` (1.5s) means the diarizer can't fire until 1.5s of audio has accumulated — so interruptions go undetected until the next VAD chunk ends
  - Goal: cut speaker label the moment a new voice interrupts mid-sentence, not after silence
  - Approach:
    1. Add a sliding-window embedding comparison inside `LiveSessionPipeline` — every ~256ms (4_096 samples), extract a short embedding and compare it to the current speaker's profile via cosine distance
    2. If cosine distance crosses a threshold (e.g. > 0.35) for two consecutive windows → fire an early boundary cut, bypassing the stability guard
    3. Tune `minSamplesForInference` vs fast-path: keep the full 1.5s path for low-confidence situations, use the fast-path only when distance is high-confidence (> 0.5)
    4. Test on overlapping-speech recordings; measure false-positive rate vs latency improvement
  - Files: `Libraries/SpeakerDiarizationCoreMLService.swift`, `Libraries/LiveSessionPipeline.swift` (or equivalent pipeline coordinator), `docs/audio-pipeline.md`
  - Effort: M · Agent: `swift-engineer`

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

- [ ] **Fix ForEach crash risk** · `MacProWorkspaceView.swift:154`
  - `ForEach(0..<sessions.count, id: \.self)` crashes if sessions mutates during render
  - Fix: `ForEach(sessions, id: \.id)` — search whole codebase for same pattern
  - Effort: S · Agent: `swift-engineer`

- [ ] **Extract `Color` out of `TranscriptRow`** · `Models/Domain/TranscriptRow.swift:14`
  - `avatarPalette: [Color]` — SwiftUI.Color is not Codable or Sendable
  - Blocks: SwiftData migration, @Observable migration, speaker profile persistence
  - Fix: Create `SpeakerProfileStore` mapping speakerID → palette index (Int into fixed array)
  - Effort: L · Agent: `swift-engineer`

---

## 🔴 High Priority — Bugs & Regressions

Small fixes, high impact. Can be done in any order.

- [ ] **Set Settings sheet default to `.large` detent** · `App/ContentView.swift`
  - `.presentationDetents([.medium, .large])` clips multi-step settings at medium
  - Fix: change to `[.large]` or make `.large` first
  - Effort: S · Agent: `apple-design-lead`

- [ ] **Fix waveform bars color state** · `Features/Chat/ChatTabView.swift` `waveformPanel`
  - Bars always show `Color.red.opacity(0.78)` — should match recording state
  - Fix: use `recorderActionColor` (already computed) as bar fill
  - Effort: S · Agent: `apple-design-lead`

- [ ] **Unify "Pause" vs "Stop" vocabulary**
  - `recorderCard` (macOS) says "Pause" during recording; iOS accessory says "Stop"
  - Decide one word. "Stop" is correct (it finalizes the chunk, not pauses)
  - Effort: S · Agent: `apple-design-lead`

- [ ] **Add haptic feedback on record start/stop** · `App/AppBackend.swift`
  - No haptics exist — DHH users cannot feel state change
  - Fix: `UIImpactFeedbackGenerator(style: .medium).impactOccurred()` at toggle transitions
  - Also: `.heavy` impact on error (credit exhausted)
  - Effort: S · Agent: `accessibility-lead`

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

- [ ] **Replace hardcoded RGB colors with adaptive Color assets**
  - `RecordingSpectrumBubble`: `Color(red: 0.20, green: 0.49, blue: 0.95)` breaks dark mode
  - `ChatTabView` macOS background gradient: `Color(red: 0.91, ...)` breaks dark mode
  - Fix: create named color assets in `Assets.xcassets` with light/dark variants
  - Effort: S · Agent: `apple-design-lead`

- [ ] **Replace `titleDisplayCharacterWidth` pixel hack** · `ChatTabView.swift:8`
  - `titleDisplayCharacterWidth: CGFloat = 9` breaks for Thai, Arabic, CJK (wider chars)
  - Fix: use `ViewThatFits` or natural button sizing with `.frame(maxWidth:)` cap
  - Effort: M · Agent: `apple-design-lead`

- [ ] **Fix iPadOS layout — use NavigationSplitView** · `App/ContentView.swift`
  - iPadOS uses the phone-style drawer — wrong for large screen
  - Fix: check `horizontalSizeClass == .regular` → use macOS-style `NavigationSplitView`
  - Effort: M · Agent: `apple-design-lead`

- [ ] **Fix DispatchQueue focus retries** · `MacProWorkspaceView.swift` `requestTitleFieldFocus()`
  - Three `asyncAfter` calls (0.0s, 0.08s, 0.2s) fight SwiftUI focus — fragile hack
  - Fix: `.task(id: isEditingTitle) { if isEditingTitle { isTitleFieldFocused = true } }`
  - Same issue in `ChatTabView.swift` `beginTitleRename()`
  - Effort: S · Agent: `swift-engineer`

- [ ] **Add play affordance to transcript bubbles**
  - No visual hint that bubbles are tappable for playback
  - Fix: show a subtle `play.circle` icon on bubbles where `isTranscriptBubblePlayable`
  - Effort: S · Agent: `apple-design-lead`

---

## 🟡 Medium — Code Quality & Architecture

- [ ] **Move MasterAudioRecorder file I/O off @MainActor** · `App/AppBackend.swift`
  - `stop()` does temp file creation + segment merge on main thread — UI stutter risk
  - Fix: detached `Task` or background actor for the merge/finalize work
  - Effort: M · Agent: `swift-engineer`

- [ ] **Extract ExportService from ContentView** · `App/ContentView.swift`
  - ~200 lines of export logic (SRT, Markdown, NotepadMinutes, PlainText) in ContentView
  - Fix: new file `Services/ExportService.swift` with a pure struct — makes it testable
  - Effort: M · Agent: `swift-engineer`

- [ ] **Extract focusLanguages catalog** · `App/ContentView.swift`
  - 96-language array inline as computed property — recomputed on every render
  - Fix: `static let all: [FocusLanguage]` in `Models/Domain/FocusLanguage+Catalog.swift`
  - Effort: S · Agent: `swift-engineer`

- [ ] **Replace NotificationCenter rename-cancel with environment** · `ChatTabView.swift:198`
  - `NotificationCenter.publisher(for: "LaycaCancelTitleRenameEditing")` is fragile coupling
  - Fix: `@FocusedValue` or pass cancel closure via environment
  - Effort: S · Agent: `swift-engineer`

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

- [ ] **Implement iCloud sync (CloudKit)** · `App/AppBackend.swift`
  - Sync: session.json + segments.json metadata only (not M4A audio — too large)
  - Use `NSUbiquitousKeyValueStore` for small data or `NSPersistentCloudKitContainer` with SwiftData
  - Toggle already exists in Settings — wire it to actual sync behavior
  - Effort: L · Agent: `swift-engineer`

- [ ] **Speaker profile persistence across sessions** · blocked by: Extract Color from TranscriptRow
  - Persist speaker voice embeddings + user-assigned names in shared `profiles.json`
  - Match incoming embeddings against known profiles at session start
  - Effort: L · Agent: `swift-engineer`

---

## 🟢 Features — Platform & Polish

- [ ] **Migrate AppBackend to @Observable macro** · blocked by: Extract Color from TranscriptRow
  - Replace `@MainActor ObservableObject` + prop drilling with `@Observable` + `.environment()`
  - Eliminates the 20+ parameter init in ChatTabView
  - Effort: L · Agent: `swift-engineer`

- [ ] **Add SwiftData persistence layer**
  - Mirror filesystem JSON to SwiftData for search, filtering, and CloudKit sync
  - Requires: Color extracted from TranscriptRow (no SwiftUI types in models)
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
Extract Color from TranscriptRow (#2 critical)
    ├── blocks: Speaker profile persistence
    └── blocks: @Observable migration
            └── blocks: SwiftData layer
```

---

*Last updated: 2026-02-21 · Source: docs/team-explorer-report.md*
