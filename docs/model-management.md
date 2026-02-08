# Model Management

## Strategy
- Ship app without heavy model binaries.
- Prompt user to install model on first use.
- Support fallback model sizes for low-storage devices.

## Paths
- Primary model directory: `Library/Application Support/Models/`
- Example:
  - `ggml-large-v3-turbo-q8_0.bin`
  - `coreml-encoder/`

## Download Workflow
1. Check model presence and checksum.
2. If missing, start background `URLSessionDownloadTask`.
3. Show progress and estimated size.
4. Verify checksum/hash after download.
5. Move file atomically to model directory.
6. Mark install active in local database.

## Failure Handling
- Resume interrupted downloads where possible.
- Keep partial files isolated under temporary directory.
- Display clear retry and storage guidance.

## UX Rules
- Disable recording/transcription actions until active model is ready.
- Provide a compact status card on the home screen:
  - Not Installed
  - Downloading (% complete)
  - Installed (active model)
