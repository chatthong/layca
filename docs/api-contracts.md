# API Contracts (Internal)

## RecorderService

### startSession() -> Session
Creates a new session, prepares filesystem paths, and begins recording.

### stopSession(sessionID: UUID) -> Void
Stops recording and marks session as ready for processing.

## TranscriptionService

### transcribeChunk(sessionID: UUID, pcmData: Data, chunkStartOffset: Double) -> [TranscriptSegment]
Runs local inference and returns normalized segments with absolute offsets.

### finalizeSession(sessionID: UUID) -> Void
Flushes pending buffers and marks processing completion.

## PlaybackService

### playSegment(sessionID: UUID, segmentID: UUID) -> Void
Loads session audio and seeks to segment start offset.

### stop() -> Void
Stops active playback.

## ExportService

### exportTranscript(sessionID: UUID, format: ExportFormat) -> URL
Generates local export file and returns shareable URL.

### exportAudio(sessionID: UUID) -> URL
Returns URL for master audio recording.
