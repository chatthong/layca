# Sprint 8 — Chunk-File Session Architecture

> Synthesized from audio-processing-lead-2 and ml-inference-lead-2 reports (2026-02-22)

## Why

Currently two separate audio pipelines run simultaneously during recording:

1. `LiveAudioInputController` — `AVAudioEngine` tap → raw PCM → live Whisper (low quality: linear-interp resampling, no AAC filtering)
2. `MasterAudioRecorder` — `AVAudioRecorder` → `session_full.m4a` (high quality: hardware AAC encoder)

The quality gap between the two is why "Transcribe Again" always produces better results than live transcription. The fix: **make every chunk transcription use the same AAC encode/decode path as "Transcribe Again"**.

### Target architecture

```
Sessions/{sessionUUID}/
  chunks/
    chunk-{rowUUID1}.m4a     ← bubble 1 audio (self-contained)
    chunk-{rowUUID2}.m4a     ← bubble 2 audio
    ...
  session.json               ← TranscriptRow.chunkURL points here; startOffset/endOffset kept for ordering
```

Each bubble has its own M4A file. Transcription, playback, and "Transcribe Again" all read from `chunkURL` directly. No master recording. No offset arithmetic. No post-recording quality pass.

---

## What Gets Removed (~320 lines)

| Code | Location |
|---|---|
| `class MasterAudioRecorder` (entire) | AppBackend.swift:101–345 |
| `MasterRecorderError` enum | AppBackend.swift:83–98 |
| `mergeAudioFilesWithRetries` + `mergeAudioFiles` | included above |
| `schedulePostRecordingQualityPass` | AppBackend.swift:3610–3622 |
| `whisperTranscriber.transcribe(samples:sourceSampleRate:)` overload | WhisperGGMLCoreMLService.swift:187–207 |
| `QueuedChunkTranscription.samples: [Float]` + `.sampleRate` | AppBackend.swift |
| `sessionStore.audioFileURL(for:)` (recording use) | SessionStore |
| `hasRecordedAudio(for:)` | SessionStore |
| `audioDurationSeconds(for:)` | SessionStore |
| `currentRecordingBaseOffset` complex calculation (replaced by row-based calc) | AppBackend.swift |

---

## What Gets Added

### 1. `ChunkAudioWriter` actor (new file: `Services/ChunkAudioWriter.swift`)

Writes VAD-cut PCM samples to per-chunk M4A files. Isolated actor so it never blocks the real-time pipeline.

```swift
actor ChunkAudioWriter {
    /// Writes `samples` at `sampleRate` to `chunk-{rowID}.m4a` inside `chunksDirectory`.
    /// File is fully finalized (closed) before this function returns.
    /// Caller must await this before enqueuing the chunk URL for transcription.
    func write(
        samples: [Float],
        sampleRate: Double,
        rowID: UUID,
        chunksDirectory: URL
    ) async throws -> URL {
        let url = chunksDirectory.appendingPathComponent("chunk-\(rowID.uuidString).m4a")
        let sourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!
        let fileSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: sampleRate,       // native rate — match tap, preserve fidelity
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let file = try AVAudioFile(forWriting: url, settings: fileSettings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        let buffer = AVAudioPCMBuffer(
            pcmFormat: sourceFormat,
            frameCapacity: AVAudioFrameCount(samples.count)
        )!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { ptr in
            buffer.floatChannelData![0].initialize(from: ptr.baseAddress!, count: samples.count)
        }
        try file.write(from: buffer)
        // AVAudioFile closes/finalizes on dealloc — file is complete after this scope exits
        return url
    }
}
```

**Notes:**
- `AVAudioFile` over `AVAssetWriter` — chunk is a complete buffer, not a stream. 4 lines vs. 30+.
- Write at **native tap sample rate** (44.1kHz or 48kHz as captured) — don't force 44.1kHz like the old master.
- Actor serialization handles backpressure automatically. Inter-chunk interval (~3–10s) >> write time (~50–300ms). No explicit queue cap needed.

---

