# Architecture Overview

## Goals
- Offline-first transcription and meeting assistant for Apple platforms.
- Privacy-by-design with local processing after model setup.
- Consistent UX across iOS, iPadOS, tvOS, and visionOS.

## High-Level Modules
1. App Shell (SwiftUI)
2. Session Recorder (`AVAudioRecorder`)
3. Audio Processor (decode/resample to 16kHz mono PCM)
4. Transcription Engine (`whisper.cpp` wrapper)
5. Transcript Mapper (segment offsets to absolute timeline)
6. Storage Layer (SwiftData + Filesystem)
7. Playback + Export Layer (`AVPlayer` and Share Sheet)

## Data Flow
1. User starts recording.
2. Audio is written to `full_recording.m4a` and buffered in PCM chunks.
3. PCM chunks are passed to Whisper for segment generation.
4. Segments are normalized and persisted to local database and JSON snapshot.
5. UI consumes normalized segments for Chat and Notepad views.
6. Tap on segment seeks to corresponding audio offset in master recording.

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

## Non-Functional Constraints
- Recording reliability with screen locked.
- Controlled memory usage during chunk buffering.
- Graceful degradation on lower storage devices.
- No required cloud dependency for core operation.
