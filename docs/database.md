# Database Design

## Current Runtime Persistence
- **Primary runtime store:** in-memory actor store (`SessionStore`) for session/transcript state.
- **Primary durable store:** filesystem (`Documents/Sessions`).
- **Bundled runtime asset:** CoreML VAD model directory in app bundle (`silero-vad-unified-256ms-v6.0.0.mlmodelc`) for offline startup.
- **Bundled runtime asset:** CoreML speaker model directory in app bundle (`wespeaker_v2.mlmodelc`) for offline startup.
- **Bundled runtime asset:** Whisper decoder model file in app bundle (`ggml-large-v3-turbo.bin`) for offline startup.
- **Bundled runtime asset:** Whisper CoreML encoder directory in app bundle (`ggml-large-v3-turbo-encoder.mlmodelc`) for optional encoder acceleration.
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
- `text` initially stores deferred placeholder and is replaced by queued automatic Whisper result.

### Speaker Profile (session-scoped)
- `label: String` (e.g., `Speaker A`)
- `colorHex: String`
- `avatarSymbol: String`
- Stored in a dictionary keyed by `speakerID`.

## Filesystem Layout
```text
Documents/
└── Sessions/
    └── {UUID}/
        ├── session_full.m4a
        └── segments.json
```

## Data Lifecycle
1. Create session directory and base files on new chat/session.
2. On each merged transcript event:
   - append row to session runtime store
   - refresh session duration
   - keep row chunk offsets for playback
   - rewrite `segments.json` snapshot
3. On each queued transcription update:
   - patch one existing row text/language
   - rewrite `segments.json` snapshot
4. On speaker edit/reassign actions:
   - rename all rows by shared `speakerID` or rebind one row to another `speakerID`
   - rewrite `segments.json` snapshot
5. On recording stop:
   - mark session status to `ready`
6. On future deletion flow:
   - remove session row/state first, then filesystem assets.

## Consistency Rules Implemented
- Speaker appearance remains stable within session once assigned.
- Transcript updates are append-only during a running session.
- UI consumes state reactively from backend-published session snapshots.
- Transcript chunk playback is valid only for rows with non-nil offsets where `endOffset > startOffset`.