### 2. `TranscriptRow` — add `chunkURL`

```swift
// TranscriptRow.swift
var chunkURL: URL?          // nil for sessions recorded before Sprint 8

// Keep these — still useful for ordering, timeline, export sorting, legacy retranscription
var startOffset: Double?
var endOffset: Double?
```

`chunkURL` is a relative URL stored in JSON: `"chunks/chunk-{uuid}.m4a"`. Resolved against `sessionDirectory` at read time. Relative paths survive iCloud sync and device migrations.

---

### 3. `WhisperGGMLCoreMLService` — new overload

```swift
// ~12 lines — reads entire chunk file, no offset arithmetic
func transcribe(
    chunkAudioURL: URL,
    preferredLanguageCode: String,
    initialPrompt: String?,
    focusLanguageCodes: [String] = []
) async throws -> WhisperTranscriptionResult {
    let ctx = try await ensureContext()
    let file = try AVAudioFile(forReading: chunkAudioURL,
                               commonFormat: .pcmFormatFloat32, interleaved: false)
    guard file.length > 0 else { throw WhisperGGMLCoreMLError.noAudioSamples }
    let endOffset = Double(file.length) / file.processingFormat.sampleRate
    let samples16k = try Self.loadSamples(from: chunkAudioURL, startOffset: 0, endOffset: endOffset)
    guard !samples16k.isEmpty else { throw WhisperGGMLCoreMLError.noAudioSamples }
    return try transcribeSamples(samples16k, context: ctx,
                                 preferredLanguageCode: preferredLanguageCode,
                                 initialPrompt: initialPrompt,
                                 focusLanguageCodes: focusLanguageCodes)
}
```

---

### 4. `SessionStore` — chunk directory API

```swift
// New methods
func chunksDirectoryURL(for sessionID: UUID) -> URL
func createChunksDirectory(for sessionID: UUID) throws

// On session creation: create chunks/ subdirectory
// Remove: pre-creation of session_full.m4a
```

---

## Data Flow (New)

```
[mic] → AVAudioEngine tap → CapturedAudioFrame
  → LiveSessionPipeline.ingest() → VAD + Speaker
  → PipelineTranscriptEvent { id, samples, sampleRate, ... }   ← samples still here

[AppBackend.consume()]
  → create TranscriptRow with placeholder text
  → await ChunkAudioWriter.write(samples, sampleRate, rowID, chunksDir)
       → returns chunk URL (file fully closed)
  → row.chunkURL = url
  → enqueueChunkForAutomaticTranscription(chunkURL: url)

[QueuedChunkTranscription { rowID, sessionID, chunkURL: URL }]   ← no [Float] in queue
  → transcribeQueuedChunk(chunkURL:)
  → whisperTranscriber.transcribe(chunkAudioURL: url)
  → AVAudioFile read → resampleTo16k → whisper_full()
  → update TranscriptRow.text
```

---

## Changed Code Paths

### `AppBackend.consume()` — transcript event handler

```swift
case .transcript(let transcript, _):
    let adjusted = transcriptWithRecordingOffsetApplied(transcript)
    await sessionStore.appendTranscript(sessionID: sessionID, event: adjusted)

    // Write chunk file, then enqueue for transcription
    if let chunksDir = sessionStore.chunksDirectoryURL(for: sessionID) {
        Task(priority: .background) { [weak self] in
            guard let self else { return }
            do {
                let url = try await chunkWriter.write(
                    samples: adjusted.samples,
                    sampleRate: adjusted.sampleRate,
                    rowID: adjusted.id,
                    chunksDirectory: chunksDir
                )
                await sessionStore.updateTranscriptRowChunkURL(
                    sessionID: sessionID, rowID: adjusted.id, chunkURL: url
                )
                enqueueChunkForAutomaticTranscription(chunkURL: url, rowID: adjusted.id, sessionID: sessionID)
            } catch {
                // Write failed — fall back to in-memory PCM path (keep samples for now)
            }
        }
    }
```

