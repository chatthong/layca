# Database Design

## Persistence Choice
- `SwiftData` (iOS 17+) for app entities and query support.
- Filesystem for large binary assets and audio recordings.

## Core Entities

### Session
- `id: UUID`
- `createdAt: Date`
- `startedAt: Date`
- `endedAt: Date?`
- `title: String`
- `languageHints: [String]`
- `audioFilePath: String`
- `durationSeconds: Double`
- `status: SessionStatus` (`recording`, `processing`, `ready`, `failed`)

### TranscriptSegment
- `id: UUID`
- `sessionID: UUID`
- `index: Int`
- `speakerID: String`
- `text: String`
- `audioStartOffset: Double`
- `audioEndOffset: Double`
- `confidence: Double?`
- `createdAt: Date`

### Speaker
- `id: UUID`
- `sessionID: UUID`
- `label: String` (e.g., Speaker A)
- `colorHex: String?`

### ModelInstall
- `id: UUID`
- `modelName: String`
- `modelVersion: String`
- `localPath: String`
- `sizeBytes: Int64`
- `isActive: Bool`
- `installedAt: Date`

## Storage Separation
- DB stores metadata and indices.
- `Documents/Sessions/{UUID}/full_recording.m4a` stores source audio.
- `Documents/Sessions/{UUID}/segments.json` stores portable transcript snapshot.
- `Library/Application Support/Models/` stores downloaded model binaries.

## Indexing Guidance
- Index by `sessionID` + `index` for segment rendering.
- Index by `startedAt` for list sorting.
- Index `status` for in-progress and failed recovery screens.

## Data Lifecycle
1. Create session row when recording starts.
2. Append segments incrementally while transcribing.
3. Finalize session metadata when processing completes.
4. On delete, remove DB rows first, then filesystem assets.
