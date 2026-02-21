# Architecture Overview

## Goals
- Offline-first meeting assistant with local-first processing.
- Dynamic configuration from Settings (language focus + main timer display + sync toggle + Whisper Advanced controls).
- Reactive chat UI driven by backend state.
- Persist chats/settings across app relaunch on iOS-family and macOS while defaulting UI to draft mode at startup.
- Native platform-adapted shell: drawer workspace on iOS/iPadOS, split-view workspace on macOS, and tab fallback on visionOS/tvOS.
- User-facing transcript timeline uses "Message" terminology (internal processing still slices audio into chunks).

## High-Level Modules
1. App Shell + State Coordinator (`App/ContentView.swift`)
2. Platform UI Components (`Features/Chat/ChatTabView.swift`, `Features/Library/LibraryTabView.swift`, `Features/Share/SettingsSheetFlowView.swift`, `Features/Share/ExportSheetFlowView.swift`, `Views/Components/IOSWorkspaceSidebarView.swift`, `Views/Mac/MacProWorkspaceView.swift`)
3. Backend Orchestrator (`App/AppBackend.swift`)
4. Preflight Layer (`PreflightService`)
5. Live Pipeline (`LiveSessionPipeline`)
6. Storage Layer (`SessionStore` + filesystem)
7. Settings Persistence (`AppSettingsStore` + `UserDefaults`)
8. Playback + Export layer (implemented/partial)

## Runtime Flow
1. App boots, reloads persisted settings + session snapshots, and opens draft mode (`activeSessionID = nil`).
2. User taps record.
3. Pre-flight checks credit and prepares language prompt.
   - Prompt uses strict verbatim instructions (`Never translate`, `Never summarize`, `Never rewrite`).
4. Live pipeline runs concurrent tracks:
   - waveform/input stream
   - CoreML Silero VAD chunk slicing (pass 1: live coarse detection)
   - CoreML speaker diarization branch (tuned thresholds + turn-taking + adaptive probe)
   - merge branch
5. After each chunk is cut, a second VAD pass (`intraChunkVAD`) finds breath-pause sub-boundaries concurrently with speaker identification; each sub-chunk becomes a separate transcript event (chat bubble).
5. Transcript item is appended to store.
6. Chat list updates reactively.
7. Chunk duration deducts credit.
8. Transcript rows persist chunk `startOffset`/`endOffset`.
9. Optional sync hook runs.
10. Backend queues chunk transcription automatically (one-by-one) and updates bubbles reactively.
11. User can tap a transcript bubble to play that chunk when recording is stopped.

## Current Implementation Note
- Pipeline internals are production-style backend services.
- Audio capture uses real `AVAudioEngine`.
- App shell is platform-aware:
  - iOS uses a custom drawer sidebar (`iosDrawerLayout`) with global right-swipe open/left-swipe close and a chat-header sidebar toggle.
  - iPadOS (`.regular` horizontal size class) uses `NavigationSplitView` split layout (`ipadSplitLayout`).
  - iOS sidebar swipe-open is recognized from anywhere on the detail surface, including transcript bubble regions.
  - iOS/iPadOS sidebar contains fixed top actions (`Search`, `New Chat`), workspace rows (`Layca Chat`, `Settings`), and a scrollable `Recent Chats` list.
  - visionOS/tvOS currently use `TabView`/`TabSection` fallback with a `New Chat` action tab.
  - iOS-family uses plain `systemBackground` for chat/settings surfaces with native material cards and automatic device light/dark appearance.
  - macOS uses `NavigationSplitView` with sidebar workspace sections and dedicated detail views.
  - macOS sidebar workspace sections are `Layca Chat` and `Settings`, with `Recent Chats` below.
  - Selecting `Settings` presents one modal settings sheet with an internal multi-step navigation stack (no nested settings sheets).
  - macOS Chat detail toolbar uses inline title rename plus a trailing native control group (`Play` + `More`).
- VAD uses native CoreML Silero (`silero-vad-unified-256ms-v6.0.0.mlmodelc`) with bundled offline model.
  - **Two-pass sub-chunking:** a dedicated `intraChunkVAD` (second `SileroVADCoreMLService` instance) re-runs VAD at 32 ms hops on completed chunks, splits at breath-pause boundaries (silence ≥ 0.15s, prob < 0.20), minimum sub-chunk 0.5s; runs concurrently with `identifySpeaker` via `async let`. Thresholds tuned for Thai/rapid turn-taking (inter-speaker pauses typically 100–150 ms).
