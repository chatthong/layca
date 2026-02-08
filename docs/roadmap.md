# Roadmap

## Completed In This Chat

### Dynamic Pre-Flight Backend (Credits + Model Readiness + Language Prompt)
- `AppBackend.swift`
- `ModelManager` resolves model `.bin` paths in `Documents/Models/`, tracks installed/loaded models, and supports fallback model selection.
- `PreflightService` checks remaining credit and builds prompt like `This is a meeting in English, Thai.`.

### Live Pipeline Backend (4-Track Style, Concurrent)
- `AppBackend.swift`
- `LiveSessionPipeline` actor emits:
  - waveform updates (visualizer timing)
  - VAD-like chunking behavior
  - parallel Whisper branch + Speaker-ID branch
  - merged transcript events (`speaker`, `language`, `text`, `timestamp`)
- Current implementation is backend-ready simulation and can be swapped to real `AVAudioEngine` + Silero VAD + `whisper.cpp`.

### Storage, Update, and Sync Hooks
- `AppBackend.swift`
- `SessionStore` creates `session_full.m4a` + `segments.json`.
- Appends transcript rows, persists segment snapshots, and keeps stable speaker profile (color/avatar) per session.
- Credit deduction per chunk and iCloud-sync hook point are included.

### App Orchestration + UI Wiring
- `AppBackend.swift`, `ContentView.swift`, `ChatTabView.swift`
- `AppBackend` (`ObservableObject`) now drives recording state, sessions, transcript stream, and model/language settings.
- Record button uses backend pipeline; chat bubbles update reactively from backend rows.
- Language tag in bubble uses pipeline language code; speaker style is session-stable.
- Recorder button tap issue fixed by disabling hit-testing on decorative overlays.

### Tests Added
- `AppBackendTests.swift`
- Covered:
  - prompt building from selected languages
  - model fallback behavior
  - speaker profile stability across chunks
- Build + tests validated on iOS simulator.

## Next Priority
1. Replace simulated model install with real `URLSessionDownloadTask` using catalog URLs.
2. Replace simulated pipeline internals with real `AVAudioEngine` + VAD + whisper inference.
3. Add playback service to seek session audio from transcript rows.
4. Add resilience/recovery for interrupted recording or processing.
5. Add optional SwiftData mirror/index layer for long-term search/filter use cases.

## Quality Gates
- Keep record disabled when model/credit pre-flight fails.
- Keep chat updates reactive and incremental.
- Keep per-session speaker style consistent across chunks.
- Keep model catalog and docs synchronized when model entries change.
