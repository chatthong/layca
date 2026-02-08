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
- End chunk when silence reaches threshold (`~0.5s`).

### Track 3: Dual AI Branch
- Branch A: transcription + language code.
- Branch B: speaker identification/matching for session speaker labels.

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
3. Deduct usage credit from chunk duration.
4. Push reactive update to Chat bubble list.

## Current vs Planned
- **Current:** simulated backend pipeline to stabilize architecture and UI contracts.
- **Planned:** swap internals with real `AVAudioEngine` + VAD + whisper inference without changing external contracts.
