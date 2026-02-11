# Model Management

## Status
- Whisper runtime is integrated via `whisper.cpp` (`whisper.xcframework`).
- Transcription is currently queued automatically per message chunk (serial one-by-one mode).
- Settings has no model selection or download controls.
- Settings now provides:
  - Language Focus (multi-select)
  - Context keywords (free text), used in Whisper `initial_prompt`
- On macOS, the same model-related settings are shown in the native settings workspace form.
- macOS settings view is reachable from sidebar `Setting` and Chat toolbar `Info`.

## Current Runtime Assets
- Bundled VAD directory: app bundle `silero-vad-unified-256ms-v6.0.0.mlmodelc` (CoreML Silero, offline-first)
- Bundled speaker directory: app bundle `wespeaker_v2.mlmodelc` (CoreML WeSpeaker, offline-first)
- Bundled Whisper decoder file: app bundle `ggml-large-v3-turbo.bin` (offline-first)
- Bundled Whisper encoder directory: app bundle `ggml-large-v3-turbo-encoder.mlmodelc` (optional CoreML encoder acceleration)
- Whisper runtime framework: `Frameworks/whisper.xcframework` (static XCFramework)
- Project source directory for bundled model assets: `xcode/layca/Models/RuntimeAssets/`

## Whisper Inference Behavior (Auto Queue)
- Language mode: `preferredLanguageCode = "auto"` (always auto-detect for queued message transcription)
- Translation: disabled (`translate = false`)
- Prompt: `initial_prompt` from settings-driven template:
  - `STRICT VERBATIM MODE. Never translate under any condition. Never summarize. Never rewrite... Context: [KEYWORDS].`
- Prompt leak guard:
  - If output appears to echo instruction text, backend reruns once without prompt.
- Empty result guard:
  - If still empty in auto mode, backend reruns once with detected language.
- Quality guardrails:
  - Classifies result as `acceptable`, `weak`, or `unusable`.
  - Unusable placeholder/no-speech outputs are removed instead of keeping placeholder text.

## Whisper Startup / Backend Selection
- App does not prewarm Whisper automatically on launch.
- Whisper context initializes lazily when first queued message transcription is requested.
- Runtime acceleration toggles:
  - `LAYCA_ENABLE_WHISPER_COREML_ENCODER`
  - `LAYCA_ENABLE_WHISPER_GGML_GPU_DECODE`
- Current defaults are ON for both toggles on macOS.
- On physical iOS devices, CoreML encoder uses an auto profile:
  - ON for higher-tier devices (more RAM/cores) to maximize performance
  - OFF for lower-tier devices to avoid startup stalls with `large-v3-turbo`
- iOS override flag:
  - `LAYCA_FORCE_WHISPER_COREML_ENCODER_IOS=ON`
- Runtime logs resolved mode:
  - `[Whisper] CoreML encoder: ON/OFF, ggml GPU decode: ON/OFF`
- If ggml GPU context initialization fails, runtime falls back to CPU decode and logs fallback reason.

## Pre-flight Behavior
1. User taps record.
2. Pre-flight validates available credits.
3. Pre-flight builds the Whisper prompt from language focus + context keywords.
4. Pipeline starts when pre-flight succeeds.

## Notes
- App runtime does not apply a profanity/sensitive-term post-filter on transcript text.
- Bundle model lookup supports both `Models/RuntimeAssets/` and legacy root-resource fallback paths.
- Model resolution order for Whisper decoder:
  1. cached `Library/Caches/WhisperGGML/ggml-large-v3-turbo.bin`
  2. bundled `ggml-large-v3-turbo.bin` (copied into cache when needed)
  3. runtime download fallback (if not available locally)
- CoreML encoder cache (`Library/Caches/WhisperGGML/ggml-large-v3-turbo-encoder.mlmodelc`) is only materialized when CoreML encoder mode is enabled.
