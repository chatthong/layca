# Roadmap

## Completed In This Chat

### Dynamic Pre-Flight Backend (Credits + Language Prompt)
- `AppBackend.swift`
- `PreflightService` checks remaining credit and builds prompt:
  - `This is a verbatim transcript of a meeting in [LANGUAGES]. The speakers switch between languages naturally. Transcribe exactly what is spoken in the original language. Do not translate. Context: [KEYWORDS].`
- Added settings-backed context keyword input for prompt context.

### Live Pipeline Backend (4-Track Style, Concurrent)
- `AppBackend.swift`, `Libraries/SileroVADCoreMLService.swift`, `Libraries/SpeakerDiarizationCoreMLService.swift`, `Libraries/WhisperGGMLCoreMLService.swift`
- `LiveSessionPipeline` actor emits:
  - waveform updates (visualizer timing)
  - CoreML Silero VAD chunking behavior
  - CoreML speaker-ID branch
  - merged transcript events (`speaker`, `language`, `text`, `timestamp`)
- Current implementation uses real `AVAudioEngine` + bundled/offline CoreML Silero VAD + bundled/offline CoreML speaker diarization.
- Chunk split defaults are tuned longer (`silenceCutoff=1.2s`, `minChunk=3.2s`, `maxChunk=12s`) to reduce over-splitting.

### Storage, Update, and Sync Hooks
- `AppBackend.swift`
- `SessionStore` creates `session_full.m4a` + `segments.json`.
- Appends transcript rows, persists segment snapshots, and keeps stable speaker profile (color/avatar) per session.
- Credit deduction per chunk and iCloud-sync hook point are included.
- Added row-level transcript text update path for on-demand Whisper inference results.

### App Orchestration + UI Wiring
- `AppBackend.swift`, `ContentView.swift`, `ChatTabView.swift`
- `AppBackend` (`ObservableObject`) now drives recording state, sessions, transcript stream, and language settings.
- Record button uses backend pipeline; chat bubbles update reactively from backend rows.
- Language tag in bubble uses pipeline language code; speaker style is session-stable.
- Transcript bubble tap now plays only that row's chunk from session audio.
- Transcript bubble tap also triggers Whisper transcription for that chunk and patches row text in place.
- Tap transcription now uses Whisper auto language detection (`preferredLanguageCode = "auto"`) and `translate = false`.
- Added stuck-state fix for transcription status (`Transcribing selected chunk...` always clears).
- Added no-speech messaging for empty inference results.
- Added prompt-leak guard: if output echoes prompt instructions, rerun without prompt.
- Playback is disabled while recording, and rows without valid offsets are non-playable.
- Recorder button tap issue fixed by disabling hit-testing on decorative overlays.

### Whisper Startup Reliability Hardening
- `AppBackend.swift`, `Libraries/WhisperGGMLCoreMLService.swift`
- Removed automatic Whisper prewarm on app bootstrap and recording start.
- Whisper context now initializes lazily on first chunk transcription request.
- Default Whisper mode now avoids CoreML encoder startup path to prevent ANE/CoreML plan-build stalls.
- Added opt-in switch for CoreML encoder path via `LAYCA_ENABLE_WHISPER_COREML_ENCODER=1`.
- In default mode, CoreML encoder load-failure logs are expected and non-fatal.

### Settings Cleanup (Model UI Removed)
- `SettingTabView.swift`, `ContentView.swift`, `AppBackend.swift`
- Removed Settings model change/download card and model-select callbacks.
- Added context-keywords input for Whisper `initial_prompt`.

### Tests Added
- `AppBackendTests.swift`
- Covered:
  - prompt building from selected languages
  - credit exhaustion guard behavior
  - speaker profile stability across chunks
- Build validated on iOS simulator.
- `laycaTests` currently has compile failures unrelated to this change (`PreflightService.prepare` callsites missing `focusKeywords`).

## Next Priority
1. Add playback/transcription UX polish (playing-state indicator, active-bubble highlight, transcription-progress state).
2. Add resilience/retry handling for interrupted on-demand transcription jobs.
3. Add resilience/recovery for interrupted recording or processing.
4. Add optional SwiftData mirror/index layer for long-term search/filter use cases.
5. Add configurable VAD/speaker sensitivity tuning in settings.

## Quality Gates
- Keep record disabled when credit pre-flight fails.
- Keep chat updates reactive and incremental.
- Keep per-session speaker style consistent across chunks.
- Keep docs synchronized with runtime behavior.
