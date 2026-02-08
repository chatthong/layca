# Layca (เลขา) - Master App Plan 📝

> **The Ultimate Offline Polyglot Meeting Secretary**

**Project Codename:** `Layca-Core`  
**Version:** 0.3.0 (Dynamic Pipeline + Model Catalog Update)  
**Platforms:** iOS, iPadOS, tvOS, visionOS  
**Core Philosophy:** Offline-first after model setup, privacy-first, chat-first UX

---

## 1. Executive Summary 🚀

**Layca** is a native Apple app for recording meetings, generating transcripts, and reviewing them in a chat-style timeline.

**Key Differentiators:**

1. **Tiny install + on-demand AI model:** App stays light; model files are installed later.
2. **Chat-first review:** Transcript appears as speaker bubbles in one timeline.
3. **Audio-linked workflow:** Session audio is stored with transcript metadata for playback/export flows.

---

## 2. Tech Stack 🛠️

### A. Core Engine & Model Strategy

- **Inference target:** `whisper.cpp` integration path (current backend uses simulation hooks).
- **Dynamic model catalog (from Settings):**
  - **Normal AI**
    - file: `ggml-large-v3-turbo-q8_0.bin`
    - URL: `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q8_0.bin?download=true`
  - **Light AI**
    - file: `ggml-large-v3-turbo-q5_0.bin`
    - URL: `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin?download=true`
  - **High Detail AI**
    - file: `ggml-large-v3-turbo.bin`
    - URL: `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin?download=true`
- **Model resolution path:** `Documents/Models/`
- **Pre-flight behavior:** selected model is validated before recording; missing model can fallback to installed model or block recording.

### B. Audio Stack

- **Current backend:** Dynamic live pipeline simulator for waveform, VAD-like chunking, transcript merge, and persistence.
- **Planned production stack:**
  - `AVAudioEngine` for live input + waveform stream
  - VAD (Silero or equivalent) for chunk boundary detection
  - Whisper inference on chunked PCM

### C. Data Layer

- **Current runtime persistence:** actor-based `SessionStore` + filesystem.
- **Planned long-term persistence:** `SwiftData`.

```text
Documents/
├── Models/
│   ├── ggml-large-v3-turbo-q8_0.bin
│   ├── ggml-large-v3-turbo-q5_0.bin
│   └── ggml-large-v3-turbo.bin
└── Sessions/
    └── {UUID}/
        ├── session_full.m4a
        └── segments.json
```

---

## 3. UI/UX Strategy: Chat-First 💬

- **Chat tab:** Recorder card + live transcript bubbles.
- **Header:** Active chat title supports inline rename.
- **Setting tab:** Hours credit, language focus, model selection/download state, iCloud toggle.
- **Library tab:** Session switcher.
- **New Chat tab role:** Action tab to create a fresh session and return to Chat.
- **Export:** Separate sheet; Notepad-style formatting is export-only.

---

## 4. Architecture & Workflow 🌭

### Phase 1: Pre-Flight

1. Check credit balance.
2. Resolve selected model from dynamic catalog.
3. Validate installed model path in `Documents/Models/`.
4. Build language prompt from Language Focus.

### Phase 2: Live Pipeline (Concurrent)

1. **Track 1: Input + Waveform**
   - Capture stream, emit waveform ticks (~0.05s).
   - Keep session master audio file (`session_full.m4a`).
2. **Track 2: VAD slicer**
   - Detect speech/silence, cut chunk after sustained silence.
3. **Track 3: Dual AI branch**
   - Branch A: transcription + language ID.
   - Branch B: speaker matching / new speaker assignment.
4. **Track 4: Merger**
   - Merge branch results into one transcript item.

### Phase 3: Persist + Reactive UI

1. Append transcript into store.
2. UI updates bubbles reactively.
3. Deduct used credit by chunk duration.
4. Optional sync hook runs in background.

---

## 5. Current Implementation Status 🗺️

### Implemented

#### Dynamic Pre-Flight Backend (Credits + Model Readiness + Language Prompt)
- `AppBackend.swift`
- `ModelManager` resolves model `.bin` paths in `Documents/Models/`, tracks installed/loaded models, and supports fallback model selection.
- `PreflightService` checks remaining credit and builds prompt text like `This is a meeting in English, Thai.`.

#### Live Pipeline Backend (4-Track Style, Concurrent)
- `AppBackend.swift`
- `LiveSessionPipeline` actor emits:
  - waveform updates (visualizer timing)
  - VAD-like chunking behavior
  - parallel Whisper branch + Speaker-ID branch
  - merged transcript events (`speaker`, `language`, `text`, `timestamp`)
- Current implementation is backend-ready simulation and is structured for replacing internals with real `AVAudioEngine` + Silero VAD + `whisper.cpp`.

#### Storage, Update, and Sync Hooks
- `AppBackend.swift`
- `SessionStore` creates `session_full.m4a` + `segments.json`.
- Appends transcript rows, persists segment snapshots, and keeps stable speaker profile (color/avatar) per session.
- Credit deduction per chunk and iCloud-sync hook point are included.

#### App Orchestration + UI Wiring
- `AppBackend.swift`, `ContentView.swift`, `ChatTabView.swift`
- `AppBackend` (`ObservableObject`) now drives recording state, sessions, transcript stream, and model/language settings.
- Record button uses backend pipeline; chat bubbles update reactively from backend rows.
- Language tag in bubble uses pipeline language code; speaker style is session-stable.
- Recorder card hit-testing fix applied so `Record` is tappable.

#### Tests Added
- `AppBackendTests.swift`
- Covered:
  - prompt building from selected languages
  - model fallback behavior
  - speaker profile stability across chunks

### Next

- Replace simulated pipeline internals with real `AVAudioEngine` + VAD + Whisper runtime.
- Replace placeholder model install with real `URLSessionDownloadTask` using catalog URLs.
- Add playback seek-by-segment path in app flow.

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
