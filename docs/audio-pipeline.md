# Audio Pipeline

## Capture
- Use `AVAudioRecorder` to persist session recording as `.m4a`.
- Enable background audio mode for long meetings.

## Processing Pipeline
1. Read captured audio stream.
2. Decode and convert to PCM 16kHz 16-bit mono.
3. Buffer by fixed window (e.g., 30s) or VAD boundaries.
4. Send chunk to Whisper engine.
5. Persist transcript segments with relative offsets.

## Timestamp Mapping
- Whisper returns chunk-relative `start`/`end` timestamps.
- Convert to session-global offsets by adding chunk start offset.
- Example:
  - chunk starts at 120.0s
  - segment is 2.4s -> 4.1s
  - stored segment offset is 122.4s -> 124.1s

## Playback Sync
- On transcript tap:
  - set `player.currentTime = audioStartOffset`
  - start playback
- Optional: auto-stop at `audioEndOffset` for per-segment playback.

## Export
- Full session audio export: share `full_recording.m4a`.
- Transcript export: markdown/pdf/text with optional timestamps.
