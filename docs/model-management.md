# Model Management

## Status
- Whisper runtime is integrated via `whisper.cpp` (`whisper.xcframework`).
- Transcription is currently triggered on transcript-bubble tap (deferred/on-demand mode).
- Settings has no model selection or download controls.
- Settings now provides:
  - Language Focus (multi-select)
  - Context keywords (free text), used in Whisper `initial_prompt`

## Current Runtime Assets
- Bundled VAD directory: app bundle `silero-vad-unified-256ms-v6.0.0.mlmodelc` (CoreML Silero, offline-first)
- Bundled speaker directory: app bundle `wespeaker_v2.mlmodelc` (CoreML WeSpeaker, offline-first)
- Bundled Whisper decoder file: app bundle `ggml-large-v3-turbo.bin` (offline-first)
- Bundled Whisper encoder directory: app bundle `ggml-large-v3-turbo-encoder.mlmodelc` (CoreML encoder acceleration)
- Whisper runtime framework: `Frameworks/whisper.xcframework` (static XCFramework)

## Whisper Inference Behavior (Chunk Tap)
- Language mode: `preferredLanguageCode = "auto"` (always auto-detect for chunk taps)
- Translation: disabled (`translate = false`)
- Prompt: `initial_prompt` from settings-driven template:
  - `This is a verbatim transcript of a meeting in [LANGUAGES]. The speakers switch between languages naturally. Transcribe exactly what is spoken in the original language. Do not translate. Context: [KEYWORDS].`
- Prompt leak guard:
  - If output appears to echo instruction text, backend reruns once without prompt.
- Empty result guard:
  - If still empty in auto mode, backend reruns once with detected language.

## Pre-flight Behavior
1. User taps record.
2. Pre-flight validates available credits.
3. Pre-flight builds the Whisper prompt from language focus + context keywords.
4. Pipeline starts when pre-flight succeeds.

## Notes
- Model resolution order for Whisper decoder:
  1. bundled `ggml-large-v3-turbo.bin`
  2. cached copy
  3. runtime download fallback (if not available locally)
