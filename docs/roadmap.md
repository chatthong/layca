# Roadmap

## Completed In This Chat

### Export Sheet Detail-Step Polish (iOS + macOS)
- `Features/Share/ExportSheetFlowView.swift`
- Export format preview in detail steps is intentionally shorter (line cap reduced from `14` to `11`) with trailing ellipsis when truncated.
- macOS `Actions` now keeps `Share` and `Copy` on a single horizontal row.

### Export Format Expansion + Real File-Type Sharing
- `Features/Share/ExportSheetFlowView.swift`, `App/ContentView.swift`
- Added new export style: `Video Subtitles (.srt)` with SubRip cue output.
- `Share` now writes and shares a temporary file URL using style-specific extensions (`.txt`, `.md`, `.srt`) instead of sharing only raw text payload.
- Kept `Notepad Minutes` and `Plain Text` as separate styles with clear behavioral split:
  - `Notepad Minutes` keeps title/date header + speaker/timestamp/language format
  - `Plain Text` now outputs only raw message text
- `Notepad Minutes` header now includes an extra blank spacer line after `Created:` for cleaner readability in preview/export.

### Settings Sheet Flow Refresh (iOS + macOS)
- `App/ContentView.swift`, `Features/Share/SettingsSheetFlowView.swift`, `Views/Mac/MacProWorkspaceView.swift`
- `Settings` now opens as a single modal sheet from app shell actions (instead of switching to a dedicated settings detail workspace).
- Settings navigation is now a single internal multi-step flow using one navigation stack (no nested settings sub-sheets).
- iOS dismiss/back control placement follows multi-step sheet guidance:
  - root step: dismiss (`x`) on leading side
  - deeper steps: back on leading side, dismiss (`x`) on trailing side
- macOS step pages were updated to grouped native form/list styling to avoid broken second-level layout rendering.

### Settings Information Architecture Tuning
- `Features/Share/SettingsSheetFlowView.swift`
- Removed `Model and Display` sub-step.
- `Time Display` is now a dedicated sub-step under `General`.
- Renamed settings section `Runtime` to `Advanced`.
- `Advanced` now has two sub-steps:
  - `Acceleration`
    - `Whisper ggml GPU Decode`
    - `Whisper CoreML Encoder`
  - `Offline Model Switch`

### iOS Compact Toolbar Overflow Icon Fix
- `Features/Chat/ChatTabView.swift`
- iOS top-right header actions remain a native grouped control (`Play` + `More`) when space is available.
- In compact toolbar width (for example long chat title), the grouped control now collapses into a single visible ellipsis overflow control instead of appearing as an empty button.
- Action/menu behavior is unchanged (`Play`, `Share`, `Rename`, `Delete`).

### iOS Chat-Title Pill Sizing + Truncation Tuning
- `Features/Chat/ChatTabView.swift`
- Kept chat title in leading header position on iOS (not center placement).
- Non-edit chat-title pill now auto-sizes by title length with min/max bounds.
- Short titles keep readable width; long titles tail-truncate only after hitting max safe width (prevents `...` overflow toolbar collapse).

### Player Mode + Main Timer UX (iOS + macOS)
- `App/AppBackend.swift`, `Features/Chat/ChatTabView.swift`, `Views/Mac/MacProWorkspaceView.swift`
- Transcript-bubble playback now drives recorder player mode on both iOS-family and macOS.
- Recorder action changes to `Stop` while playback is active, and tapping it stops playback.
- Recorder tint now uses state color:
  - red while recording
  - green while playback is active
- Main timer shows playback time remaining (countdown) in player mode.
- Recorder subtitle switches to segment range text (`mm:ss → mm:ss`) in player mode.
- Draft idle state now shows starter copy in the main timer slot:
  - `Tap to start record` (iOS/iPadOS)
  - `Click to start record` (macOS)

### iOS Drawer Swipe Capture Reliability
- `App/ContentView.swift`
- Replaced edge-only/parent-only swipe dependency with global iOS pan capture wiring.
- Sidebar can now open by right-swiping from anywhere in the app detail surface, including over chat bubble/dialog regions.
- Keeps horizontal-intent filtering and existing close behavior (`drag left` / dimmed-area tap).