> Note: `PipelineTranscriptEvent.samples` stays until the write succeeds. The `[Float]` is released when the Task completes. Peak memory per in-flight chunk write: ~1MB at 48kHz/5s.

### `QueuedChunkTranscription` struct

```swift
// Before
struct QueuedChunkTranscription {
    let rowID: UUID
    let sessionID: UUID
    let samples: [Float]      // removed
    let sampleRate: Double    // removed
}

// After
struct QueuedChunkTranscription {
    let rowID: UUID
    let sessionID: UUID
    let chunkURL: URL         // added
}
```

### `retranscribeTranscriptRowInternal` — "Transcribe Again"

```swift
// New primary path
if let chunkURL = row.chunkURL {
    result = try await whisperTranscriber.transcribe(
        chunkAudioURL: chunkURL,
        preferredLanguageCode: preferredLanguageCode,
        initialPrompt: initialPrompt,
        focusLanguageCodes: focusLanguageCodes
    )
} else {
    // Legacy fallback: pre-Sprint 8 session — use master M4A with offsets
    guard let audioURL = await sessionStore.audioFileURL(for: sessionID),
          let startOffset = row.startOffset,
          let endOffset = row.endOffset else { return }
    result = try await whisperTranscriber.transcribe(
        audioURL: audioURL,
        startOffset: startOffset,
        endOffset: endOffset,
        ...
    )
}
```

### Playback (`playTranscriptChunkInternal`)

```swift
// Before: AVAudioFile seek into master M4A by offset
// After:
guard let chunkURL = row.chunkURL else {
    // Legacy playback from master M4A (pre-Sprint 8 sessions)
    ...
    return
}
let player = try AVAudioPlayer(contentsOf: chunkURL)
player.play()
```

### Export (full-session audio)

```swift
// New: lazy concatenation on demand
func exportFullSessionAudio(sessionID: UUID) async throws -> URL {
    let chunks = await sessionStore.chunkURLs(for: sessionID)
        .sorted { /* by startOffset */ }
    let composition = AVMutableComposition()
    // AVMutableCompositionTrack insert each chunk M4A in order
    // Export to temp file
}
```

### `startRecording()` — resume offset

```swift
// Before: measure audioDurationSeconds from M4A (fragile — file may still be finalizing)
// After: derive from existing rows
let baseOffset = activeSession.rows
    .compactMap(\.endOffset)
    .max() ?? 0
currentRecordingBaseOffset = baseOffset
```

### `AVAudioSession` activation

Move from `MasterAudioRecorder.activateAudioSessionForRecordingIfSupported()` to `LiveAudioInputController.start()`. Called once before `engine.start()`.

---

## Migration (Existing Sessions)

Existing sessions have:
- `session_full.m4a` — one master file
- `TranscriptRow.startOffset` / `.endOffset` — offsets into master
- `TranscriptRow.chunkURL == nil`

**No migration run needed.** The `chunkURL == nil` fallback in retranscription and playback handles old sessions transparently. Old sessions continue to work as before. New sessions get chunk files.

The old `session_full.m4a` can be cleaned up opportunistically on app update or kept indefinitely — at ~2-4MB per hour of audio, storage cost is negligible.

---

## iCloud Sync

`ICloudSyncService` syncs `Sessions/{uuid}/session.json`. Chunk files are in `Sessions/{uuid}/chunks/` — a subdirectory.

**Check needed:** Does `NSMetadataQuery` in `ICloudSyncService` recurse into subdirectories? If not, the query scope needs to change from `session.json` to `Sessions/**` or chunk files need their own sync handling. This is a Sprint 8 investigation item.

---

## Chunk File Deletion

When a row is dropped (no speech detected), its chunk file must also be deleted:

```swift
// dropTranscriptRowWithoutSpeech — add cleanup
if let chunkURL = row.chunkURL {
    try? FileManager.default.removeItem(at: chunkURL)
}
```

---

## Implementation Order

