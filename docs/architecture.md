# Architecture Overview

## Goals
- Offline-first meeting assistant with local-first processing.
- Dynamic configuration from Settings (model + language focus + sync toggle).
- Reactive chat UI driven by backend state.

## High-Level Modules
1. App Shell + State Coordinator (`ContentView`)
2. Tab Components (`ChatTabView`, `SettingTabView`, `LibraryTabView`)
3. Backend Orchestrator (`AppBackend`)
4. Model Layer (`ModelManager`, `PreflightService`)
5. Live Pipeline (`LiveSessionPipeline`)
6. Storage Layer (`SessionStore` + filesystem)
7. Playback + Export layer (implemented/partial)

## Model Catalog (Current)
- `Normal AI` -> `ggml-large-v3-turbo-q8_0.bin`
- `Light AI` -> `ggml-large-v3-turbo-q5_0.bin`
- `High Detail AI` -> `ggml-large-v3-turbo.bin`

Model URLs are stored in backend model metadata and selected from Settings.

## Runtime Flow
1. User taps record.
2. Pre-flight checks credit, resolves model, prepares language prompt.
3. Live pipeline runs concurrent tracks:
   - waveform/input stream
   - CoreML Silero VAD chunk slicing
   - transcription branch + CoreML speaker diarization branch
   - merge branch
4. Transcript item is appended to store.
5. Chat list updates reactively.
6. Chunk duration deducts credit.
7. Transcript rows persist chunk `startOffset`/`endOffset`.
8. Optional sync hook runs.
9. User can tap a transcript bubble to play that chunk when recording is stopped.

## Current Implementation Note
- Pipeline internals are production-style backend services.
- Audio capture uses real `AVAudioEngine`.
- VAD uses native CoreML Silero (`silero-vad-unified-256ms-v6.0.0.mlmodelc`) with bundled offline model.
- Speaker branch uses native CoreML WeSpeaker (`wespeaker_v2.mlmodelc`) with bundled offline model.
- Whisper transcription branch is still placeholder text pending runtime integration.
- Chunk slicing defaults are tuned longer to reduce over-splitting: silence cutoff `1.2s`, minimum chunk `3.2s`, max chunk `12s`.
- Chunk playback is gated off while recording to avoid audio-session conflicts.

## Folder Layout (Current)
```text
xcode/layca/
├── ContentView.swift
├── ChatTabView.swift
├── SettingTabView.swift
├── LibraryTabView.swift
├── AppBackend.swift
├── Libraries/
│   ├── SileroVADCoreMLService.swift
│   └── SpeakerDiarizationCoreMLService.swift
├── silero-vad-unified-256ms-v6.0.0.mlmodelc/
└── wespeaker_v2.mlmodelc/
```

## Non-Functional Constraints
- Keep memory bounded during live stream/chunk processing.
- Keep per-session speaker identity stable (color/avatar consistency).
- Keep recording controls gated by model readiness and credit status.