### Chat Follow Mode + macOS Width Guard
- `Features/Chat/ChatTabView.swift`, `Views/Mac/MacProWorkspaceView.swift`, `App/ContentView.swift`
- Live transcript updates during recording no longer force auto-scroll by default.
- `New message` button appears for pending updates; tapping it scrolls to bottom and enables follow mode.
- Follow mode remains active until user scrolls away from bottom.
- macOS split detail column now enforces a minimum width guard to keep transcript layout readable during resize.
- macOS chat-title edit form uses a compact width to prevent oversized toolbar capsules.

### Navigation + Draft Mode Behavior Alignment (iOS + macOS)
- `App/ContentView.swift`, `App/AppBackend.swift`, `Views/Mac/MacProWorkspaceView.swift`
- Updated naming to `Layca Chat` in iOS/iPadOS workspace and macOS workspace.
- macOS sidebar `Layca Chat` now behaves as draft-open action and shows workspace checkmark only in draft mode.
- App launch now defaults to draft mode on both iOS-family and macOS (no auto-open of last active saved chat).
- `startNewChat()` now resets to draft state; persisted session is created on first record tap.
- Recorder timer now:
  - shows draft starter copy before first recording starts,
  - shows accumulated duration for saved chats when idle,
  - resumes from previous duration when recording continues on an old chat.

### iOS Drawer Sidebar + Recording Glass Alignment
- `App/ContentView.swift`, `Views/Components/IOSWorkspaceSidebarView.swift`, `Features/Chat/ChatTabView.swift`
- Replaced iOS/iPadOS tab-first shell with a swipeable drawer sidebar.
- Moved drawer trigger into chat header leading controls (before chat title).
- Sidebar top area (`Search` + `New Chat`) is fixed; `Workspace` + `Recent Chats` are scrollable.
- `Recent Chats` rows use the same action group (`Rename`, `Share this chat`, `Delete`).
- Recording accessory glass now uses recorder state tint:
  - red while recording
  - green in player mode during transcript playback

### Chat Header Rename UX Hardening
- `Features/Chat/ChatTabView.swift`, `Views/Mac/MacProWorkspaceView.swift`, `Views/Components/IOSWorkspaceSidebarView.swift`
- iOS chat header control order is aligned as sidebar toggle first, then chat title, with a trailing native control group (`Play` + `More`).
- During chat-title inline edit, non-title header controls are hidden to avoid toolbar collapse/overlap.
- Tapping outside the title edit form now cancels editing on both iOS and macOS (content area, sidebar interactions, and focus-loss path).

### Dynamic Pre-Flight Backend (Credits + Language Prompt)
- `App/AppBackend.swift`
- `PreflightService` checks remaining credit and builds prompt:
  - `STRICT VERBATIM MODE. Never translate under any condition. Never summarize. Never rewrite... Context: [KEYWORDS].`
- Added settings-backed context keyword input for prompt context.

### Live Pipeline Backend (4-Track Style, Concurrent)
- `App/AppBackend.swift`, `Libraries/SileroVADCoreMLService.swift`, `Libraries/SpeakerDiarizationCoreMLService.swift`, `Libraries/WhisperGGMLCoreMLService.swift`
- `LiveSessionPipeline` actor emits:
  - waveform updates (visualizer timing)
  - CoreML Silero VAD chunking behavior
  - CoreML speaker-ID branch
  - merged transcript events (`speaker`, `language`, `text`, `timestamp`)
- Current implementation uses real `AVAudioEngine` + bundled/offline CoreML Silero VAD + bundled/offline CoreML speaker diarization.
- Chunk split defaults are tuned longer (`silenceCutoff=1.2s`, `minChunk=3.2s`, `maxChunk=12s`) to reduce over-splitting.
- Speaker fallback matching upgraded to multi-feature signature (amplitude + ZCR + RMS) to improve multi-speaker separation when CoreML speaker inference is unavailable.

### Storage, Update, and Sync Hooks
- `App/AppBackend.swift`
- `SessionStore` creates `session_full.m4a` + `segments.json` + `session.json`.
- Appends transcript rows, persists segment snapshots, and keeps stable speaker profile (color/avatar) per session.
- Credit deduction per chunk and iCloud-sync hook point are included.
- Added row-level transcript text update path for automatic queued Whisper inference results.

### Durable Session + Settings Persistence Across Relaunch
- `App/AppBackend.swift`
- Extended `SessionStore` persistence:
  - adds per-session metadata file `session.json`
  - persists row snapshots with stable row IDs and bubble metadata
  - reloads all sessions from `Documents/Sessions/{UUID}` on app startup
  - supports session delete by removing in-memory row + filesystem folder
