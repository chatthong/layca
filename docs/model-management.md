# Model Management

## Status
- Whisper runtime is integrated via `whisper.cpp` (`whisper.xcframework`).
- Transcription is currently queued automatically per message chunk (serial one-by-one mode).
- Settings provides:
  - Language Focus (multi-select)
  - Context keywords (free text), used in Whisper `initial_prompt`
  - Advanced Zone:
    - Whisper ggml GPU Decode (toggle)
    - Whisper CoreML Encoder (toggle)
    - Model Switch (`Fast`, `Normal`, `Pro`)
- On macOS, the same model-related settings are shown in the native settings workspace form.
- macOS settings view is reachable from sidebar `Setting`.
- Initial Advanced Zone values are auto-detected by device and persisted; users can override anytime.

## Current Runtime Assets
- Bundled VAD directory: app bundle `silero-vad-unified-256ms-v6.0.0.mlmodelc` (CoreML Silero, offline-first)
- Bundled speaker directory: app bundle `wespeaker_v2.mlmodelc` (CoreML WeSpeaker, offline-first)
- Bundled Whisper decoder profiles:
  - `Fast` -> `ggml-large-v3-turbo-q5_0.bin`
  - `Normal` -> `ggml-large-v3-turbo-q8_0.bin`
  - `Pro` -> `ggml-large-v3-turbo.bin`
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

## Manual Re-transcribe Behavior
- Bubble action `Transcribe Again` provides:
  - `Transcribe Auto` (auto language detect)
  - `Transcribe in <Focus Language>` (entries come from selected focus languages only)
- Manual language override runs with `preferredLanguageCode = <forced code>` and translation disabled.
- Forced `TH` / `EN` retries validate output script:
  - first pass uses standard prompt flow
  - on script mismatch, backend retries once without prompt
  - if mismatch persists, existing row text is kept (no low-confidence warning banner)

## Whisper Startup / Backend Selection
- App applies runtime preferences during bootstrap and triggers background Whisper prepare/warmup to reduce first-use latency.
- Runtime preference sources:
  1. App settings (`Advanced Zone`) via `setRuntimePreferences(...)` (highest priority in app flow)
  2. Environment fallback at service level
- Runtime acceleration env toggles:
  - `LAYCA_ENABLE_WHISPER_COREML_ENCODER`
  - `LAYCA_ENABLE_WHISPER_GGML_GPU_DECODE`
- On physical iOS devices, CoreML encoder uses an auto profile:
  - ON for higher-tier devices (more RAM/cores) to maximize performance
  - OFF for lower-tier devices to avoid startup stalls with `large-v3-turbo`
- iOS override flag:
  - `LAYCA_FORCE_WHISPER_COREML_ENCODER_IOS=ON`
- Model profile auto defaults:
  - simulator: `Fast`
  - higher-tier iOS-family: `Normal` or `Pro` by RAM/cores
  - macOS: `Pro`
- Runtime logs resolved mode:
  - `[Whisper] Model: Fast/Normal/Pro, CoreML encoder: ON/OFF, ggml GPU decode: ON/OFF`
- If ggml GPU context initialization fails, runtime falls back to CPU decode and logs fallback reason.
- On some iPhones, CoreML may print ANE recompile/plan-build warnings on first run; this can be slow but is typically recoverable.

## Pre-flight Behavior
1. User taps record.
2. Pre-flight validates available credits.
3. Pre-flight builds the Whisper prompt from language focus + context keywords.
4. Pipeline starts when pre-flight succeeds.

## Notes
- App runtime does not apply a profanity/sensitive-term post-filter on transcript text.
- Bundle model lookup supports both `Models/RuntimeAssets/` and legacy root-resource fallback paths.
- Model resolution order for selected Whisper decoder profile:
  1. profile-specific cached file under `Library/Caches/WhisperGGML/`
  2. bundled profile file from app resources (copied to cache when needed)
  3. runtime download fallback (currently configured for `Pro` model file)
- CoreML encoder cache (`Library/Caches/WhisperGGML/ggml-large-v3-turbo-encoder.mlmodelc`) is only materialized when CoreML encoder mode is enabled.
