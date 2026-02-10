# Layca (เลขา) - Master App Plan 📝

> **The Ultimate Offline Polyglot Meeting Secretary**

**Project Codename:** `Layca-Core`  
**Version:** 0.5.2 (Live Audio + CoreML VAD + CoreML Speaker Diarization + Automatic Queued Whisper Chunk Transcription)  
**Platforms:** iOS, iPadOS, macOS, tvOS, visionOS  
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

- **Inference target:** `whisper.cpp` with automatic queued chunk transcription and optional CoreML encoder acceleration (`ggml-large-v3-turbo-encoder.mlmodelc`).
- **Decoder model:** `ggml-large-v3-turbo.bin` bundled in app resources (with cache/download fallback).
- **Model source layout in project:** `xcode/layca/Models/RuntimeAssets/` (copied into app resources at build time).
- **Whisper startup mode:** no automatic prewarm on app launch; transcription engine initializes lazily on first queued chunk.
- **CoreML encoder mode:** disabled by default for startup reliability; can be re-enabled with `LAYCA_ENABLE_WHISPER_COREML_ENCODER=1`.
- **Pre-flight behavior:** credits and language prompt are validated before recording.

### B. Audio Stack

- **Current backend:**
  - `AVAudioEngine` live microphone input + waveform stream
  - Native `Silero VAD` via CoreML (`silero-vad-unified-256ms-v6.0.0.mlmodelc`)
  - Native speaker embedding via CoreML (`wespeaker_v2.mlmodelc`)
  - Bundled VAD model in app resources (offline-first), with network/cache fallback
  - Bundled speaker model in app resources (offline-first), with network/cache fallback
  - Chunk merge + persistence + reactive chat updates
- **Current transcription mode:**
  - Chunk transcription runs automatically in a serial queue (one-by-one) as chunks are produced.

### C. Data Layer

- **Current runtime persistence:** actor-based `SessionStore` + filesystem snapshots (`session.json`, `segments.json`) with startup reload.
- **Current settings persistence:** `UserDefaults`-backed app settings snapshot (language focus, credits, iCloud toggle, active chat, chat counter).
- **Planned long-term persistence:** `SwiftData`.

```text
Documents/
└── Sessions/
    └── {UUID}/
        ├── session_full.m4a
        ├── session.json
        └── segments.json
```

---

## 3. UI/UX Strategy: Chat-First 💬

- **iOS/iPadOS/visionOS/tvOS shell:** `TabView` with `Chat`, `Library`, `Setting`, plus a dedicated `New Chat` action tab.
- **macOS shell:** native `NavigationSplitView` workspace with sidebar sections (`Chat`, `Library`, `Setting`) and no top segmented workspace picker.
- **Chat workspace:** Recorder card + live transcript bubbles.
- **Header/session actions:** macOS chat detail toolbar uses Landmarks-style liquid-glass toolbar items: `Share`, grouped `Rename` + `New Chat`, and `Info` (opens `Setting`).
- **Settings workspace:** Hours credit, language focus, context keywords, iCloud toggle, purchase restore, and macOS microphone access controls.
- **Library workspace:** Session switcher with long-press/right-click action group (`Rename`, `Share this chat`, `Delete`) on session rows.
- **macOS recent chats sidebar:** Same long-press/right-click action group (`Rename`, `Share this chat`, `Delete`).
- **Export:** Separate sheet; Notepad-style formatting is export-only.

---

## 4. Architecture & Workflow 🌭

### Phase 1: Pre-Flight

1. Check credit balance.
2. Build Whisper initial prompt from Language Focus + context keywords.

### Phase 2: Live Pipeline (Concurrent)

1. **Track 1: Input + Waveform**
   - Capture stream, emit waveform ticks (~0.05s).
   - Keep session master audio file (`session_full.m4a`).
2. **Track 2: VAD slicer**
   - Detect speech/silence, cut chunk after sustained silence.
   - Current defaults: silence cutoff `1.2s`, minimum chunk `3.2s`, max chunk `12s`.
3. **Track 3: Speaker branch**
   - CoreML speaker embedding extraction + cosine matching / new speaker assignment.
4. **Track 4: Merger**
   - Store speaker/language metadata plus chunk offsets and deferred-transcript placeholder text.

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
- `App/AppBackend.swift`
- `PreflightService` checks remaining credit and builds prompt text:
  - `This is a verbatim transcript of a meeting in [LANGUAGES]. The speakers switch between languages naturally. Transcribe exactly what is spoken in the original language, including profanity, violence, drug terms, and other sensitive words. Do not censor, mask, or replace words. Do not translate. Context: [KEYWORDS].`

