# API Contracts (Internal)

## AppBackend (UI-facing)

### `toggleRecording() -> Void`
- Starts or stops recording flow.
- If current state is draft (`activeSessionID == nil`), start path creates a new persisted session first (`chat N` naming flow), then starts recording.
- On start, runs pre-flight before pipeline starts.
- If transcript chunk playback is active, call stops playback (player mode stop action) instead of starting recording.
- Surfaces microphone permission denial as user-visible preflight message.

### `startNewChat() -> Void`
- Resets selection to draft mode (`activeSessionID = nil`) and clears active transcript rows.
- Does not create a persisted session immediately.
- Used by iOS/iPadOS sidebar `New Chat` compose action, visionOS/tvOS `New Chat` tab action, and macOS sidebar `New Chat` action.
- Persisted session is created on first record tap from draft mode.

### `activateSession(_ session: ChatSession) -> Void`
- Sets active session and pushes its rows to chat UI.

### `recordingTimeText` (published display value)
- Value is formatted by selected `mainTimerDisplayStyle` (`friendly`, `hybrid`, `professional`).
- Saved chat mode displays accumulated duration from persisted transcript offsets.
- During recording, value displays `currentRecordingBaseOffset + liveElapsedSeconds` so resumed recordings continue from prior duration.

### `mainTimerDisplayStyle` (published setting)
- Controls main timer formatting only.
- Supported values:
  - `friendly` (trim zero units, e.g. `11 sec`, `5 min 22 sec`, `1 hr 5 sec`)
  - `hybrid` (e.g. `5:22`, `1:05:22`)
  - `professional` (e.g. `00:05:22`)
- Default is `friendly`.

### `renameActiveSessionTitle(_ newTitle: String) -> Void`
- Renames active session title (used by Chat header inline rename).
- Used by both iOS and macOS inline chat-title edit flows.

### `renameSession(_ session: ChatSession, to newTitle: String) -> Void`
- Renames a specific session (used by session-list context-menu rename actions in Library where present and sidebar `Recent Chats`).

### `deleteSession(_ session: ChatSession) -> Void`
- Deletes a specific session from runtime store and filesystem storage.
- If deleted session is active, backend clears active selection and reloads next available session.

### `shareText(for session: ChatSession) -> String`
- Returns share-ready plain text for a session (title/date + transcript rows).
- Used by session-list `Share this chat` actions (Library where present and sidebar `Recent Chats`).

## macOS Workspace UI Actions (View-level Wiring)
- Chat-detail toolbar `More` menu `Share` action presents export sheet (`isExportPresented`) from `ContentView`.
- Sidebar toolbar `New Chat` action calls `startNewChat()` (via `startNewChatAndReturnToChat` in `ContentView`).
- Sidebar workspace `Settings` row presents the settings modal sheet.
- Sidebar workspace `Layca Chat` action routes through draft-open behavior in `ContentView` (`openLaycaChatWorkspace`).
- Chat header inline-rename UX (iOS + macOS):
  - entering edit mode hides non-title header actions
  - tapping outside edit context (content/sidebar/focus-loss path) cancels edit without applying changes
- iOS non-edit chat-title pill:
  - width auto-sizes from title text with min/max bounds
  - applies tail truncation only when the max width limit is reached
- iOS trailing chat-header control group (`Play` + `More`) uses an explicit ellipsis overflow label in compact toolbar width so the collapsed control remains visibly tappable.
- Recording transcript follow UX (iOS + macOS):
  - incoming rows during recording show `New message` (no forced auto-follow by default)
  - tapping `New message` jumps to bottom and enables follow mode
  - follow mode disables when user scrolls away from bottom
- Recorder bottom-bar UX (iOS + macOS):
  - draft idle state shows starter text (`Tap to start record` / `Click to start record`) until recording starts
  - transcript playback state changes action to `Stop`, switches recorder tint green, and shows countdown + segment range subtitle

## Export Sheet UI Contract (View-level)
- `ExportSheetFlowView` presents a root list of export formats and pushes into a single format detail step.
- Format detail preview text is intentionally truncated to the first 11 lines; a trailing ellipsis line is appended when additional content exists.
- On macOS format detail step, `Actions` displays `Share` and `Copy`/`Copied` in one horizontal row.

### `toggleLanguageFocus(_ code: String) -> Void`
- Adds/removes language code used to build pre-flight prompt.

### `playTranscriptChunk(_ row: TranscriptRow) -> Void`
- Plays one transcript row chunk from the active session audio file.
- Requires valid row offsets (`startOffset`, `endOffset`) and recording must be stopped.
- When active, backend publishes playback countdown (`transcriptChunkPlaybackRemainingText`) and segment-range subtitle (`transcriptChunkPlaybackRangeText`, `mm:ss → mm:ss`) for recorder player mode.
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
- Queues a manual re-transcribe for the row's audio range.
- Equivalent to calling language-override variant with `preferredLanguageCodeOverride = nil`.

