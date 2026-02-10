# Architecture Overview

## Goals
- Offline-first meeting assistant with local-first processing.
- Dynamic configuration from Settings (language focus + context keywords + sync toggle).
- Reactive chat UI driven by backend state.
- Native platform-adapted shell: tab-driven on iOS-family and split-view workspace on macOS.

## High-Level Modules
1. App Shell + State Coordinator (`ContentView`)
2. Platform UI Components (`ChatTabView`, `SettingTabView`, `LibraryTabView`, `Views/Mac/MacProWorkspaceView`)
3. Backend Orchestrator (`AppBackend`)
4. Preflight Layer (`PreflightService`)
5. Live Pipeline (`LiveSessionPipeline`)
6. Storage Layer (`SessionStore` + filesystem)
7. Playback + Export layer (implemented/partial)

## Runtime Flow
1. User taps record.
2. Pre-flight checks credit and prepares language prompt.
3. Live pipeline runs concurrent tracks:
   - waveform/input stream
   - CoreML Silero VAD chunk slicing
   - CoreML speaker diarization branch
   - merge branch
4. Transcript item is appended to store.
5. Chat list updates reactively.
6. Chunk duration deducts credit.
7. Transcript rows persist chunk `startOffset`/`endOffset`.
8. Optional sync hook runs.
9. Backend queues chunk transcription automatically (one-by-one) and updates bubbles reactively.
10. User can tap a transcript bubble to play that chunk when recording is stopped.

## Current Implementation Note
- Pipeline internals are production-style backend services.
- Audio capture uses real `AVAudioEngine`.
- App shell is platform-aware:
  - iOS-family uses `TabView`/`TabSection`.
  - macOS uses `NavigationSplitView` with sidebar workspace sections and dedicated detail views.
- VAD uses native CoreML Silero (`silero-vad-unified-256ms-v6.0.0.mlmodelc`) with bundled offline model.
- Speaker branch uses native CoreML WeSpeaker (`wespeaker_v2.mlmodelc`) with bundled offline model.
- Whisper transcription runs automatically through a serial queue (`whisper.cpp`) as chunks are produced.
- Automatic transcription runs with Whisper auto language detection (`preferredLanguageCode = "auto"`) and `translate = false`.
- Whisper prompt template is built from Language Focus + context keywords.
- If output appears to echo the prompt text, the backend reruns inference without prompt.
- Whisper is initialized lazily on first transcription request (no app-launch prewarm).
- CoreML encoder is opt-in via `LAYCA_ENABLE_WHISPER_COREML_ENCODER=1`; default startup path uses non-CoreML encoder flow for reliability.
- Chunk slicing defaults are tuned longer to reduce over-splitting: silence cutoff `1.2s`, minimum chunk `3.2s`, max chunk `12s`.
- Chunk playback is gated off while recording to avoid audio-session conflicts.
- macOS recording permission uses `AVAudioApplication.requestRecordPermission`.
- macOS target is sandboxed and requires audio-input entitlement to appear in Privacy > Microphone settings.

## Folder Layout (Current)
```text
xcode/layca/
├── ContentView.swift
├── ChatTabView.swift
├── SettingTabView.swift
├── LibraryTabView.swift
├── View+PlatformCompatibility.swift
├── Views/
│   └── Mac/
│       └── MacProWorkspaceView.swift
├── AppBackend.swift
├── Libraries/
│   ├── SileroVADCoreMLService.swift
│   ├── SpeakerDiarizationCoreMLService.swift
│   └── WhisperGGMLCoreMLService.swift
├── Frameworks/
│   └── whisper.xcframework/
├── ggml-large-v3-turbo.bin
├── ggml-large-v3-turbo-encoder.mlmodelc/
├── silero-vad-unified-256ms-v6.0.0.mlmodelc/
└── wespeaker_v2.mlmodelc/
```

## Non-Functional Constraints
- Keep memory bounded during live stream/chunk processing.
- Keep per-session speaker identity stable (color/avatar consistency).
- Keep recording controls gated by credit status.
