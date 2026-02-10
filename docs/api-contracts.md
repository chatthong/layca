# API Contracts (Internal)

## AppBackend (UI-facing)

### `toggleRecording() -> Void`
- Starts or stops recording flow.
- On start, runs pre-flight before pipeline starts.
- Surfaces microphone permission denial as user-visible preflight message.

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
- Requires valid row offsets (`startOffset`, `endOffset`) and recording must be stopped.
- If constraints are not met, call is a no-op.

### `editTranscriptRow(_ row: TranscriptRow, text: String) -> Void`
- Applies a manual transcript text edit for a row.
- Keeps row language metadata and persists updated text immediately.

### `editSpeakerName(_ row: TranscriptRow, name: String) -> Void`
- Renames the speaker profile for `row.speakerID`.
- Propagates the updated name to every row in the active session with the same `speakerID`.

### `changeSpeaker(_ row: TranscriptRow, to speakerID: String) -> Void`
- Reassigns one row to another existing speaker profile in the active session.
- Updates speaker label/avatar color metadata on that row to match the target speaker profile.

### `retranscribeTranscriptRow(_ row: TranscriptRow) -> Void`
- Re-runs Whisper for the row's chunk range from session audio.
- Uses auto language detect with translation disabled and patches row text/language.

## PreflightService

### `prepare(languageCodes:focusKeywords:remainingCreditSeconds:) async throws -> PreflightConfig`
- Validates credits.
- Builds prompt string from language focus and context keywords.

### `buildPrompt(languageCodes:keywords:) -> String`
- Returns:
  - `This is a verbatim transcript of a meeting in [LANGUAGES]. The speakers switch between languages naturally. Transcribe exactly what is spoken in the original language, including profanity, violence, drug terms, and other sensitive words. Do not censor, mask, or replace words. Do not translate. Context: [KEYWORDS].`

## LiveSessionPipeline

### `start(config: LivePipelineConfig) -> AsyncStream<PipelineEvent>`
- Starts concurrent live pipeline and streams events:
  - waveform
  - timer
  - transcript merged events
  - stopped
- Uses native CoreML Silero VAD for speech detection when available.
- Uses native CoreML WeSpeaker embedding (`wespeaker_v2.mlmodelc`) for speaker matching when available.
- Emits deferred transcript placeholder text during recording; backend auto-queues Whisper transcription.
- Falls back to amplitude-threshold gating if VAD cannot initialize.
- Falls back to lightweight heuristic speaker matching if speaker model cannot initialize.

### `stop() -> Void`
- Stops pipeline and ends stream.

## Platform Permission Behavior

### macOS
- Recording permission is requested through `AVAudioApplication.requestRecordPermission`.
- If denied, backend throws `MasterRecorderError.microphonePermissionDenied`.
- UI is expected to offer a deep-link action to Privacy & Security > Microphone.

### iOS-family
- Uses `AVAudioApplication.requestRecordPermission` on modern runtimes.
- Falls back to `AVAudioSession.requestRecordPermission` on older runtimes.

## SileroVADCoreMLService

### `prepareIfNeeded() async throws -> Void`
- Resolves bundled `silero-vad-unified-256ms-v6.0.0.mlmodelc` first.
- Bundle lookup supports `Models/RuntimeAssets/` and root-resource fallback locations.
- Falls back to cache/download if bundle resource is unavailable.

### `ingest(samples:sampleRate:) throws -> Float?`
- Accepts PCM frames, resamples to 16kHz, runs recurrent CoreML VAD windowing, and returns latest speech probability.

### `reset() -> Void`
- Clears audio/state buffers between recording sessions.

## SpeakerDiarizationCoreMLService

### `prepareIfNeeded() async throws -> Void`
- Resolves bundled `wespeaker_v2.mlmodelc` first.
- Bundle lookup supports `Models/RuntimeAssets/` and root-resource fallback locations.
- Falls back to cache/download if bundle resource is unavailable.

### `embedding(for:sampleRate:) throws -> [Float]?`
- Accepts PCM samples, resamples to 16kHz, prepares fixed model window, and returns normalized speaker embedding vector.

### `reset() -> Void`
- Stateless reset hook (kept for pipeline lifecycle symmetry).

## WhisperGGMLCoreMLService

### `prepareIfNeeded() async throws -> Void`
- Initializes Whisper context and runs a one-time warmup inference.
- Bundle lookup for decoder/encoder supports `Models/RuntimeAssets/` and root-resource fallback locations.
- Available for explicit warmup flows, but is not called automatically on app launch.

### `transcribe(audioURL:startOffset:endOffset:preferredLanguageCode:initialPrompt:) async throws -> WhisperTranscriptionResult`
- Loads chunk audio, resamples to 16kHz, and runs `whisper.cpp`.
- Default runtime path uses non-CoreML encoder for reliability.
- CoreML encoder path can be enabled with environment variable `LAYCA_ENABLE_WHISPER_COREML_ENCODER=1`.

### `transcribe(samples:sourceSampleRate:preferredLanguageCode:initialPrompt:) async throws -> WhisperTranscriptionResult`
- Transcribes in-memory chunk PCM and resamples to 16kHz internally.
- Used by backend automatic queue worker so chunk inference does not depend on reading from the active recording file.

## SessionStore

### `createSession(title:languageHints:) throws -> UUID`
- Creates session files and runtime row.

### `appendTranscript(sessionID:event:) -> Void`
- Appends transcript row, updates duration, persists `segments.json` snapshot.
- Persists `startOffset`/`endOffset` on each row for chunk playback.
- Stores deferred placeholder text until queued automatic transcription updates row text.

### `updateTranscriptRow(sessionID:rowID:text:language:) -> Void`
- Patches one persisted transcript row with inferred Whisper text/language.

### `updateSpeakerName(sessionID:speakerID:newName:) -> Void`
- Renames one stored speaker profile and updates all rows that reference that `speakerID`.

### `changeTranscriptRowSpeaker(sessionID:rowID:targetSpeakerID:) -> Void`
- Rebinds a row to another existing speaker profile in the same session.

### `snapshotSessions() -> [ChatSession]`
- Returns session list for Library UI.

### `transcriptRows(for:) -> [TranscriptRow]`
- Returns rows for active chat timeline.