### `retranscribeTranscriptRow(_ row: TranscriptRow, preferredLanguageCodeOverride: String?) -> Void`
- Queues a manual re-transcribe for the row's audio range with optional language override.
- `preferredLanguageCodeOverride = nil` keeps auto language detection behavior.
- Non-nil override forces decode to that language code for the retry (e.g., `th`, `en`).
- Current execution guard: while recording, backend shows `Stop recording before running Transcribe Again.` and waits for stopped state.
- Uses translation-disabled decode and patches row text/language.
- Forced `TH` / `EN` retries validate output script, retry once without prompt if mismatched, and keep existing text when mismatch persists.

## PreflightService

### `prepare(languageCodes:focusKeywords:remainingCreditSeconds:) async throws -> PreflightConfig`
- Validates credits.
- Builds prompt string from language focus and context keywords.

### `buildPrompt(languageCodes:keywords:) -> String`
- Returns:
  - `STRICT VERBATIM MODE. Never translate under any condition. Never summarize. Never rewrite... Context: [KEYWORDS].`

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
- Called by app backend in a background prewarm task after runtime preferences are applied.

### `setRuntimePreferences(coreMLEncoderEnabled:ggmlGPUDecodeEnabled:modelProfile:) -> Void`
- Applies runtime backend/model preference overrides.
- `modelProfile` maps to:
  - `quick` (`Fast`) -> `ggml-large-v3-turbo-q5_0.bin`
  - `normal` -> `ggml-large-v3-turbo-q8_0.bin`
  - `pro` -> `ggml-large-v3-turbo.bin`
- Forces context reset so next prepare/transcribe uses the selected combination.

### `transcribe(audioURL:startOffset:endOffset:preferredLanguageCode:initialPrompt:) async throws -> WhisperTranscriptionResult`
- Loads chunk audio, resamples to 16kHz, and runs `whisper.cpp`.
- Runtime acceleration can be controlled by environment variables:
  - `LAYCA_ENABLE_WHISPER_COREML_ENCODER`
  - `LAYCA_ENABLE_WHISPER_GGML_GPU_DECODE`
- App-managed runtime settings override env defaults in normal app flow.
- Runtime logs resolved mode (`Model`, `CoreML`, `ggml GPU`) and falls back to CPU decode when ggml GPU decode init fails.

### `transcribe(samples:sourceSampleRate:preferredLanguageCode:initialPrompt:) async throws -> WhisperTranscriptionResult`
- Transcribes in-memory chunk PCM and resamples to 16kHz internally.
- Used by backend automatic queue worker so chunk inference does not depend on reading from the active recording file.

## SessionStore

### `createSession(title:languageHints:) throws -> UUID`
- Creates session files (`session_full.m4a`, `segments.json`, `session.json`) and runtime row.

### `appendTranscript(sessionID:event:) -> Void`
- Appends transcript row, updates duration, persists `segments.json` + `session.json` snapshots.
- Persists `startOffset`/`endOffset` on each row for chunk playback.
- Stores deferred placeholder text until queued automatic transcription updates row text.

### `updateTranscriptRow(sessionID:rowID:text:language:) -> Void`
- Patches one persisted transcript row with inferred Whisper text/language.
- Language value is resolved from detected Whisper language (`AUTO` fallback when unknown).

### `updateSpeakerName(sessionID:speakerID:newName:) -> Void`
- Renames one stored speaker profile and updates all rows that reference that `speakerID`.

### `changeTranscriptRowSpeaker(sessionID:rowID:targetSpeakerID:) -> Void`
- Rebinds a row to another existing speaker profile in the same session.

### `deleteSession(sessionID:) -> Void`
- Deletes session from in-memory store and removes `Documents/Sessions/{UUID}` directory.

### `snapshotSessions() -> [ChatSession]`
- Returns session list for Library or sidebar `Recent Chats` UI surfaces.
- Ensures store is hydrated from disk before snapshotting.

### `transcriptRows(for:) -> [TranscriptRow]`
- Returns rows for active chat timeline.

## AppSettingsStore

### `load() -> PersistedAppSettings?`
- Loads persisted app/UI setting snapshot from `UserDefaults`.
- Snapshot includes Whisper runtime preferences (`whisperCoreMLEncoderEnabled`, `whisperGGMLGPUDecodeEnabled`, `whisperModelProfileRawValue`) and main timer display style (`mainTimerDisplayStyleRawValue`).

### `save(_ settings: PersistedAppSettings) -> Void`
- Persists app/UI setting snapshot to `UserDefaults`.
