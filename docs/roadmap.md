# Roadmap

## Completed In This Chat

### Dynamic Pre-Flight Backend (Credits + Language Prompt)
- `App/AppBackend.swift`
- `PreflightService` checks remaining credit and builds prompt:
  - `This is a verbatim transcript of a meeting in [LANGUAGES]. The speakers switch between languages naturally. Transcribe exactly what is spoken in the original language, including profanity, violence, drug terms, and other sensitive words. Do not censor, mask, or replace words. Do not translate. Context: [KEYWORDS].`
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

### Storage, Update, and Sync Hooks
- `App/AppBackend.swift`
- `SessionStore` creates `session_full.m4a` + `segments.json`.
- Appends transcript rows, persists segment snapshots, and keeps stable speaker profile (color/avatar) per session.
- Credit deduction per chunk and iCloud-sync hook point are included.
- Added row-level transcript text update path for automatic queued Whisper inference results.

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
  - "Transcribe Again" retry action
- Bubble long-press is disabled while recording and while queued/active transcription work is running.
- Extracted bubble-option UI logic into dedicated component file:
  - `Views/Components/TranscriptBubbleOptionButton.swift`
- Chunk transcription now runs automatically in backend queue order and patches row text in place.
- Queued transcription uses Whisper auto language detection (`preferredLanguageCode = "auto"`) and `translate = false`.
- Added stuck-state fix for transcription status (transcribing indicator always clears).
- Added no-speech messaging for empty inference results.
- Added prompt-leak guard: if output echoes prompt instructions, rerun without prompt.
- Playback is disabled while recording, and rows without valid offsets are non-playable.
- Recorder button tap issue fixed by disabling hit-testing on decorative overlays.

### Automatic Chunk Transcription Queue
- `App/AppBackend.swift`, `Features/Chat/ChatTabView.swift`
- Removed transcription trigger from transcript-bubble tap (tap remains playback-only).
- Added serial queue processing so finished chunks are transcribed one-by-one automatically.
- Added queue dedup guards to avoid duplicate transcription jobs per row.
- Updated placeholder/transcribing UI copy to reflect automatic queue processing.

### Whisper Startup Reliability Hardening
- `App/AppBackend.swift`, `Libraries/WhisperGGMLCoreMLService.swift`
- Removed automatic Whisper prewarm on app bootstrap and recording start.
- Whisper context now initializes lazily on first chunk transcription request.
- Default Whisper mode now avoids CoreML encoder startup path to prevent ANE/CoreML plan-build stalls.
- Added opt-in switch for CoreML encoder path via `LAYCA_ENABLE_WHISPER_COREML_ENCODER=1`.
- In default mode, CoreML encoder load-failure logs are expected and non-fatal.

### Settings Cleanup (Model UI Removed)
- `Features/Settings/SettingsTabView.swift`, `App/ContentView.swift`, `App/AppBackend.swift`
- Removed Settings model change/download card and model-select callbacks.
- Added context-keywords input for Whisper `initial_prompt`.

### macOS Native Workspace + Permission Hardening
- `App/ContentView.swift`, `Views/Mac/MacProWorkspaceView.swift`, `layca.xcodeproj/project.pbxproj`
- Added dedicated macOS workspace shell using `NavigationSplitView`, sidebar sections, and toolbar control group actions.
- Added desktop-optimized chat/library/settings views for macOS (instead of reusing iOS tab layout).
- Added microphone permission status and actions in macOS settings plus deep-link action from recorder denial state.
- Added macOS codesigning entitlement wiring for sandbox audio input so app appears in Privacy > Microphone after permission request.

### Tests Added
- `AppBackendTests.swift`
- Covered:
  - prompt building from selected languages
  - credit exhaustion guard behavior
  - speaker profile stability across chunks
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
  - `Views/Shared/View+LiquidGlassStyle.swift`
  - `Views/Shared/View+PlatformCompatibility.swift`
- Extracted domain models into `Models/Domain/`:
  - `Models/Domain/FocusLanguage.swift`
  - `Models/Domain/ChatSession.swift`
  - `Models/Domain/TranscriptRow.swift`
- Moved runtime model assets to `Models/RuntimeAssets/`.

## Next Priority
1. Add playback/transcription UX polish (playing-state indicator, active-bubble highlight, transcription-progress state).
2. Add resilience/retry handling for interrupted queued transcription jobs.
3. Add resilience/recovery for interrupted recording or processing.
4. Add optional SwiftData mirror/index layer for long-term search/filter use cases.
5. Add configurable VAD/speaker sensitivity tuning in settings.

## Quality Gates
- Keep record disabled when credit pre-flight fails.
- Keep chat updates reactive and incremental.
- Keep per-session speaker style consistent across chunks.
- Keep docs synchronized with runtime behavior.