- Speaker branch uses native CoreML WeSpeaker (`wespeaker_v2.mlmodelc`) with bundled offline model.
  - Thresholds tuned Sprint 1–2: main `0.65`, loose `0.52`, new-candidate `0.58`, immediate `0.40`.
  - Turn-taking detection at `0.45` after 500ms silence; adaptive probe window 0.8s for established speakers.
  - `checkForInterrupt` with consecutive-window tracking and 80ms timeout guard.
  - Sample-rate mismatch: confirmed resolved — source `sampleRate` passed explicitly to interrupt inference.
  - `lastKnownSpeakerEmbedding` fallback properly seeded before each speaker-boundary cut via `extractWindowEmbedding(audioBuffer:sampleRate:)` (relaxed 1,200-sample minimum for 44.1/48 kHz); preserved across silence/max-duration cuts. Eliminates the ~1.6s interrupt-detection blind window at every chunk start.
  - `interruptCheckSampleAccumulator` cleared on boundary cut to prevent mixed-audio contamination.
- Speaker fallback now uses a multi-feature signature (amplitude + zero-crossing-rate + RMS energy) with tunable threshold when CoreML speaker model is unavailable.
- Runtime model asset sources are organized under `Models/RuntimeAssets/`.
- Whisper transcription runs automatically through a serial queue (`whisper.cpp`) as chunks are produced.
- Automatic transcription runs with Whisper auto language detection (`preferredLanguageCode = "auto"`) and `translate = false`.
- Whisper prompt template is built from Language Focus + context keywords.
- If output appears to echo the prompt text, the backend reruns inference without prompt.
- If transcription quality is weak/unusable (e.g., `-`, `foreign`, empty-like output), backend queues retry and/or removes placeholder rows with no usable speech text.
- Whisper runtime preferences are applied from app settings and background-prewarmed after apply.
- Whisper acceleration toggles are available at environment level:
  - `LAYCA_ENABLE_WHISPER_COREML_ENCODER`
  - `LAYCA_ENABLE_WHISPER_GGML_GPU_DECODE`
- Settings `Advanced` controls:
  - `Acceleration` sub-step:
    - `Whisper ggml GPU Decode` toggle
    - `Whisper CoreML Encoder` toggle
  - `Offline Model Switch` sub-step (`Fast`, `Normal`, `Pro`)
- Settings `General` controls include:
  - `Time Display` as a dedicated sub-step (`Friendly` / `Hybrid` / `Professional`) for main timer only
- Export format sub-steps use a shortened preview window (11 lines + trailing ellipsis when truncated) on both iOS-family and macOS.
- Export sheet styles currently include:
  - `Notepad Minutes` (header + spacer line + timestamp/speaker/language blocks)
  - `Plain Text` (raw transcript text only)
  - `Markdown`
  - `Video Subtitles (.srt)` (SubRip cue output)
- Export `Share` action writes and shares a temporary file URL with a style-matched extension (`.txt`, `.md`, `.srt`), while `Copy` always copies text payload.
- macOS export format sub-step renders `Share` + `Copy` in a single actions row.
- On physical iOS devices, CoreML encoder now uses an auto profile: enabled on high-memory/high-core devices for maximum performance, safety-disabled on lower-tier devices to avoid startup stalls.
- Set `LAYCA_FORCE_WHISPER_COREML_ENCODER_IOS=ON` to force-enable on any iPhone.
- On some iPhones, first CoreML encoder run may log ANE/CoreML plan-build warnings before succeeding.
- If ggml GPU decode init fails, runtime falls back to CPU decode and logs reason.
- Chunk slicing defaults keep silence boundaries (`silence cutoff 1.2s`, `minimum chunk 3.2s`, `max chunk 6s`) and add near-real-time speaker-change boundary cuts with `1.0s` backtrack plus stability guard.
- Post-chunk two-pass VAD splits completed chunks into sub-chunks at breath-pause boundaries (prob < 0.20, pause ≥ 0.15s, min sub-chunk 0.5s); each sub-chunk gets its own `TranscriptRow` and chat bubble.
- Whisper decoding is adaptive: chunks ≤ 6s use single-segment/no-timestamp fast path; chunks > 6s use timestamp-conditioned multi-segment decoding to prevent greedy attention drift on long multi-speaker audio.
- Chat UI: consecutive same-speaker sub-chunk bubbles use "continuation" styling — 8pt color dot avatar, hidden speaker-name/timestamp header, 2pt top padding — to reduce visual noise while preserving speaker identity via color accent and VoiceOver labels.
- `@Published var liveSpeakerID: String?` on `AppBackend` tracks the active speaker during recording; `RecordingSpectrumBubble` reflects the current speaker's color.
- Chunk playback is gated off while recording to avoid audio-session conflicts.
- `startNewChat()` is draft-reset behavior (does not create a persisted session until recording starts).
- First recording from draft creates a new persisted session title (`chat N`).
- iOS chat header keeps sidebar toggle before chat title and uses a trailing native control group (`Play` + `More`).
- On compact iOS toolbar widths, this group collapses into a single ellipsis overflow control while preserving the same actions.
- iOS non-edit chat-title pill width is content-aware (auto-size by title length within safe min/max bounds) and uses tail truncation only for long titles.
- Inline chat-title editing on iOS/macOS hides other header actions and cancels on outside interaction (tap-away/focus loss/sidebar tap).
- During active recording, transcript updates do not auto-follow by default; `New message` appears until user opts into follow mode by tapping it.
- Follow mode stays active until user scrolls away from bottom, then returns to button-first behavior for later messages.
- Main timer format is settings-driven (`Friendly`, `Hybrid`, `Professional`).
- Friendly mode trims zero units (`11 sec`, `5 min 22 sec`, `1 hr 5 sec`).
- Draft idle state shows starter text instead of timer (`Tap to start record` on iOS/iPadOS, `Click to start record` on macOS).
- Saved sessions show accumulated duration while idle and resume from prior offset when recording again.
- During transcript chunk playback (player mode), recorder controls switch to playback state:
  - action button changes to `Stop`
  - recorder tint switches green
  - main timer shows playback time remaining (countdown)
  - subtitle shows segment range (`mm:ss → mm:ss`)
