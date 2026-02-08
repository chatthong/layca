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

## Runtime Workflow
1. User selects model.
2. App checks if model file exists.
3. If installed, model becomes active immediately.
4. If missing, app enters download/install flow.
5. On record press, pre-flight validates model and may fallback to another installed model.

## Current Implementation State
- Backend has model metadata, local file checks, and fallback logic.
- Download UI is simulated with placeholder install path.
- Next step is replacing placeholder install with real `URLSessionDownloadTask` from the URLs above.

## UX Rules
- Disable recording until at least one model is available.
- Show clear state per row:
  - Not Installed
  - Downloading
  - Installed (Active)