- Added `AppSettingsStore` (`UserDefaults`) for persisted:
  - language focus
  - language search text
  - context keywords
  - credit counters
  - iCloud toggle
  - active session ID
  - chat counter

### App Orchestration + UI Wiring
- `App/AppBackend.swift`, `App/ContentView.swift`, `Features/Chat/ChatTabView.swift`
- `AppBackend` (`ObservableObject`) now drives recording state, sessions, transcript stream, and language settings.
- Record button uses backend pipeline; chat bubbles update reactively from backend rows.
- Language tag in bubble uses pipeline language code; speaker style is session-stable.
- Transcript bubble tap now plays only that row's chunk from session audio.
- Added transcript-bubble long-press action menu:
  - manual transcript edit
  - speaker rename (sync all rows by `speakerID`)
  - change row speaker to another existing speaker profile
  - "Transcribe Again" submenu:
    - `Transcribe Auto`
    - `Transcribe in <Focus Language>` (selected focus languages only)
- Bubble long-press is disabled while recording and while queued/active transcription work is running.
- Extracted bubble-option UI logic into dedicated component file:
  - `Views/Components/TranscriptBubbleOptionButton.swift`
- Chunk transcription now runs automatically in backend queue order and patches row text in place.
- Queued transcription uses Whisper auto language detection (`preferredLanguageCode = "auto"`) and `translate = false`.
- Added stuck-state fix for transcription status (transcribing indicator always clears).
- Added no-speech handling that removes unusable placeholder rows instead of rendering `No speech detected in this chunk.`
- Added prompt-leak guard: if output echoes prompt instructions, rerun without prompt.
- Added transcription quality classification (`acceptable` / `weak` / `unusable`) to trigger retry behavior and reduce junk outputs (e.g., `-`, `foreign`).
- Playback is disabled while recording, and rows without valid offsets are non-playable.
- Manual `Transcribe Again` is currently gated while recording (`Stop recording before running Transcribe Again.`).
- Added manual language override path for retranscribe (`preferredLanguageCodeOverride`) with forced-language queue payload.
- Added forced `TH` / `EN` script validation for manual retranscribe:
  - retry once without prompt when script mismatches
  - keep existing text when mismatch persists
- Removed low-confidence warning banner for manual keep-existing fallback.
- Recorder button tap issue fixed by disabling hit-testing on decorative overlays.

### Automatic Message Transcription Queue
- `App/AppBackend.swift`, `Features/Chat/ChatTabView.swift`
- Removed transcription trigger from transcript-bubble tap (tap remains playback-only).
- Added serial queue processing so finished chunks are transcribed one-by-one automatically.
- Added queue dedup guards to avoid duplicate transcription jobs per row.
- Updated placeholder/transcribing UI copy to reflect automatic queue processing (`Message queued for automatic transcription...`).

### Whisper Startup + Runtime Performance Controls
- `App/AppBackend.swift`, `Libraries/WhisperGGMLCoreMLService.swift`
- Added independent acceleration toggles and model profile controls:
  - `LAYCA_ENABLE_WHISPER_COREML_ENCODER`
  - `LAYCA_ENABLE_WHISPER_GGML_GPU_DECODE`
- Added iOS safety override flag:
  - `LAYCA_FORCE_WHISPER_COREML_ENCODER_IOS`
- Added runtime model profiles:
  - `Fast` -> `ggml-large-v3-turbo-q5_0.bin`
  - `Normal` -> `ggml-large-v3-turbo-q8_0.bin`
  - `Pro` -> `ggml-large-v3-turbo.bin`
- Runtime now logs resolved acceleration mode (`Model: Fast/Normal/Pro, CoreML encoder: ON/OFF, ggml GPU decode: ON/OFF`).
- Added ggml GPU decode fallback path to CPU decode when GPU context init fails.
- Added background Whisper prewarm after runtime preference apply to reduce first-transcription cold-start delay.

### Settings Advanced + Time Display Sub-Steps
- `Features/Share/SettingsSheetFlowView.swift`, `App/ContentView.swift`, `App/AppBackend.swift`
- Added settings controls on iOS-family and macOS settings:
  - `General > Time Display` (`Friendly` / `Hybrid` / `Professional`) for main timer only
  - `Advanced > Acceleration`:
    - `Whisper ggml GPU Decode` toggle
    - `Whisper CoreML Encoder` toggle
  - `Advanced > Offline Model Switch` (`Fast` / `Normal` / `Pro`)