#### Live Pipeline Backend (4-Track Style, Concurrent)
- `App/AppBackend.swift`
- `Libraries/SileroVADCoreMLService.swift`, `Libraries/SpeakerDiarizationCoreMLService.swift`, `Libraries/WhisperGGMLCoreMLService.swift`
- `LiveSessionPipeline` actor emits:
  - waveform updates (visualizer timing)
  - CoreML Silero VAD chunking behavior
  - speaker-ID branch
  - merged transcript events (`speaker`, `language`, `text`, `timestamp`)
- Current implementation uses real `AVAudioEngine` + native CoreML Silero VAD + native CoreML speaker diarization.
- Chunk rows are persisted with placeholder transcript text and are transcribed by Whisper in automatic queue order.
- Automatic transcription runs with `preferredLanguageCode = "auto"` and `translate = false` to keep original spoken language (no translation).
- Whisper prompt-leak fallback is implemented: if output echoes the instruction prompt, inference reruns without prompt.
- Whisper context initialization is lazy (first queued chunk may be slower once).
- CoreML encoder is opt-in (`LAYCA_ENABLE_WHISPER_COREML_ENCODER=1`); default path avoids ANE/CoreML plan-build startup stalls.

#### Storage, Update, and Sync Hooks
- `App/AppBackend.swift`
- `SessionStore` creates `session_full.m4a` + `segments.json` + `session.json`.
- Appends transcript rows, persists segment snapshots, and keeps stable speaker profile (color/avatar) per session.
- Session metadata (title/status/language hints/duration/speakers) is persisted in `session.json` and reloaded on app launch.
- User settings/state are persisted in `UserDefaults` and restored on app launch.
- Session deletion removes runtime state and filesystem assets (`Documents/Sessions/{UUID}`).
- Credit deduction per chunk and iCloud-sync hook point are included.

#### App Orchestration + UI Wiring
- `App/AppBackend.swift`, `App/ContentView.swift`, `Features/Chat/ChatTabView.swift`, `Views/Mac/MacProWorkspaceView.swift`
- `AppBackend` (`ObservableObject`) now drives recording state, sessions, transcript stream, and language settings.
- Record button uses backend pipeline; chat bubbles update reactively from backend rows.
- Language tag in bubble uses pipeline language code; speaker style is session-stable.
- Chat bubble tap plays that chunk from `session_full.m4a`.
- macOS uses dedicated workspace views (sidebar/detail) rather than iOS-style tabs.
- macOS chat detail toolbar uses SwiftUI `ToolbarItem` + `ToolbarItemGroup` composition with `.toolbar(removing: .title)` for Liquid Glass-style controls.
- Library rows now support long-press action menu: `Rename`, `Share this chat`, `Delete`.
- macOS sidebar `Recent Chats` rows now support the same action menu: `Rename`, `Share this chat`, `Delete`.
- macOS settings includes live microphone permission status and actions (`Allow Microphone Access` / `Open System Settings`).
- macOS recorder error state provides direct deep-link action to System Settings when microphone permission is denied.
- Chat bubble long-press opens actions for:
  - manual text edit
  - speaker rename (syncs all rows with same `speakerID`)
  - speaker reassignment to another existing speaker profile
  - "Transcribe Again" retry
- Bubble long-press is disabled while recording and while queued/active transcription work is running.
- Bubble option UI is extracted into a dedicated component (`Views/Components/TranscriptBubbleOptionButton.swift`).
- Row transcription status clears reliably and reports `"No speech detected in this chunk."` when inference returns empty text.
- Chunk playback is only enabled when recording is stopped.
- Recorder card hit-testing fix applied so `Record` is tappable.

#### Tests Added
- `AppBackendTests.swift`
- Covered:
  - prompt building from selected languages
  - credit exhaustion guard behavior
  - speaker profile stability across chunks
  - persisted session reload from disk
  - app settings persistence round-trip
  - session delete removes store row + filesystem directory

#### Project Structure Cleanup
- App orchestration moved to `App/` (`laycaApp.swift`, `ContentView.swift`, `AppBackend.swift`).
- Feature screens moved to `Features/` (`Chat`, `Library`, `Settings`).
- Shared UI helpers moved to `Views/Shared/`.
- Domain models extracted to `Models/Domain/` (`FocusLanguage`, `ChatSession`, `TranscriptRow`).
- Runtime model assets moved to `Models/RuntimeAssets/`.

#### macOS Permission + Signing Notes
- `NSMicrophoneUsageDescription` is required for runtime microphone prompts.
- macOS target uses sandboxed signing with explicit audio-input entitlement (`com.apple.security.device.audio-input`).
- If permission was previously denied or missing in System Settings list, reset and re-request:
  - `tccutil reset Microphone cropbinary.layca`
  - relaunch app and press record once.

### Next

- Add explicit playback/transcription progress state per tapped bubble.
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
