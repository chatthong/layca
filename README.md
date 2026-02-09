# Layca (เลขา) - Master App Plan 📝

> **The Ultimate Offline Polyglot Meeting Secretary**

**Project Codename:** `Layca-Core`  
**Version:** 0.5.1 (Live Audio + CoreML VAD + CoreML Speaker Diarization + Chunk Playback)  
**Platforms:** iOS, iPadOS, tvOS, visionOS  
**Core Philosophy:** Offline-first after model setup, privacy-first, chat-first UX

---

## 1. Executive Summary 🚀

**Layca** is a native Apple app for recording meetings, generating transcripts, and reviewing them in a chat-style timeline.

**Key Differentiators:**

1. **Privacy-first local processing:** Core pipeline runs on-device.
2. **Chat-first review:** Transcript appears as speaker bubbles in one timeline.
3. **Audio-linked workflow:** Session audio is stored with transcript metadata for playback/export flows.

---

## 2. Tech Stack 🛠️

### A. Core Engine Strategy

- **Inference target:** `whisper.cpp` integration path (transcription branch still uses placeholder text while runtime integration is pending).
- **Pre-flight behavior:** credits and language prompt are validated before recording.

### B. Audio Stack

- **Current backend:**
  - `AVAudioEngine` live microphone input + waveform stream
  - Native `Silero VAD` via CoreML (`silero-vad-unified-256ms-v6.0.0.mlmodelc`)
  - Native speaker embedding via CoreML (`wespeaker_v2.mlmodelc`)
  - Bundled VAD model in app resources (offline-first), with network/cache fallback
  - Bundled speaker model in app resources (offline-first), with network/cache fallback
  - Chunk merge + persistence + reactive chat updates
- **Remaining integration:**
  - Whisper inference on chunked PCM (replace current placeholder transcript text)

### C. Data Layer

- **Current runtime persistence:** actor-based `SessionStore` + filesystem.
- **Planned long-term persistence:** `SwiftData`.

```text
Documents/
└── Sessions/
    └── {UUID}/
        ├── session_full.m4a
        └── segments.json
```

---

## 3. UI/UX Strategy: Chat-First 💬

- **Chat tab:** Recorder card + live transcript bubbles.
- **Header:** Active chat title supports inline rename.
- **Setting tab:** Hours credit, language focus, iCloud toggle, and purchase restore.
- **Library tab:** Session switcher.
- **New Chat tab role:** Action tab to create a fresh session and return to Chat.
- **Export:** Separate sheet; Notepad-style formatting is export-only.

---

## 4. Architecture & Workflow 🌭

### Phase 1: Pre-Flight

1. Check credit balance.
2. Build language prompt from Language Focus.

### Phase 2: Live Pipeline (Concurrent)

1. **Track 1: Input + Waveform**
   - Capture stream, emit waveform ticks (~0.05s).
   - Keep session master audio file (`session_full.m4a`).
2. **Track 2: VAD slicer**
   - Detect speech/silence, cut chunk after sustained silence.
   - Current defaults: silence cutoff `1.2s`, minimum chunk `3.2s`, max chunk `12s`.
3. **Track 3: Dual AI branch**
   - Branch A: transcription + language ID.
   - Branch B: speaker embedding extraction + cosine matching / new speaker assignment.
4. **Track 4: Merger**
   - Merge branch results into one transcript item.

### Phase 3: Persist + Reactive UI

1. Append transcript into store.
2. UI updates bubbles reactively.
3. Transcript rows keep chunk `startOffset`/`endOffset` for playback.
4. Deduct used credit by chunk duration.
5. Optional sync hook runs in background.

---

## 5. Current Implementation Status 🗺️

### Implemented

#### Dynamic Pre-Flight Backend (Credits + Language Prompt)
- `AppBackend.swift`
- `PreflightService` checks remaining credit and builds prompt text like `This is a meeting in English, Thai.`.

#### Live Pipeline Backend (4-Track Style, Concurrent)
- `AppBackend.swift`
- `Libraries/SileroVADCoreMLService.swift`, `Libraries/SpeakerDiarizationCoreMLService.swift`
- `LiveSessionPipeline` actor emits:
  - waveform updates (visualizer timing)
  - CoreML Silero VAD chunking behavior
  - parallel Whisper branch + Speaker-ID branch
  - merged transcript events (`speaker`, `language`, `text`, `timestamp`)
- Current implementation uses real `AVAudioEngine` + native CoreML Silero VAD + native CoreML speaker diarization.
- Transcription branch is still placeholder text until Whisper runtime is connected.

#### Storage, Update, and Sync Hooks
- `AppBackend.swift`
- `SessionStore` creates `session_full.m4a` + `segments.json`.
- Appends transcript rows, persists segment snapshots, and keeps stable speaker profile (color/avatar) per session.
- Credit deduction per chunk and iCloud-sync hook point are included.

#### App Orchestration + UI Wiring
- `AppBackend.swift`, `ContentView.swift`, `ChatTabView.swift`
- `AppBackend` (`ObservableObject`) now drives recording state, sessions, transcript stream, and language settings.
- Record button uses backend pipeline; chat bubbles update reactively from backend rows.
- Language tag in bubble uses pipeline language code; speaker style is session-stable.
- Chat bubble tap plays only that chunk from `session_full.m4a` using persisted offsets.
- Chunk playback is only enabled when recording is stopped.
- Recorder card hit-testing fix applied so `Record` is tappable.

#### Tests Added
- `AppBackendTests.swift`
- Covered:
  - prompt building from selected languages
  - model fallback behavior
  - speaker profile stability across chunks

### Next

- Replace placeholder transcript generation with real Whisper runtime inference.
- Add VAD confidence/debug telemetry for tuning thresholds in production.
- Add playback UX polish (selected-row highlight / progress / interruption policy).

---

## 6. Documentation

- [Architecture Overview](docs/architecture.md)
- [Database Design](docs/database.md)
- [Model Management](docs/model-management.md)
- [Audio Pipeline](docs/audio-pipeline.md)
- [API Contracts](docs/api-contracts.md)
- [Tab Navigation](docs/tab-navigation.md)
- [Export Notepad Style](docs/export-notepad-style.md)
- [Roadmap](docs/roadmap.md)