- Added auto-detected first-launch defaults per device with persisted user overrides.
- Added settings persistence fields for CoreML toggle, GPU toggle, model profile, and main timer display style.

### macOS Native Workspace + Permission Hardening
- `App/ContentView.swift`, `Views/Mac/MacProWorkspaceView.swift`, `layca.xcodeproj/project.pbxproj`
- Added dedicated macOS workspace shell using `NavigationSplitView` and sidebar workspace sections.
- Added desktop-optimized chat/library/settings views for macOS (instead of reusing iOS mobile layout).
- Added microphone permission status and actions in macOS settings plus deep-link action from recorder denial state.
- Added macOS codesigning entitlement wiring for sandbox audio input so app appears in Privacy > Microphone after permission request.

### macOS Toolbar Style Alignment (Native Composition)
- `App/ContentView.swift`, `Views/Mac/MacProWorkspaceView.swift`
- Removed top toolbar segmented workspace picker from macOS root split view.
- Current native composition keeps inline chat-title rename + trailing native control group (`Play` + `More`) in Chat detail.
- `New Chat` and `Settings` are now sidebar-driven actions on macOS.

### Native Theme + Surface Simplification
- `App/ContentView.swift`, `Features/Chat/ChatTabView.swift`, `Features/Library/LibraryTabView.swift`, `Features/Share/SettingsSheetFlowView.swift`, `Views/Components/TranscriptBubbleOptionButton.swift`, `Views/Shared/View+PlatformCompatibility.swift`
- iOS-family backgrounds switched to plain `systemBackground` (removed live backdrop on iOS-family screens).
- Card and control surfaces now use native SwiftUI material fills instead of custom liquid-card wrappers.
- iOS-family appearance now follows automatic device light/dark switching.
- Removed custom shared helper:
  - `Views/Shared/View+LiquidGlassStyle.swift`

### Library + Sidebar Chat Actions
- `Features/Library/LibraryTabView.swift`, `Views/Mac/MacProWorkspaceView.swift`, `App/ContentView.swift`, `App/AppBackend.swift`
- Added long-press/right-click action group on Library chat rows:
  - `Rename`
  - `Share this chat`
  - `Delete`
- Added same action group on macOS `Recent Chats` sidebar rows.
- Rename/delete actions are wired to persisted `SessionStore` state; share action exports plain-text transcript payload.

### Tests Added
- `AppBackendTests.swift`
- Covered:
  - prompt building from selected languages
  - credit exhaustion guard behavior
  - speaker profile stability across chunks
  - persisted session reload from disk
  - app settings store round-trip
  - session delete removes store row + session folder
- Build validated on iOS simulator and macOS destination.

### Project Structure Cleanup
- Reorganized app orchestration files into `App/`:
  - `App/laycaApp.swift`
  - `App/ContentView.swift`
  - `App/AppBackend.swift`
- Reorganized UI feature files into `Features/`:
  - `Features/Chat/ChatTabView.swift`
  - `Features/Library/LibraryTabView.swift`
  - `Features/Share/ExportSheetFlowView.swift`
  - `Features/Share/SettingsSheetFlowView.swift`
- Extracted shared UI helpers into `Views/Shared/`:
  - `Views/Shared/LiquidBackdrop.swift`
  - `Views/Shared/View+PlatformCompatibility.swift`
- Extracted domain models into `Models/Domain/`:
  - `Models/Domain/FocusLanguage.swift`
  - `Models/Domain/ChatSession.swift`
  - `Models/Domain/TranscriptRow.swift`
- Moved runtime model assets to `Models/RuntimeAssets/`.

## Next Priority
1. Add playback/transcription UX polish (playing-state indicator, active-bubble highlight, transcription-progress state).
2. Improve recording-time `Transcribe Again` behavior so queued manual retries do not wait for stop.
3. Add resilience/recovery for interrupted recording or processing.
4. Add optional SwiftData mirror/index layer for long-term search/filter use cases.
5. Add configurable VAD/speaker sensitivity tuning in settings.

## Quality Gates
- Keep record disabled when credit pre-flight fails.
- Keep chat updates reactive and incremental.
- Keep per-session speaker style consistent across chunks.
- Keep docs synchronized with runtime behavior.
