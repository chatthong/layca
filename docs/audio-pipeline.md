# Audio Pipeline

## Capture
- Recorder is represented by a live stream track in backend.
- Waveform values are emitted every ~`0.05s` for UI visualizer updates.
- Session audio file path is reserved as `Documents/Sessions/{UUID}/session_full.m4a`.
- Recording start is gated by runtime microphone permission.
- On macOS, app signing must include sandbox audio-input entitlement for TCC registration.
- On macOS, toolbar styling/navigation (native SwiftUI toolbar composition) is UI-only and does not change capture/transcription behavior.

## Live Processing Pipeline

### Track 1: Input + Visualizer
- Produce amplitude ticks for UI waveform bars.
- Keep master session recording path alive.

### Track 2: Slicer (VAD — two passes)
- Buffer frames while speech is active.
- **Pass 1 (live, coarse):** CoreML Silero VAD probability output; fallback to amplitude threshold when VAD unavailable.
- End chunk when silence reaches threshold (`1.2s` by default).
- Message-chunk guardrails:
  - minimum chunk duration: `3.2s`
  - maximum chunk duration: `12s`
  - near-real-time speaker-change boundary cut applied while speech is active
  - boundary cut uses `1.0s` backtrack from detected speaker-change point
  - stability guard requires enough speech context before boundary split
- **Pass 2 (post-chunk, fine — two-pass VAD sub-chunking):** after each chunk is cut, a dedicated second `SileroVADCoreMLService` instance (`intraChunkVAD`) re-runs VAD on the chunk's raw samples at 32 ms hops.
  - Finds silence regions where probability < `0.30` spanning ≥ `0.3s` (breath pause boundaries).
  - Splits chunk at silence midpoints into sub-chunks; minimum sub-chunk size `0.8s`.
  - Each sub-chunk becomes its own `PipelineTranscriptEvent` → its own chat bubble.
  - `intraChunkVAD` LSTM state is reset before each pass; runs concurrently with speaker identification.
  - Falls back to single full-chunk event if no valid split points found.

### Track 3: Dual AI Branch
- Branch A: speaker embedding extraction from CoreML WeSpeaker (`wespeaker_v2.mlmodelc`) and cosine-similarity matching for session speaker labels.
  - Cosine similarity thresholds (tuned Sprint 1–2): main `0.65`, loose `0.52`, new-candidate `0.58`, immediate-switch `0.40`.
  - Minimum 2.5s segment guard before assigning new speaker.
  - Adaptive probe window: `0.8s` for speakers seen ≥ 5 times (tighter for known voices).
  - Turn-taking detection: lower threshold `0.45` applied when silence gap ≥ `500ms` precedes chunk.
  - Weighted EMA for pending embedding accumulation.
  - `checkForSpeakerInterrupt` receives correct source sample rate (fixed Sprint 1 sample-rate mismatch bug).
  - Eliminated 1.6s blind window at chunk start via `lastKnownSpeakerEmbedding` fallback.
  - 80ms `withTaskGroup` timeout on interrupt inference to keep pipeline responsive.
- Branch B: deferred transcription marker (placeholder text persisted per message until queue worker transcribes it).
- Speaker branch fallback: amplitude + zero-crossing-rate + RMS signature matching when speaker CoreML model is unavailable.

### Track 4: Merger
- Merge branch A + branch B output into one transcript event.
- Persist speaker label, language tag, text, and start/end offsets.

## Timestamp Mapping
- Pipeline tracks elapsed session seconds.
- Chunk-relative timings are converted into session-global offsets.
- Transcript row timestamp is stored as formatted `HH:mm:ss`.
- Recorder timer display behavior:
  - main timer formatting is user-selectable (`Friendly`, `Hybrid`, `Professional`)
  - `Friendly` trims zero units (for example, `11 sec` instead of `0 min 11 sec`)
  - draft mode (`activeSessionID == nil`) shows starter text in UI (`Tap to start record` / `Click to start record`) until first recording starts
  - saved sessions show accumulated prior duration while idle
  - resumed recording continues from prior persisted duration offset
  - during transcript chunk playback, main timer shows remaining playback time (countdown)

