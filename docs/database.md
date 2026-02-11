# Database Design

## Current Runtime Persistence
- **Primary runtime store:** actor store (`SessionStore`) for session/transcript state.
- **Primary durable store:** filesystem (`Documents/Sessions`) plus per-session metadata/segment snapshots.
- **Settings durable store:** `UserDefaults` (`AppSettingsStore`) for app/UI state restore across relaunch.
- **Platform note:** same session layout is used on iOS-family and macOS within each platform's app sandbox container.
- **macOS style note:** sidebar-first `NavigationSplitView` and native toolbar controls do not change persistence schema or file layout.
- **Bundled runtime asset:** CoreML VAD model directory in app bundle (`silero-vad-unified-256ms-v6.0.0.mlmodelc`) for offline startup.
- **Bundled runtime asset:** CoreML speaker model directory in app bundle (`wespeaker_v2.mlmodelc`) for offline startup.
- **Bundled runtime asset:** Whisper decoder model files in app bundle:
  - `ggml-large-v3-turbo-q5_0.bin` (`Fast`)
  - `ggml-large-v3-turbo-q8_0.bin` (`Normal`)
  - `ggml-large-v3-turbo.bin` (`Pro`)
- **Bundled runtime asset:** Whisper CoreML encoder directory in app bundle (`ggml-large-v3-turbo-encoder.mlmodelc`) for optional encoder acceleration.
- **Project source location for bundled model assets:** `xcode/layca/Models/RuntimeAssets/` (copied into app resources during build).
- **Runtime cache workspace:** `Library/Caches/WhisperGGML` for cached Whisper decoder and optional CoreML encoder assets.
- **Planned:** migrate/extend to `SwiftData` for long-term query/index workflows.

## Runtime Entities (Current)

### Session (runtime model)
- `id: UUID`
- `title: String`
- `createdAt: Date`
- `languageHints: [String]`
- `audioFilePath: String`
- `segmentsFilePath: String`
- `metadataFilePath: String`
- `durationSeconds: Double`
- `status: SessionStatus` (`recording`, `processing`, `ready`, `failed`)

### Transcript Row (runtime model)
- `id: UUID`
- `speakerID: String` (stable per-session speaker identity key)
- `speaker: String`
- `text: String`
- `time: String` (`HH:mm:ss`)
- `language: String` (e.g., `EN`, `TH`)
- `avatarSymbol: String`
- `avatarPalette: [Color]`
- `startOffset: Double?` (seconds in `session_full.m4a`)
- `endOffset: Double?` (seconds in `session_full.m4a`)
- `text` initially stores deferred placeholder (`Message queued for automatic transcription...`) and is replaced by queued automatic Whisper result.
- Placeholder rows are deleted when transcription is unusable/no-speech.

### Speaker Profile (session-scoped)
- `label: String` (e.g., `Speaker A`)
- `colorHex: String`
- `avatarSymbol: String`
- Stored in a dictionary keyed by `speakerID`.

### Persisted App Settings
- `selectedLanguageCodes: [String]`
- `languageSearchText: String`
- `focusContextKeywords: String`
- `totalHours: Double`
- `usedHours: Double`
- `isICloudSyncEnabled: Bool`
- `whisperCoreMLEncoderEnabled: Bool`
- `whisperGGMLGPUDecodeEnabled: Bool`
- `whisperModelProfileRawValue: String` (`quick` / `normal` / `pro`)
- `activeSessionID: UUID?`
- `chatCounter: Int`

## Filesystem Layout
```text
Documents/
└── Sessions/
    └── {UUID}/
        ├── session_full.m4a
        ├── session.json
        └── segments.json
```

## Data Lifecycle
1. On app launch, `SessionStore` scans `Documents/Sessions`, reloads each `{UUID}` folder, and hydrates in-memory session order/state.
2. Create session directory and base files on new chat/session.
3. On each merged transcript event:
   - append row to session runtime store
   - refresh session duration
   - keep row message offsets for playback
   - rewrite `session.json` metadata snapshot
   - rewrite `segments.json` snapshot
4. On each queued transcription update:
   - patch one existing row text/language
   - rewrite `segments.json` snapshot
   - delete row when result is unusable/no-speech placeholder quality
5. On speaker edit/reassign actions:
   - rename all rows by shared `speakerID` or rebind one row to another `speakerID`
   - rewrite `session.json` metadata snapshot
   - rewrite `segments.json` snapshot
6. On recording stop:
   - mark session status to `ready`
7. On session delete:
   - remove session runtime row/state
   - remove session directory (`Documents/Sessions/{UUID}`) and its files.
8. On app setting updates:
   - rewrite `UserDefaults` snapshot for settings + active chat metadata.

## Consistency Rules Implemented
- Speaker appearance remains stable within session once assigned.
- Transcript updates are append-only during a running session.
- UI consumes state reactively from backend-published session snapshots.
- Transcript message playback is valid only for rows with non-nil offsets where `endOffset > startOffset`.
- Session list, chat title, transcript rows, and speaker metadata are restored after app relaunch.
