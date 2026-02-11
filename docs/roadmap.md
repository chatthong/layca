# Roadmap

## Completed In This Chat

### Navigation + Draft Mode Behavior Alignment (iOS + macOS)
- `App/ContentView.swift`, `App/AppBackend.swift`, `Views/Mac/MacProWorkspaceView.swift`
- Updated naming to `Layca Chat` in iOS tab + macOS workspace.
- Kept iOS `New Chat` as dedicated right-side action tab.
- macOS sidebar `Layca Chat` now behaves as draft-open action and shows workspace checkmark only in draft mode.
- App launch now defaults to draft mode on both iOS-family and macOS (no auto-open of last active saved chat).
- `startNewChat()` now resets to draft state; persisted session is created on first record tap.
- Recorder timer now:
  - shows `00:00:00` in draft,
  - shows accumulated duration for saved chats when idle,
  - resumes from previous duration when recording continues on an old chat.

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

### Settings Advanced Zone (Model + Acceleration Controls)
- `Features/Settings/SettingsTabView.swift`, `App/ContentView.swift`, `App/AppBackend.swift`
- Added Advanced Zone controls on iOS-family and macOS settings:
  - `Whisper ggml GPU Decode` toggle
  - `Whisper CoreML Encoder` toggle
  - `Model Switch` (`Fast` / `Normal` / `Pro`)
- Added auto-detected first-launch defaults per device with persisted user overrides.
- Added settings persistence fields for CoreML toggle, GPU toggle, and model profile.

### macOS Native Workspace + Permission Hardening
- `App/ContentView.swift`, `Views/Mac/MacProWorkspaceView.swift`, `layca.xcodeproj/project.pbxproj`
- Added dedicated macOS workspace shell using `NavigationSplitView` and sidebar workspace sections.
- Added desktop-optimized chat/library/settings views for macOS (instead of reusing iOS tab layout).
- Added microphone permission status and actions in macOS settings plus deep-link action from recorder denial state.
- Added macOS codesigning entitlement wiring for sandbox audio input so app appears in Privacy > Microphone after permission request.

### macOS Toolbar Style Alignment (Native Composition)
- `App/ContentView.swift`, `Views/Mac/MacProWorkspaceView.swift`
- Removed top toolbar segmented workspace picker from macOS root split view.
- Moved top-right chat actions to Chat detail toolbar using native SwiftUI composition:
  - `ToolbarItem` for `Share`
  - `ToolbarItemGroup` for `Rename` + `New Chat`
  - `ToolbarItem` for `Info` (switches to `Setting`)
- Applied `.toolbar(removing: .title)` in Chat detail for a clean native toolbar layout.

### Native Theme + Surface Simplification
- `App/ContentView.swift`, `Features/Chat/ChatTabView.swift`, `Features/Library/LibraryTabView.swift`, `Features/Settings/SettingsTabView.swift`, `Views/Components/TranscriptBubbleOptionButton.swift`, `Views/Shared/View+PlatformCompatibility.swift`
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
  - `Features/Settings/SettingsTabView.swift`
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
