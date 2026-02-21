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
All previously tracked critical issues are resolved as of 2026-02-22:
- ✅ `ForEach(0..<sessions.count, id: \.self)` crash risk — fixed 2026-02-21
- ✅ `TranscriptRow.palettes: [Color]` not Codable — fixed 2026-02-21 (avatarPaletteIndex: Int)
- ✅ `MasterAudioRecorder.stop()` file I/O on `@MainActor` — fixed 2026-02-21
- ✅ `checkForSpeakerInterrupt` wrong sampleRate — confirmed resolved (frame.sampleRate passed explicitly)
- ✅ `lastKnownSpeakerEmbedding` fallback dead code (1.6s blind window) — fixed 2026-02-22 (Sprint 5)

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
