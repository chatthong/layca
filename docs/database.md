# Database Design

## Current Runtime Persistence
- **Primary runtime store:** in-memory actor store (`SessionStore`) for session/transcript state.
- **Primary durable store:** filesystem (`Documents/Models`, `Documents/Sessions`).
- **Planned:** migrate/extend to `SwiftData` for long-term query/index workflows.

## Runtime Entities (Current)

### Session (runtime model)
- `id: UUID`
- `title: String`
- `createdAt: Date`
- `languageHints: [String]`
- `modelID: String`
- `audioFilePath: String`
- `segmentsFilePath: String`
- `durationSeconds: Double`
- `status: SessionStatus` (`recording`, `processing`, `ready`, `failed`)

### Transcript Row (runtime model)
- `id: UUID`
- `speaker: String`
- `text: String`
- `time: String` (`HH:mm:ss`)
- `language: String` (e.g., `EN`, `TH`)
- `avatarSymbol: String`
- `avatarPalette: [Color]`

### Speaker Profile (session-scoped)
- `label: String` (e.g., `Speaker A`)
- `colorHex: String`
- `avatarSymbol: String`

## Filesystem Layout
```text
Documents/
├── Models/
│   ├── ggml-large-v3-turbo-q8_0.bin
│   ├── ggml-large-v3-turbo-q5_0.bin
│   └── ggml-large-v3-turbo.bin
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
   - rewrite `segments.json` snapshot
3. On recording stop:
   - mark session status to `ready`
4. On future deletion flow:
   - remove session row/state first, then filesystem assets.

## Consistency Rules Implemented
- Speaker appearance remains stable within session once assigned.
- Transcript updates are append-only during a running session.
- UI consumes state reactively from backend-published session snapshots.
