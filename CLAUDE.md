# Layca — Project Memory for Claude

## What This App Is
Layca (เลขา, "secretary" in Thai) is a **native Apple meeting recorder** for iOS, iPadOS, macOS, visionOS, and tvOS. Core value: **offline-first, privacy-first, polyglot transcription** using on-device CoreML models (Whisper large-v3-turbo, Silero VAD, WeSpeaker diarization). No cloud. No subscription. Chat-style transcript UI with speaker bubbles.

**Current version:** 0.5.3
**Current status:** Working app, pre-launch, pre-monetization

## Key Files
| File | Role |
|---|---|
| `xcode/layca/App/AppBackend.swift` | Main state coordinator (@MainActor ObservableObject) |
| `xcode/layca/App/ContentView.swift` | Root layout switcher (iOS drawer / macOS split / visionOS tab) |
| `xcode/layca/Features/Chat/ChatTabView.swift` | iOS/macOS chat workspace + transcript bubbles |
| `xcode/layca/Views/Mac/MacProWorkspaceView.swift` | macOS-specific workspace views |
| `xcode/layca/Models/Domain/TranscriptRow.swift` | Transcript data model (⚠️ contains SwiftUI.Color) |
| `xcode/layca/Libraries/WhisperGGMLCoreMLService.swift` | Whisper.cpp bridge |
| `xcode/layca/Libraries/SileroVADCoreMLService.swift` | Voice activity detection |
| `xcode/layca/Libraries/SpeakerDiarizationCoreMLService.swift` | Speaker embedding + matching |

## Architecture
- `AppBackend` → `LiveSessionPipeline` (actor) → VAD → Speaker → Whisper queue
- Persistence: filesystem JSON + M4A under `Documents/Sessions/{UUID}/`
- Settings: `UserDefaults` via `AppSettingsStore`
- Platform shells: iOS=drawer, macOS=NavigationSplitView, visionOS/tvOS=TabView

## Known Critical Issues (Fix Before Adding Features)
1. `ForEach(0..<sessions.count, id: \.self)` in `MacProWorkspaceView.swift:154` — **crash risk**
2. `TranscriptRow.palettes: [Color]` static array — SwiftUI.Color not Codable — **blocks SwiftData** (avatarPalette refactored to avatarPaletteIndex: Int but the static palettes array still uses Color)
3. `MasterAudioRecorder.stop()` does file I/O on `@MainActor` — **UI stutter risk**
4. `checkForSpeakerInterrupt` called without `sampleRate` (defaults 16kHz, engine runs 44.1kHz) — wrong decimation ratio, degraded interrupt embeddings — `AppBackend.swift:777`
5. `activeChunkSpeakerID == nil` guard blocks interrupt detection for first 1.6s of every chunk — `AppBackend.swift:758`

## Agents Available
Custom agents are in `.claude/agents/`:
- `apple-design-lead` — HIG audits, design decisions
- `swift-engineer` — architecture, code quality, bugs
- `product-strategist` — features, monetization, roadmap
- `accessibility-lead` — VoiceOver, Dynamic Type, inclusive design
- `market-analyst` — competitive research, pricing, launch
- `ml-inference-lead` — CoreML, Metal GPU, ANE routing, Whisper/VAD/diarization model optimization, on-device inference latency
- `audio-processing-lead` — AVAudioEngine, AVAudioSession, signal processing, VAD tuning, buffer alignment, audio quality

## Task List
All pending work is tracked in **[TODO.md](TODO.md)**.
Always check TODO.md before starting new work. Update checkboxes as tasks complete.

## Docs
- `docs/architecture.md` — system architecture
- `docs/roadmap.md` — completed + next items
- `docs/audio-pipeline.md` — VAD/speaker/Whisper pipeline detail
- `docs/team-explorer-report.md` — full multi-perspective analysis (source of TODO.md)