| Step | What | Who | Effort |
|---|---|---|---|
| 1 | `ChunkAudioWriter` actor | swift-engineer | M |
| 2 | `SessionStore`: `chunksDirectoryURL`, `createChunksDirectory`, `updateTranscriptRowChunkURL` | swift-engineer | S |
| 3 | `TranscriptRow`: add `chunkURL: URL?` | swift-engineer | S |
| 4 | `AppBackend.consume()`: wire `ChunkAudioWriter` write, enqueue by URL | swift-engineer | S |
| 5 | `QueuedChunkTranscription`: replace samples with URL | swift-engineer | S |
| 6 | `WhisperGGMLCoreMLService`: add `transcribe(chunkAudioURL:)` | swift-engineer | S |
| 7 | `transcribeQueuedChunk`: use URL overload | swift-engineer | S |
| 8 | `retranscribeTranscriptRowInternal`: `chunkURL` path + legacy fallback | swift-engineer | S |
| 9 | Playback: `AVAudioPlayer(contentsOf: chunkURL)` | swift-engineer | S |
| 10 | `dropTranscriptRowWithoutSpeech`: delete chunk file | swift-engineer | S |
| 11 | Remove `MasterAudioRecorder` | swift-engineer | S |
| 12 | Move AVAudioSession activation to `LiveAudioInputController` | audio-processing-lead | S |
| 13 | Export: `AVMutableComposition` over chunk files | swift-engineer | M |
| 14 | Remove `schedulePostRecordingQualityPass` | swift-engineer | S |
| 15 | Remove `transcribe(samples:sourceSampleRate:)` Whisper overload | swift-engineer | S |
| 16 | Verify iCloud sync recurses into `chunks/` | swift-engineer | S |

**Total: M-L (2–3 focused days)**

Steps 1–10 are the core migration and should be done atomically in one PR. Steps 11–16 are cleanup and can follow in a second PR.

---

## Team Task Breakdown (sprint8 team, 2026-02-23)

Parallelism boundary: Steps 1, 3, 6 touch independent files and run concurrently. Steps 2, 4–5, 7–16 all touch `AppBackend.swift` and must be sequential.

### Phase 1 — Parallel (no file conflicts)

| Task | Steps | File(s) | Agent |
|---|---|---|---|
| 1A | 1, 3 | `Services/ChunkAudioWriter.swift` (new), `Models/Domain/TranscriptRow.swift` | swift-engineer |
| 1B | 6 | `Libraries/WhisperGGMLCoreMLService.swift` | swift-engineer |
| 1C | 16 | `Services/ICloudSyncService.swift` (investigation only) | swift-engineer |

### Phase 2 — Sequential (AppBackend.swift, after Phase 1)

| Task | Steps | Notes |
|---|---|---|
| 2 | 2, 5, resume-offset fix | SessionStore chunk API + QueuedChunkTranscription struct |
| 3 | 4, 7, 8, 9, 10 | consume() wiring, transcribe, retranscribe, playback, dropRow |

### Phase 3 — Cleanup (after Phase 2 core works)

| Task | Steps | Notes |
|---|---|---|
| 4A | 11, 14, 15 | Remove MasterAudioRecorder, schedulePostRecordingQualityPass, old Whisper overload |
| 4B | 12 | Move AVAudioSession to LiveAudioInputController |
| 4C | 13 | Export via AVMutableComposition |

---

## Open Questions

1. **iCloud sync subdirectory**: Does `NSMetadataQuery` scope cover `chunks/`? Needs investigation (Task 1C).
2. **Chunk write failure handling**: If `ChunkAudioWriter` fails (disk full, permissions), should we fall back to in-memory PCM path or surface an error? Proposed: silent fallback to PCM path with a log, so recording keeps working.
3. **Sub-chunk file count**: Two-pass VAD can produce 8–12 chunks per minute. Long meetings (1h) = ~720 chunk files. Fine for filesystem and iCloud, but confirm no performance issues in `SessionStore.loadSession()` that lists directory contents.

---

*Last updated: 2026-02-23 · Sprint 8 team task breakdown added. Phase 1 ready to dispatch (Tasks 1A, 1B, 1C in parallel). Phases 2–3 sequential after Phase 1.*