- During recording, recorder tint remains red.
- "Transcribe Again" is a submenu (`Transcribe Auto`, plus `Transcribe in <Focus Language>` entries for selected focus languages).
- Manual retranscribe execution is currently gated during active recording and runs after recording stops.
- Forced `TH` / `EN` manual retries validate script output; backend retries once without prompt on mismatch, then keeps existing text when mismatch persists.
- Manual low-confidence retries keep existing text silently (no red warning banner).
- `SessionStore` persists both `session.json` (session metadata) and `segments.json` (row snapshots) and reloads from disk at startup.
- `AppSettingsStore` persists user setting values (including `mainTimerDisplayStyleRawValue`) and compatibility metadata (`activeSessionID`, `chatCounter`) through relaunch; startup still forces draft mode.
- Session rows support `Rename`, `Share this chat`, `Delete` via context menu (Library where present, and macOS `Recent Chats` sidebar).
- macOS sidebar `Recent Chats` rows support the same context menu action group.
- macOS detail pane keeps a minimum width guard to preserve chat readability when resizing.
- macOS recording permission uses `AVAudioApplication.requestRecordPermission`.
- macOS target is sandboxed and requires audio-input entitlement to appear in Privacy > Microphone settings.

## Folder Layout (Current)
```text
xcode/layca/
├── App/
│   ├── laycaApp.swift
│   ├── ContentView.swift
│   └── AppBackend.swift
├── Features/
│   ├── Chat/ChatTabView.swift
│   ├── Library/LibraryTabView.swift
│   └── Share/
│       ├── ExportSheetFlowView.swift
│       └── SettingsSheetFlowView.swift
├── Models/
│   ├── Domain/
│   │   ├── FocusLanguage.swift
│   │   ├── ChatSession.swift
│   │   └── TranscriptRow.swift
│   └── RuntimeAssets/
│       ├── ggml-large-v3-turbo-q5_0.bin
│       ├── ggml-large-v3-turbo-q8_0.bin
│       ├── ggml-large-v3-turbo.bin
│       ├── ggml-large-v3-turbo-encoder.mlmodelc/
│       ├── silero-vad-unified-256ms-v6.0.0.mlmodelc/
│       └── wespeaker_v2.mlmodelc/
├── Views/
│   ├── Components/
│   │   ├── IOSWorkspaceSidebarView.swift
│   │   └── TranscriptBubbleOptionButton.swift
│   ├── Mac/
│   │   └── MacProWorkspaceView.swift
│   └── Shared/
│       ├── LiquidBackdrop.swift
│       └── View+PlatformCompatibility.swift
├── Libraries/
│   ├── SileroVADCoreMLService.swift
│   ├── SpeakerDiarizationCoreMLService.swift
│   └── WhisperGGMLCoreMLService.swift
├── Frameworks/
│   └── whisper.xcframework/
└── Assets.xcassets/
```

## Non-Functional Constraints
- Keep memory bounded during live stream/chunk processing.
- Keep per-session speaker identity stable (color/avatar consistency).
- Keep recording controls gated by credit status.