## Persistence + UI
1. Append event to session store.
2. Write `segments.json` snapshot.
3. Keep message `startOffset`/`endOffset` for transcript-row playback.
4. Deduct usage credit from message duration.
5. Push reactive update to Chat bubble list.

## Message Playback Path
- Chat bubble taps call backend message playback.
- Playback seeks into `session_full.m4a` at row `startOffset`, then auto-stops at `endOffset`.
- Playback mode (when a chunk is playing) updates recorder UI on iOS/iPadOS and macOS:
  - action control changes from `Record` to `Stop`
  - recorder tint switches green (recording mode still uses red)
  - subtitle switches from session date to segment range (`mm:ss → mm:ss`)
- Pressing the recorder action while playback is active stops playback (does not start recording).
- Message transcription runs automatically from backend queue (`whisper.cpp`) and updates row text in storage/UI.
- Whisper decode is configured for original-language transcript output:
  - `preferredLanguageCode = "auto"` (language auto-detect)
  - `translate = false` (never translate)
  - `initial_prompt` comes from strict verbatim preflight template + context keywords
- Whisper runtime preferences are applied from Settings `Advanced` (`Acceleration` + `Offline Model Switch`) and prewarmed in background to reduce first-use latency.
- Runtime acceleration env flags (service-level fallback):
  - `LAYCA_ENABLE_WHISPER_COREML_ENCODER`
  - `LAYCA_ENABLE_WHISPER_GGML_GPU_DECODE`
- iOS auto profile:
  - CoreML encoder is auto-enabled on higher-tier iPhones for maximum speed
  - lower-tier iPhones auto-fallback to encoder OFF for startup reliability
  - set `LAYCA_FORCE_WHISPER_COREML_ENCODER_IOS=ON` to force-enable
- `Offline Model Switch` model profiles:
  - `Fast` -> `ggml-large-v3-turbo-q5_0.bin`
  - `Normal` -> `ggml-large-v3-turbo-q8_0.bin`
  - `Pro` -> `ggml-large-v3-turbo.bin`
- Runtime prints acceleration status (`Model: Fast/Normal/Pro, CoreML encoder: ON/OFF, ggml GPU decode: ON/OFF`) and falls back to CPU decode if ggml GPU context init fails.
- On some iPhones, first CoreML encoder run may emit ANE plan-build warnings and take longer before succeeding.
- If output is empty or appears to echo prompt instructions, backend applies fallback reruns (without prompt and detected-language retry).
- Transcription quality guardrails classify outputs and handle unusable values (`-`, `foreign`, empty-like text) by retrying or deleting placeholder rows with no usable speech.
- Playback is disabled while recording is active.
- Manual `Transcribe Again` uses submenu options:
  - `Transcribe Auto` (auto language detect)
  - `Transcribe in <Focus Language>` (only user-selected focus languages are shown)
- Forced `TH` / `EN` manual retries validate output script and retry once without prompt if script mismatches.
- If forced-language retry still mismatches script, backend keeps existing row text and does not show a low-confidence error banner.
- Manual `Transcribe Again` remains blocked during active recording and shows `Stop recording before running Transcribe Again.`.
- If offsets are missing or invalid, bubble remains non-playable.

## Real-Time Speaker Feed
- `@Published var liveSpeakerID: String?` on `AppBackend` tracks the speaker active during the current chunk.
- `PipelineEvent.liveSpeaker(String?)` emitted by `applyTrailingSpeakerObservation` and `resetActiveChunkSpeakerTracking`.
- `RecordingSpectrumBubble` and the live segment area reflect the current speaker's avatar color in real time.

## Current vs Planned
- **Current:** real `AVAudioEngine` input + native CoreML Silero VAD (two-pass: live coarse + per-chunk fine sub-chunking) + native CoreML speaker diarization (tuned thresholds, turn-taking, adaptive probe) + reactive message pipeline + message playback + automatic queued Whisper transcription with auto language detection, no translation, and quality guardrails.
- **Planned:** add per-bubble processing/progress state and retry controls for debug workflows; add configurable VAD/speaker sensitivity tuning in settings.
