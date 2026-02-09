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

### `toggleLanguageFocus(_ code: String) -> Void`
- Adds/removes language code used to build pre-flight prompt.

### `playTranscriptChunk(_ row: TranscriptRow) -> Void`
- Plays one transcript row chunk from the active session audio file.
- Also triggers on-demand Whisper transcription for that row and updates row text if inference succeeds.
- On-demand transcription always uses Whisper language auto-detect (`preferredLanguageCode = "auto"`).
- On-demand transcription uses the pre-flight prompt template with Language Focus + context keywords as `initial_prompt`.
- If inference returns empty text, backend reports `No speech detected in this chunk.`
- Requires valid row offsets (`startOffset`, `endOffset`) and recording must be stopped.
- If constraints are not met, call is a no-op.

## PreflightService

### `prepare(languageCodes:focusKeywords:remainingCreditSeconds:) async throws -> PreflightConfig`
- Validates credits.
- Builds prompt string from language focus and context keywords.

### `buildPrompt(languageCodes:keywords:) -> String`
- Returns:
  - `This is a verbatim transcript of a meeting in [LANGUAGES]. The speakers switch between languages naturally. Transcribe exactly what is spoken in the original language. Do not translate. Context: [KEYWORDS].`

## LiveSessionPipeline

### `start(config: LivePipelineConfig) -> AsyncStream<PipelineEvent>`
- Starts concurrent live pipeline and streams events:
  - waveform
  - timer
  - transcript merged events
  - stopped
- Uses native CoreML Silero VAD for speech detection when available.
- Uses native CoreML WeSpeaker embedding (`wespeaker_v2.mlmodelc`) for speaker matching when available.
- Emits deferred transcript placeholder text during recording; Whisper transcription is run later on tap.
- Falls back to amplitude-threshold gating if VAD cannot initialize.
- Falls back to lightweight heuristic speaker matching if speaker model cannot initialize.

### `stop() -> Void`
- Stops pipeline and ends stream.

## SileroVADCoreMLService

### `prepareIfNeeded() async throws -> Void`
- Resolves bundled `silero-vad-unified-256ms-v6.0.0.mlmodelc` first.
- Falls back to cache/download if bundle resource is unavailable.

### `ingest(samples:sampleRate:) throws -> Float?`
- Accepts PCM frames, resamples to 16kHz, runs recurrent CoreML VAD windowing, and returns latest speech probability.

### `reset() -> Void`
- Clears audio/state buffers between recording sessions.

## SpeakerDiarizationCoreMLService

### `prepareIfNeeded() async throws -> Void`
- Resolves bundled `wespeaker_v2.mlmodelc` first.
- Falls back to cache/download if bundle resource is unavailable.

### `embedding(for:sampleRate:) throws -> [Float]?`
- Accepts PCM samples, resamples to 16kHz, prepares fixed model window, and returns normalized speaker embedding vector.

### `reset() -> Void`
- Stateless reset hook (kept for pipeline lifecycle symmetry).

## SessionStore

### `createSession(title:languageHints:) throws -> UUID`
- Creates session files and runtime row.

### `appendTranscript(sessionID:event:) -> Void`
- Appends transcript row, updates duration, persists `segments.json` snapshot.
- Persists `startOffset`/`endOffset` on each row for chunk playback.
- Stores deferred placeholder text until bubble-tap transcription updates row text.

### `updateTranscriptRow(sessionID:rowID:text:language:) -> Void`
- Patches one persisted transcript row with inferred Whisper text/language.

### `snapshotSessions() -> [ChatSession]`
- Returns session list for Library UI.

### `transcriptRows(for:) -> [TranscriptRow]`
- Returns rows for active chat timeline.
