# Audio Pipeline

## Capture
- Recorder is represented by a live stream track in backend.
- Waveform values are emitted every ~`0.05s` for UI visualizer updates.
- Session audio file path is reserved as `Documents/Sessions/{UUID}/session_full.m4a`.

## Live Processing Pipeline

### Track 1: Input + Visualizer
- Produce amplitude ticks for UI waveform bars.
- Keep master session recording path alive.

### Track 2: Slicer (VAD-like)
- Buffer frames while speech is active.
- Primary detector: CoreML Silero VAD probability output.
- Fallback detector: amplitude threshold when VAD is unavailable.
- End chunk when silence reaches threshold (`1.2s` by default).
- Chunk guardrails:
  - minimum chunk duration: `3.2s`
  - maximum chunk duration: `12s`

### Track 3: Dual AI Branch
- Branch A: transcription + language code.
- Branch B: speaker embedding extraction from CoreML WeSpeaker (`wespeaker_v2.mlmodelc`) and cosine-similarity matching for session speaker labels.
- Speaker branch fallback: lightweight amplitude/ZCR heuristic if speaker CoreML model is unavailable.

### Track 4: Merger
- Merge branch A + branch B output into one transcript event.
- Persist speaker label, language tag, text, and start/end offsets.

## Timestamp Mapping
- Pipeline tracks elapsed session seconds.
- Chunk-relative timings are converted into session-global offsets.
- Transcript row timestamp is stored as formatted `HH:mm:ss`.

## Persistence + UI
1. Append event to session store.
2. Write `segments.json` snapshot.
3. Keep chunk `startOffset`/`endOffset` for transcript-row playback.
4. Deduct usage credit from chunk duration.
5. Push reactive update to Chat bubble list.

## Chunk Playback Path
- Chat bubble taps call backend chunk playback.
- Playback seeks into `session_full.m4a` at row `startOffset`, then auto-stops at `endOffset`.
- Playback is disabled while recording is active.
- If offsets are missing or invalid, bubble remains non-playable.

## Current vs Planned
- **Current:** real `AVAudioEngine` input + native CoreML Silero VAD + native CoreML speaker diarization + reactive chunk pipeline + chunk-level playback.
- **Planned:** replace placeholder transcript text with real whisper inference without changing external contracts.
