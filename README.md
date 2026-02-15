# Layca (เลขา) - Master App Plan 📝

> **The Ultimate Offline Polyglot Meeting Secretary**

**Project Codename:** `Layca-Core`  
**Version:** 0.5.3 (Live Audio + CoreML VAD + CoreML Speaker Diarization + Automatic Queued Whisper Message Transcription + Quality Guardrails)  
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

- **Inference target:** `whisper.cpp` with automatic queued message transcription plus configurable CoreML encoder and ggml GPU decode acceleration.
- **Decoder model profiles:** `Fast` (`ggml-large-v3-turbo-q5_0.bin`), `Normal` (`ggml-large-v3-turbo-q8_0.bin`), `Pro` (`ggml-large-v3-turbo.bin`).
- **Model source layout in project:** `xcode/layca/Models/RuntimeAssets/` (copied into app resources at build time).
- **Whisper startup mode:** app applies runtime preferences and triggers background prewarm so first manual transcription avoids most cold-start delay.
- **Advanced Zone runtime controls:** GPU Decode (ON/OFF), CoreML Encoder (ON/OFF), Model Switch (`Fast`/`Normal`/`Pro`) on both iOS-family and macOS settings.
- **iOS defaults:** values are auto-detected by device capability at first launch, then persisted as user-overridable settings.
- **Environment toggles:** `LAYCA_ENABLE_WHISPER_COREML_ENCODER`, `LAYCA_ENABLE_WHISPER_GGML_GPU_DECODE`, and `LAYCA_FORCE_WHISPER_COREML_ENCODER_IOS` remain available at runtime level (primarily useful outside app-managed settings flow).
- **Acceleration fallback:** if ggml GPU context init fails, runtime falls back to CPU decode and logs status.
- **iOS CoreML note:** first run may log ANE/CoreML plan rebuild warnings before succeeding; this is a known cold-start behavior on some devices.
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
  - Message transcription runs automatically in a serial queue (one-by-one) as chunks are produced.

### C. Data Layer

- **Current runtime persistence:** actor-based `SessionStore` + filesystem snapshots (`session.json`, `segments.json`) with startup reload.
- **Current settings persistence:** `UserDefaults`-backed app settings snapshot (language focus, credits, iCloud toggle, Whisper runtime profile/toggles, main-timer display style, active-session metadata compatibility, chat counter).
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

- **iOS/iPadOS shell:** custom swipeable drawer sidebar (`Layca Chat`, `Setting`, `Recent Chats`) with fixed top actions (`Search`, `New Chat`) and a chat-header sidebar toggle button.
- **visionOS/tvOS shell:** `TabView` with `Layca Chat`, `Library`, `Setting`, plus a dedicated `New Chat` action tab.
- **iOS-family visual style:** plain `systemBackground` chat/settings canvas + native material cards; iOS/iPadOS sidebar uses a dark workspace surface with material controls.
- **macOS shell:** native `NavigationSplitView` workspace with sidebar sections (`Layca Chat`, `Setting`) and a `Recent Chats` list.
- **Launch behavior:** app always opens in a fresh draft room on both iOS-family and macOS; existing saved chats remain available in `Recent Chats` (and `Library` on visionOS/tvOS).
- **Chat workspace:** Recorder card + live transcript bubbles.
- **Header/session actions:** iOS chat header keeps sidebar toggle before chat title, with share on trailing side; macOS chat detail keeps inline title rename + trailing `Share`.
- **Settings workspace:** Hours credit, language focus, context keywords, Advanced Zone (GPU/CoreML/model profile + main timer `Time Display`), iCloud toggle, purchase restore, and macOS microphone access controls.
- **Library workspace:** Session switcher with long-press/right-click action group (`Rename`, `Share this chat`, `Delete`) on session rows (where Library is present).
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
   - Detect speech/silence, cut message chunk after sustained silence.
   - Current defaults: silence cutoff `1.2s`, minimum chunk `3.2s`, max chunk `12s`.
3. **Track 3: Speaker branch**
   - CoreML speaker embedding extraction + cosine matching / new speaker assignment.
   - Fallback branch uses amplitude + zero-crossing-rate + RMS signature matching.
4. **Track 4: Merger**
   - Store speaker/language metadata plus message offsets and deferred-transcript placeholder text.

### Phase 3: Persist + Reactive UI

1. Append transcript into store.
2. UI updates bubbles reactively.
3. Transcript rows keep message `startOffset`/`endOffset` for playback.
4. Deduct used credit by message duration.
5. Optional sync hook runs in background.

---

## 5. Current Implementation Status 🗺️

### Implemented

#### Dynamic Pre-Flight Backend (Credits + Language Prompt)
- `App/AppBackend.swift`
- `PreflightService` checks remaining credit and builds prompt text in strict verbatim mode:
  - `STRICT VERBATIM MODE. Never translate under any condition. Never summarize. Never rewrite. Preserve the original spoken language for every utterance... Context: [KEYWORDS].`

#### Live Pipeline Backend (4-Track Style, Concurrent)
- `App/AppBackend.swift`
- `Libraries/SileroVADCoreMLService.swift`, `Libraries/SpeakerDiarizationCoreMLService.swift`, `Libraries/WhisperGGMLCoreMLService.swift`
- `LiveSessionPipeline` actor emits:
  - waveform updates (visualizer timing)
  - CoreML Silero VAD chunking behavior
  - speaker-ID branch
  - merged transcript events (`speaker`, `language`, `text`, `timestamp`)
