# Model Management

## Strategy
- App ships without model binaries.
- User chooses one model in Settings.
- Recording is gated by model readiness + credit.

## Active Catalog

### Normal AI
- File: `ggml-large-v3-turbo-q8_0.bin`
- URL: `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q8_0.bin?download=true`

### Light AI
- File: `ggml-large-v3-turbo-q5_0.bin`
- URL: `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin?download=true`

### High Detail AI
- File: `ggml-large-v3-turbo.bin`
- URL: `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin?download=true`

## Paths
- Model directory: `Documents/Models/`
- Bundled VAD directory: app bundle `silero-vad-unified-256ms-v6.0.0.mlmodelc` (CoreML Silero, offline-first)
- Bundled speaker directory: app bundle `wespeaker_v2.mlmodelc` (CoreML WeSpeaker, offline-first)

## Runtime Workflow
1. User selects model.
2. App checks if model file exists.
3. If installed, model becomes active immediately.
4. If missing, app enters download/install flow.
5. On record press, pre-flight validates model and may fallback to another installed model.

## Current Implementation State
- Backend has model metadata, local file checks, fallback logic, and real download/install for Whisper model binaries.
- CoreML Silero VAD is bundled in app resources and loaded locally first.
- If bundled VAD resource is unavailable, cache/download fallback is used.
- CoreML speaker model (`wespeaker_v2.mlmodelc`) is bundled in app resources and loaded locally first.
- If bundled speaker resource is unavailable, cache/download fallback is used.

## UX Rules
- Disable recording until at least one model is available.
- Show clear state per row:
  - Not Installed
  - Downloading
  - Installed (Active)
