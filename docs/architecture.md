# Architecture Overview

## Goals
- Offline-first transcription and meeting assistant for Apple platforms.
- Privacy-by-design with local processing after model setup.
- Consistent UX across iOS, iPadOS, tvOS, and visionOS.

## High-Level Modules
1. App Shell + State Coordinator (`ContentView`)
2. Tab Components (`ChatTabView`, `SettingTabView`, `LibraryTabView`)
3. Navigation Layer (native grouped tab bar + special action tab)
4. Session Recorder (`AVAudioRecorder`)
5. Audio Processor (decode/resample to 16kHz mono PCM)
6. Transcription Engine (`whisper.cpp` wrapper)
7. Transcript Mapper (segment offsets to absolute timeline)
8. Storage Layer (SwiftData + Filesystem)
9. Playback + Export Layer (`AVPlayer` and Share Sheet)

## Data Flow
1. User starts recording.
2. Audio is written to `full_recording.m4a` and buffered in PCM chunks.
3. PCM chunks are passed to Whisper for segment generation.
4. Segments are normalized and persisted to local database and JSON snapshot.
5. Chat UI consumes normalized segments for timeline review.
6. Native grouped tab bar routes to Chat, Setting, Library, and New Chat action tab.
7. Export action is available from the Chat header icon (top-right).
8. Tap on segment seeks to corresponding audio offset in master recording.
9. Export pipeline can transform transcript into Notepad-style document formats.

## Folder Layout (Proposed)
```text
Layca/
├── App/
├── Features/
│   ├── Session/
│   ├── Transcript/
│   ├── Playback/
│   └── Export/
├── Core/
│   ├── Audio/
│   ├── Whisper/
│   ├── Storage/
│   └── ModelManager/
├── Resources/
└── docs/
```

## Current UI File Layout
```text
xcode/layca/
├── ContentView.swift      <-- Shared state + tab routing
├── ChatTabView.swift      <-- Chat screen component
├── SettingTabView.swift   <-- Settings screen component
└── LibraryTabView.swift   <-- Session library component
```

## Non-Functional Constraints
- Recording reliability with screen locked.
- Controlled memory usage during chunk buffering.
- Graceful degradation on lower storage devices.
- No required cloud dependency for core operation.
