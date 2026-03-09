# Whisper Model Picker — Design Document
_2026-03-09_

## Problem

All three Whisper model variants (Q5/Fast, Q8/Balanced, FP32-Turbo/Pro) are currently bundled inside the app binary, adding ~2.9 GB to the download size. The existing model-switch UI is a small segmented picker buried in Settings with no download management.

New users who have never opened the app have no model downloaded when they tap Record, and the app has no graceful handling for this case.

## Goals

1. Remove all three Whisper GGML binaries from the app bundle — drastically reduce app store size.
2. Add a rich per-model download sheet (iOS and macOS) that replaces the existing segmented picker.
3. Gate recording: if no model is downloaded when the user taps Record, show the model picker sheet automatically.
4. After download the user taps Record again to begin recording.

## Out of Scope

- Removing CoreML encoder, VAD, or speaker models from the bundle (they are small).
- Background download (URLSession background transfers) — foreground download is sufficient for MVP.
- Qwen summary model — separate system, not touched.

## Model Definitions

| Profile | Display Name | Variant | File | Size | HuggingFace URL |
|---|---|---|---|---|---|
| `.quick` | Whisper Fast | Q5 | `ggml-large-v3-turbo-q5_0.bin` | 547 MB | `ggerganov/whisper.cpp` repo |
| `.normal` | Whisper Balanced | Q8 | `ggml-large-v3-turbo-q8_0.bin` | 834 MB | `ggerganov/whisper.cpp` repo |
| `.pro` | Whisper Pro | FP32 Turbo | `ggml-large-v3-turbo.bin` | 1.5 GB | Already in code |

All files download to `~/Library/Caches/WhisperGGML/` (existing cache dir).

## Architecture

### WhisperModelDownloadManager (new actor)

Single source of truth for download state. Owned by AppBackend.

```
State per profile:
  .notDownloaded   — file not in cache
  .downloading(progress: Double)
  .downloaded      — file present and passes size check
  .active          — downloaded AND currently loaded in WhisperGGMLCoreMLService

Actions:
  download(profile:)   — starts URLSession data task, reports progress
  cancel(profile:)     — cancels in-flight task
  activate(profile:)   — sets AppBackend.whisperModelProfile, calls setRuntimePreferences
  deleteAll()          — for testing
```

Exposed to SwiftUI via `@Published` state on AppBackend (or as an `ObservableObject`).

### WhisperModelPickerView (new SwiftUI view)

`Features/Models/WhisperModelPickerView.swift`

Replaces `SettingsOfflineModelSwitchStepView` entirely (delete the old view).

#### Contexts

| Context | Trigger | Title | Dismiss | Post-download |
|---|---|---|---|---|
| `.gate` | Record tapped, no model downloaded | "Choose a Model" | `interactiveDismissDisabled(true)`, no close button | Sheet dismisses, user taps Record again |
| `.settings` | Settings → Offline Models | "Whisper Models" | `xmark` close button | Stay on sheet, show Active state |

If download fails in gate context, show an inline error on the card + a "Later" button in the banner so the user can dismiss without being trapped.

### Visual Design

**Model card anatomy (per card):**
- 44×44 rounded icon (tinted bg + SF Symbol): blue=Fast, accent=Balanced, purple=Pro
- Name + file size (one line), description (2–3 lines), badge pills
- Fixed 80pt trailing action slot:
  - Not downloaded → `Download` filled accent capsule button
  - Downloading → progress ring (36pt, 3pt stroke) with % label + stop icon to cancel
  - Downloaded, not active → `Use` outlined capsule button
  - Active → green `✓ Active` (no tap)
- State transitions: `.transition(.opacity.combined(with: .scale(0.85)))` + spring animation

**Badges:**

| Badge | Color |
|---|---|
| 96 Languages | blue |
| CoreML | purple |
| GPU | orange |
| Fast | green (Q5 only) |
| Best Quality | amber (Pro only) |

**Gate banner (gate context only):**
Orange mic icon + "A model is required to start recording / Download one now — it stays on your device."
- `.interactiveDismissDisabled(true)`
- "Later" button only appears if a download fails

**Platform differences:**
- iOS: `.sheet`, `.presentationDetents([.large])`, `.presentationDragIndicator(.visible)`
- macOS: `frame(minWidth: 560, minHeight: 520)`, native button styles (`.borderedProminent` / `.bordered`), no gate context

### Changes to Existing Files

| File | Change |
|---|---|
| `WhisperGGMLCoreMLService.swift` | Add download URLs to Q5 and Q8 `ModelAssetSpec`; expose download progress callback |
| `AppBackend.swift` | Own `WhisperModelDownloadManager`; gate check in `toggleRecording`; publish sheet-show trigger |
| `SettingsSheetFlowView.swift` | Replace `SettingsOfflineModelSwitchStepView` destination with `WhisperModelPickerView(.settings)` |
| `ContentView.swift` / record button site | Add `.sheet(isPresented: $showModelPicker)` for gate context |
| Xcode project | Remove Q5 and Q8 `.bin` files from Copy Bundle Resources |

## Success Criteria

- App bundle no longer contains any Whisper `.bin` files
- First run: tapping Record shows the picker sheet; after downloading any model, user can dismiss and record
- Settings path shows the same sheet with working switch + Active indicator
- Download can be cancelled mid-flight; progress ring updates smoothly
- Works on iOS 17+ and macOS 14+
