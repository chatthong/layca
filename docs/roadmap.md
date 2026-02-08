# Roadmap

## Phase 1 - Foundation
- Model download manager and install gating.
- `AVAudioRecorder` setup with background capability.
- Session directory management and recording save flow.

## Phase 2 - Core Brain + Sync
- Integrate `whisper.cpp` wrapper.
- Implement chunk transcription and offset mapping.
- Build playback seek-to-segment behavior.

## Phase 3 - UX Polish
- Polish Chat timeline and grouped native tab-bar flow.
- Add Library session switch list and fast chat loading.
- Keep New Chat as separate special-role tab action.
- Add basic speaker labeling and editing actions.
- Add transcript/audio export options with Notepad-style export templates.

## Phase 4 - Quality + Hardening
- Failure recovery for interrupted sessions.
- Download resilience and checksum validation.
- Performance profiling and battery optimization.
