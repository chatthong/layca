# Model Management

## Status
- Whisper GGML binaries are not used in the app now.
- Legacy Whisper GGML binary files are removed from this project.
- Settings has no model selection or download controls.

## Current Runtime Assets
- Bundled VAD directory: app bundle `silero-vad-unified-256ms-v6.0.0.mlmodelc` (CoreML Silero, offline-first)
- Bundled speaker directory: app bundle `wespeaker_v2.mlmodelc` (CoreML WeSpeaker, offline-first)

## Pre-flight Behavior
1. User taps record.
2. Pre-flight validates available credits.
3. Pre-flight builds the language prompt from language focus.
4. Pipeline starts when pre-flight succeeds.

## Notes
- The transcription branch still uses placeholder text until Whisper/runtime integration is added.
- This keeps the settings and backend clean for upcoming VAD-related work.
