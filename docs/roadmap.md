# Roadmap

## Completed In This Chat

### Dynamic Pre-Flight Backend (Credits + Language Prompt)
- `AppBackend.swift`
- `PreflightService` checks remaining credit and builds prompt like `This is a meeting in English, Thai.`.

### Live Pipeline Backend (4-Track Style, Concurrent)
- `AppBackend.swift`, `Libraries/SileroVADCoreMLService.swift`, `Libraries/SpeakerDiarizationCoreMLService.swift`
- `LiveSessionPipeline` actor emits:
  - waveform updates (visualizer timing)
  - CoreML Silero VAD chunking behavior
  - parallel Whisper branch + CoreML speaker-ID branch
  - merged transcript events (`speaker`, `language`, `text`, `timestamp`)
- Current implementation uses real `AVAudioEngine` + bundled/offline CoreML Silero VAD + bundled/offline CoreML speaker diarization.
- Chunk split defaults are tuned longer (`silenceCutoff=1.2s`, `minChunk=3.2s`, `maxChunk=12s`) to reduce over-splitting.

### Storage, Update, and Sync Hooks
- `AppBackend.swift`
- `SessionStore` creates `session_full.m4a` + `segments.json`.
- Appends transcript rows, persists segment snapshots, and keeps stable speaker profile (color/avatar) per session.
- Credit deduction per chunk and iCloud-sync hook point are included.

### App Orchestration + UI Wiring
- `AppBackend.swift`, `ContentView.swift`, `ChatTabView.swift`
- `AppBackend` (`ObservableObject`) now drives recording state, sessions, transcript stream, and language settings.
- Record button uses backend pipeline; chat bubbles update reactively from backend rows.
- Language tag in bubble uses pipeline language code; speaker style is session-stable.
- Transcript bubble tap now plays only that row's chunk from session audio.
- Playback is disabled while recording, and rows without valid offsets are non-playable.
- Recorder button tap issue fixed by disabling hit-testing on decorative overlays.

### Settings Cleanup (Model UI Removed)
- `SettingTabView.swift`, `ContentView.swift`, `AppBackend.swift`
- Removed Settings model change/download card and model-select callbacks.
- Removed in-app Whisper model-file dependency from backend/UI.

### Tests Added
- `AppBackendTests.swift`
- Covered:
  - prompt building from selected languages
  - credit exhaustion guard behavior
  - speaker profile stability across chunks
- Build + tests validated on iOS simulator.

## Next Priority
1. Replace placeholder transcript generation with real whisper runtime inference.
2. Add playback UX polish (playing-state indicator, active-bubble highlight, scrub constraints).
3. Add resilience/recovery for interrupted recording or processing.
4. Add optional SwiftData mirror/index layer for long-term search/filter use cases.
5. Add configurable VAD/speaker sensitivity tuning in settings.

## Quality Gates
- Keep record disabled when credit pre-flight fails.
- Keep chat updates reactive and incremental.
- Keep per-session speaker style consistent across chunks.
- Keep docs synchronized with runtime behavior.
