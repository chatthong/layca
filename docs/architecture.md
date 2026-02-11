# Architecture Overview

## Goals
- Offline-first meeting assistant with local-first processing.
- Dynamic configuration from Settings (language focus + context keywords + sync toggle + Whisper Advanced Zone controls).
- Reactive chat UI driven by backend state.
- Persist chats/settings across app relaunch on iOS-family and macOS.
- Native platform-adapted shell: tab-driven on iOS-family and split-view workspace on macOS.
- User-facing transcript timeline uses "Message" terminology (internal processing still slices audio into chunks).

## High-Level Modules
1. App Shell + State Coordinator (`App/ContentView.swift`)
2. Platform UI Components (`Features/Chat/ChatTabView.swift`, `Features/Settings/SettingsTabView.swift`, `Features/Library/LibraryTabView.swift`, `Views/Mac/MacProWorkspaceView.swift`)
3. Backend Orchestrator (`App/AppBackend.swift`)
4. Preflight Layer (`PreflightService`)
5. Live Pipeline (`LiveSessionPipeline`)
6. Storage Layer (`SessionStore` + filesystem)
7. Settings Persistence (`AppSettingsStore` + `UserDefaults`)
8. Playback + Export layer (implemented/partial)

## Runtime Flow
1. App boots and reloads persisted settings + session snapshots.
2. User taps record.
3. Pre-flight checks credit and prepares language prompt.
   - Prompt uses strict verbatim instructions (`Never translate`, `Never summarize`, `Never rewrite`).
4. Live pipeline runs concurrent tracks:
   - waveform/input stream
   - CoreML Silero VAD chunk slicing
   - CoreML speaker diarization branch
   - merge branch
5. Transcript item is appended to store.
6. Chat list updates reactively.
7. Chunk duration deducts credit.
8. Transcript rows persist chunk `startOffset`/`endOffset`.
9. Optional sync hook runs.
10. Backend queues chunk transcription automatically (one-by-one) and updates bubbles reactively.
11. User can tap a transcript bubble to play that chunk when recording is stopped.

## Current Implementation Note
- Pipeline internals are production-style backend services.
- Audio capture uses real `AVAudioEngine`.
- App shell is platform-aware:
  - iOS-family uses `TabView`/`TabSection`.
  - iOS-family uses plain `systemBackground` with native material cards and automatic device light/dark appearance.
  - macOS uses `NavigationSplitView` with sidebar workspace sections and dedicated detail views.
  - macOS Chat detail toolbar uses native `ToolbarItem` + `ToolbarItemGroup` controls (`Share`, grouped `Rename` + `New Chat`, and `Info` to open `Setting`).
- VAD uses native CoreML Silero (`silero-vad-unified-256ms-v6.0.0.mlmodelc`) with bundled offline model.
- Speaker branch uses native CoreML WeSpeaker (`wespeaker_v2.mlmodelc`) with bundled offline model.
- Speaker fallback now uses a multi-feature signature (amplitude + zero-crossing-rate + RMS energy) with tunable threshold when CoreML speaker model is unavailable.
- Runtime model asset sources are organized under `Models/RuntimeAssets/`.
- Whisper transcription runs automatically through a serial queue (`whisper.cpp`) as chunks are produced.
- Automatic transcription runs with Whisper auto language detection (`preferredLanguageCode = "auto"`) and `translate = false`.
- Whisper prompt template is built from Language Focus + context keywords.
- If output appears to echo the prompt text, the backend reruns inference without prompt.
- If transcription quality is weak/unusable (e.g., `-`, `foreign`, empty-like output), backend queues retry and/or removes placeholder rows with no usable speech text.
- Whisper runtime preferences are applied from app settings and background-prewarmed after apply.
- Whisper acceleration toggles are available at environment level:
  - `LAYCA_ENABLE_WHISPER_COREML_ENCODER`
  - `LAYCA_ENABLE_WHISPER_GGML_GPU_DECODE`
- Settings Advanced Zone controls:
  - `Whisper ggml GPU Decode` toggle
  - `Whisper CoreML Encoder` toggle
  - `Model Switch` (`Fast`, `Normal`, `Pro`)
- On physical iOS devices, CoreML encoder now uses an auto profile: enabled on high-memory/high-core devices for maximum performance, safety-disabled on lower-tier devices to avoid startup stalls.
- Set `LAYCA_FORCE_WHISPER_COREML_ENCODER_IOS=ON` to force-enable on any iPhone.
- On some iPhones, first CoreML encoder run may log ANE/CoreML plan-build warnings before succeeding.
- If ggml GPU decode init fails, runtime falls back to CPU decode and logs reason.
- Chunk slicing defaults are tuned longer to reduce over-splitting: silence cutoff `1.2s`, minimum chunk `3.2s`, max chunk `12s`.
- Chunk playback is gated off while recording to avoid audio-session conflicts.
- "Transcribe Again" is a submenu (`Transcribe Auto`, plus `Transcribe in <Focus Language>` entries for selected focus languages).
- Manual retranscribe execution is currently gated during active recording and runs after recording stops.
- Forced `TH` / `EN` manual retries validate script output; backend retries once without prompt on mismatch, then keeps existing text when mismatch persists.
- Manual low-confidence retries keep existing text silently (no red warning banner).
- `SessionStore` persists both `session.json` (session metadata) and `segments.json` (row snapshots) and reloads from disk at startup.
- `AppSettingsStore` persists user setting values and active-chat selection through relaunch.
- Library session rows (iOS-family + macOS library workspace) support `Rename`, `Share this chat`, `Delete` via context menu.
- macOS sidebar `Recent Chats` rows support the same context menu action group.
- macOS recording permission uses `AVAudioApplication.requestRecordPermission`.
- macOS target is sandboxed and requires audio-input entitlement to appear in Privacy > Microphone settings.

## Folder Layout (Current)
```text
xcode/layca/
├── App/
│   ├── laycaApp.swift
│   ├── ContentView.swift
│   └── AppBackend.swift
├── Features/
│   ├── Chat/ChatTabView.swift
│   ├── Library/LibraryTabView.swift
│   └── Settings/SettingsTabView.swift
├── Models/
│   ├── Domain/
│   │   ├── FocusLanguage.swift
│   │   ├── ChatSession.swift
│   │   └── TranscriptRow.swift
│   └── RuntimeAssets/
│       ├── ggml-large-v3-turbo-q5_0.bin
│       ├── ggml-large-v3-turbo-q8_0.bin
│       ├── ggml-large-v3-turbo.bin
│       ├── ggml-large-v3-turbo-encoder.mlmodelc/
│       ├── silero-vad-unified-256ms-v6.0.0.mlmodelc/
│       └── wespeaker_v2.mlmodelc/
├── Views/
│   ├── Components/
│   │   └── TranscriptBubbleOptionButton.swift
│   ├── Mac/
│   │   └── MacProWorkspaceView.swift
│   └── Shared/
│       ├── LiquidBackdrop.swift
│       └── View+PlatformCompatibility.swift
├── Libraries/
│   ├── SileroVADCoreMLService.swift
│   ├── SpeakerDiarizationCoreMLService.swift
│   └── WhisperGGMLCoreMLService.swift
├── Frameworks/
│   └── whisper.xcframework/
└── Assets.xcassets/
```

## Non-Functional Constraints
- Keep memory bounded during live stream/chunk processing.
- Keep per-session speaker identity stable (color/avatar consistency).
- Keep recording controls gated by credit status.