- Current implementation uses real `AVAudioEngine` + native CoreML Silero VAD + native CoreML speaker diarization.
- Message rows are persisted with placeholder transcript text and are transcribed by Whisper in automatic queue order.
- Automatic transcription runs with `preferredLanguageCode = "auto"` and `translate = false` to keep original spoken language (no translation).
- Whisper prompt-leak fallback is implemented: if output echoes the instruction prompt, inference reruns without prompt.
- Transcription quality guardrails classify outputs as `acceptable` / `weak` / `unusable`; weak/unusable outputs trigger queued retry or row removal.
- Rows with unusable/no-speech placeholder output are removed instead of showing "No speech detected in this chunk."
- Whisper context is background-prewarmed after runtime preference apply to reduce first-transcription latency.
- Acceleration uses environment toggles:
  - `LAYCA_ENABLE_WHISPER_COREML_ENCODER`
  - `LAYCA_ENABLE_WHISPER_GGML_GPU_DECODE`
- iOS override for CoreML encoder safety fallback:
  - `LAYCA_FORCE_WHISPER_COREML_ENCODER_IOS`
- Runtime prints one-line acceleration status:
  - `[Whisper] Model: Fast/Normal/Pro, CoreML encoder: ON/OFF, ggml GPU decode: ON/OFF`

#### Storage, Update, and Sync Hooks
- `App/AppBackend.swift`
- `SessionStore` creates `session_full.m4a` + `segments.json` + `session.json`.
- Appends transcript rows, persists segment snapshots, and keeps stable speaker profile (color/avatar) per session.
- Session metadata (title/status/language hints/duration/speakers) is persisted in `session.json` and reloaded on app launch.
- User settings/state are persisted in `UserDefaults` and restored on app launch.
- Active session restore is intentionally overridden at startup so UI opens in draft mode.
- Persisted settings include Whisper acceleration/model preferences (CoreML toggle, GPU toggle, model profile) plus main timer display style (`Friendly` / `Hybrid` / `Professional`).
- Session deletion removes runtime state and filesystem assets (`Documents/Sessions/{UUID}`).
- Credit deduction per message and iCloud-sync hook point are included.

#### App Orchestration + UI Wiring
- `App/AppBackend.swift`, `App/ContentView.swift`, `Features/Chat/ChatTabView.swift`, `Views/Mac/MacProWorkspaceView.swift`
- `AppBackend` (`ObservableObject`) now drives recording state, sessions, transcript stream, and language settings.
- Record button uses backend pipeline; chat bubbles update reactively from backend rows.
- `startNewChat()` now switches to draft mode (does not create a session immediately).
- First record action in draft creates the persisted chat (`chat N`) and begins capture.
- Main timer uses selectable formatting (`Friendly`, `Hybrid`, `Professional`) from settings.
- Friendly format trims zero units (`11 sec`, `5 min 22 sec`, `1 hr 5 sec`).
- Draft idle state shows starter copy instead of timer (`Tap to start record` on iOS/iPadOS, `Click to start record` on macOS).
- Saved chats show accumulated session duration while idle, and resumed recording continues from prior duration.
- Language tag in bubble uses pipeline language code; speaker style is session-stable.
- Chat bubble tap plays that message range from `session_full.m4a`.
- While transcript chunk playback is active (player mode), recorder controls switch to playback state on iOS/iPadOS and macOS:
  - action button changes to `Stop`
  - recorder tint changes to green (recording still uses red)
  - main timer shows remaining playback time (countdown)
  - subtitle shows segment range (`mm:ss → mm:ss`)
- iOS/iPadOS uses a custom drawer workspace shell; macOS uses dedicated split workspace views (sidebar/detail).
- macOS chat detail toolbar keeps inline title-rename + trailing `Share`; `New Chat` and `Setting` are sidebar actions.
- iOS chat header uses leading controls with sidebar toggle before chat title and a trailing share action.
- iOS non-edit chat-title pill auto-sizes with title length (bounded min/max to prevent toolbar overflow) and uses tail truncation only when needed.
- iOS drawer opens via right-swipe from anywhere on the screen (including over chat bubbles), not only from the left edge.
- Inline chat-title edit mode on iOS and macOS hides non-title header controls and cancels on outside interaction (content/sidebar/tap-away focus loss).
- During live recording, transcript updates do not force-scroll; a `New message` button appears. Tapping it jumps to bottom and enables follow mode until user scrolls away.
- iOS-family cards and sheets use plain `systemBackground` + native material fills to follow automatic light/dark switching without custom liquid-glass wrappers.
- Recorder accessory glass uses state tint on chat controls:
  - red while recording
  - green during transcript-chunk playback
- Library rows now support long-press action menu: `Rename`, `Share this chat`, `Delete`.
- macOS sidebar `Recent Chats` rows now support the same action menu: `Rename`, `Share this chat`, `Delete`.
- macOS split detail uses a minimum width guard to prevent over-compressed chat layout.
- macOS settings includes live microphone permission status and actions (`Allow Microphone Access` / `Open System Settings`).
- macOS recorder error state provides direct deep-link action to System Settings when microphone permission is denied.
- Chat bubble long-press opens actions for:
  - manual text edit
  - speaker rename (syncs all rows with same `speakerID`)
  - speaker reassignment to another existing speaker profile
  - "Transcribe Again" submenu:
    - `Transcribe Auto` (same behavior as previous retry)
    - `Transcribe in <Focus Language>` (shows selected focus languages only)
- Bubble long-press is disabled while recording and while queued/active transcription work is running.
- "Transcribe Again" execution is currently gated while recording (`Stop recording before running Transcribe Again.`).
- Forced language retry (`TH` / `EN`) now validates output script; on mismatch backend retries once without prompt and keeps existing text if script still mismatches.
- Manual retry quality failures keep existing text silently (no low-confidence banner).
- Bubble option UI is extracted into a dedicated component (`Views/Components/TranscriptBubbleOptionButton.swift`).
- Row transcription status clears reliably; no-speech placeholder rows are deleted automatically.
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
