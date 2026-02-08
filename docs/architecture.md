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
7. Playback + Export layer (planned/partial)

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
   - VAD-like chunk slicing
   - transcription branch + speaker branch
   - merge branch
4. Transcript item is appended to store.
5. Chat list updates reactively.
6. Chunk duration deducts credit.
7. Optional sync hook runs.

## Current Implementation Note
- Pipeline internals are structured as production-ready backend services.
- Audio capture/VAD/Whisper internals are currently simulated to keep UI and data contracts stable.

## Folder Layout (Current)
```text
xcode/layca/
├── ContentView.swift
├── ChatTabView.swift
├── SettingTabView.swift
├── LibraryTabView.swift
└── AppBackend.swift
```

## Non-Functional Constraints
- Keep memory bounded during live stream/chunk processing.
- Keep per-session speaker identity stable (color/avatar consistency).
- Keep recording controls gated by model readiness and credit status.
