# API Contracts (Internal)

## AppBackend (UI-facing)

### `toggleRecording() -> Void`
- Starts or stops recording flow.
- On start, runs pre-flight before pipeline starts.

### `startNewChat() -> Void`
- Creates a new session and switches active session.

### `activateSession(_ session: ChatSession) -> Void`
- Sets active session and pushes its rows to chat UI.

### `renameActiveSessionTitle(_ newTitle: String) -> Void`
- Renames active session title (used by Chat header inline rename).

### `selectModel(_ option: ModelOption) -> Void`
- Changes active model or triggers model install simulation.

### `toggleLanguageFocus(_ code: String) -> Void`
- Adds/removes language code used to build pre-flight prompt.

## PreflightService

### `prepare(selectedModelID:languageCodes:remainingCreditSeconds:modelManager:) async throws -> PreflightConfig`
- Validates credits.
- Resolves selected model (with fallback if selected is missing but another installed model exists).
- Ensures model is loadable.
- Builds prompt string from language focus.

## ModelManager

### `installedModels() -> Set<BackendModel>`
- Returns models found in `Documents/Models/`.

### `ensureLoaded(_ model: BackendModel) async throws -> URL`
- Verifies model file exists and marks model as loaded.

### `installPlaceholderModel(_ model: BackendModel) throws`
- Current simulated install path for UI/testing.

## LiveSessionPipeline

### `start(config: LivePipelineConfig) -> AsyncStream<PipelineEvent>`
- Starts concurrent live pipeline and streams events:
  - waveform
  - timer
  - transcript merged events
  - stopped

### `stop() -> Void`
- Stops pipeline and ends stream.

## SessionStore

### `createSession(title:languageHints:modelID:) throws -> UUID`
- Creates session files and runtime row.

### `appendTranscript(sessionID:event:) -> Void`
- Appends transcript row, updates duration, persists `segments.json` snapshot.

### `snapshotSessions() -> [ChatSession]`
- Returns session list for Library UI.

### `transcriptRows(for:) -> [TranscriptRow]`
- Returns rows for active chat timeline.
