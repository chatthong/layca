# Layca (เลขา) - Master App Plan 📝

> **The Ultimate Offline Polyglot Meeting Secretary**

**Project Codename:** `Layca-Core`  
**Version:** 0.2.0 (Refined Architecture)  
**Platforms:** iOS, iPadOS, tvOS, visionOS  
**Core Philosophy:** 100% Offline (after setup), Privacy First, "Simple Stack"

---

## 1. Executive Summary 🚀

**Layca** (pun on Thai word "Le-kha/เลขา") is a native Apple ecosystem app designed to record, transcribe, and organize multi-language meetings.

**Key Differentiators:**

1. **Tiny App Store Footprint:** The app installs quickly (<50MB). The heavy AI Brain (1.8GB) is downloaded by the user only when they are ready.
2. **Chat-First Simplicity:** A single **"Group Chat"** style experience with native grouped tab navigation.
3. **Audio Sync:** Tap any sentence to hear exactly what was said at that moment.

---

## 2. Tech Stack (The "Easy Dev" Stack) 🛠️

### A. Core Engine & Model Strategy

- **Inference:** `whisper.cpp` (Swift Package).
- **Model Management (On-Demand):**
  - **Target Model:** `ggml-large-v3-turbo-q8_0.bin` (~1.8 GB).
  - **Logic:** The app ships *without* the model. On first launch, the `ModelManager` downloads the `.bin` and `.mlmodelc` files from a remote source (e.g., Hugging Face or S3) to the user's `Library/Application Support` directory.
  - **Fallback:** Users can choose smaller models (Base/Small) if they have low storage.

### B. Audio Stack (The Native Apple Way) 🍏

- **Recorder:** `AVAudioRecorder`.
  - **Format:** High-Efficiency AAC (`.m4a`) or ALAC for storage (saves space).
  - **Processing:** Decode audio to PCM 16kHz 16-bit Mono on-the-fly for Whisper consumption.
- **Playback:** `AVAudioPlayer` / `AVPlayer` with seeking capabilities.

### C. Data Layer

- **Persistence:** `SwiftData` (iOS 17+).
- **Storage Structure:**

```text
Documents/
├── Models/                 <-- Downloaded AI Brains live here
│   ├── ggml-large-v3-turbo-q8_0.bin
│   └── coreml-encoder/
├── Sessions/
│   ├── {UUID}/
│   │   ├── full_recording.m4a  <-- The Master Audio
│   │   └── segments.json       <-- Metadata (timestamps)
```

---

## 3. UI/UX Strategy: Chat-First 💬

### Mode A: "Group Chat" Style (The Default) 💬

- **Visual:** Bubbles aligned for speakers (simple transcript timeline).
- **Interaction:**
  - **Tap-to-Play:** Tapping a bubble plays the specific audio slice for that sentence.
  - **New Chat:** Start a fresh chat/session from the tab bar action tab.
  - **Export Icon (Top Right):** Quick export action beside the active chat badge.
  - **Setting / Library:** Access model management and session switching from the tab bar.
- **Use Case:** Reviewing who said what, resolving arguments, checking translations.

### Navigation: Native Grouped Tab Bar

- **Group 1:** `Chat`, `Setting`, `Library`
- **Group 2:** `New Chat` (special role tab in a separate right-side group)
- **Header Action:** `Export` icon at top-right of Chat screen (next to active chat badge)
- **Note:** On some device sizes, iOS may render the special-role tab as icon-focused even when a title is provided.

### Tab Component Split

- `ContentView`: app-level state coordinator and tab routing.
- `ChatTabView`: chat timeline, recording card, transcript list, export trigger.
- `SettingTabView`: hours credit, language focus, model selection/download, iCloud and restore purchase card.
- `LibraryTabView`: session list and active-chat switching.

### Library (Session Switch)

- `Library` shows saved chat sessions.
- Tapping a session loads it directly into `Chat`.
- `New Chat` creates a fresh session and returns focus to `Chat`.

### Setting Highlights

- **Language Focus:** multi-select list with search and compact scroll area.
- **Model Change:** single active model with download status/loading indicator.
- **Hours Credit:** top card shows hour balance/usage.
- **iCloud & Purchases:** sync toggle and restore purchases action.

### Export-Only Notepad Style 📝

- Notepad formatting is available **only during export** (Markdown/PDF/Text templates).
- The in-app experience remains chat-only to keep navigation simple.

---

## 4. Architecture & Workflow 🌭

### Phase 1: Native Recording (The Input)

1. **User taps Record:**
   - `AVAudioRecorder` starts saving to `Documents/Sessions/{UUID}/full_recording.m4a`.
   - **Constraint:** Use iOS Background Modes (Audio) to ensure recording continues even if the screen is locked.

### Phase 2: The "Sausage Slicer" (Processing)

*Since we need to match audio to chat, we cannot just feed the stream blindly.*

1. **Buffer Handling:**
   - Monitor the `AVAudioRecorder` input tap.
   - Buffer audio data (PCM) in memory (e.g., every 30 seconds or on VAD silence).
2. **Transcription:**
   - Pass the PCM buffer to **Whisper Large v3 Turbo (Q8)**.
   - **Important:** Whisper returns `segments` with `startTime` and `endTime`.
   - **Offset Math:** Add the `SessionStartTime` to the `SegmentTime` to get the absolute timestamp in the master audio file.
3. **Saving:**
   - Create a `TranscriptSegment` object:
     - `text`: "Hello world"
     - `audioStartOffset`: 10.5 (seconds)
     - `audioEndOffset`: 12.0 (seconds)
     - `speakerID`: "Speaker A"

### Phase 3: Playback & Export

- **Audio Match:** When user taps a chat bubble -> `player.currentTime = segment.audioStartOffset` -> `player.play()`.
- **Full Download:** User can share the `.m4a` file directly via AirDrop/Share Sheet.

---

## 5. Development Roadmap 🗺️

### Phase 1: The Foundation (Skeleton) 🦴

- [ ] **Model Downloader:** Create a download manager with a progress bar. (Don't let the user record until the brain is installed).
- [ ] **Native Recorder:** Setup `AVAudioRecorder` with background execution permissions.
- [ ] **File System:** Logic to create session folders and save `.m4a` files.

### Phase 2: The Brain & Sync (Core) 🧠

- [ ] **Whisper Integration:** Connect recorded audio buffers to `whisper.cpp`.
- [ ] **Timestamp Logic:** Ensure the text accurately maps to the audio seconds.
- [ ] **Audio Player:** Implement "Seek to time" logic.

### Phase 3: The UI Polish (Skin) 🎨

- [ ] **Chat Experience:** Polish chat timeline, speaker chips, and "New Chat" flow.
- [ ] **Speaker Labels:** Simple "Speaker A/B" assignment.
- [ ] **Export:** Generate PDF/Markdown/Text with optional Notepad-style formatting templates.

---

## 6. Implementation Notes (Tips for Dev) 💡

### Model Downloading Logic (Swift)

```swift
func downloadBrain() {
    let url = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q8_0.bin")!
    let destination = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Models/brain.bin")

    // Use URLSessionDownloadTask to handle background downloading
    // Show a "Downloading AI Brain... (1.8 GB)" progress bar
}
```

---

## Documentation

- [Architecture Overview](docs/architecture.md)
- [Database Design](docs/database.md)
- [Model Management](docs/model-management.md)
- [Audio Pipeline](docs/audio-pipeline.md)
- [API Contracts](docs/api-contracts.md)
- [Tab Navigation](docs/tab-navigation.md)
- [Export Notepad Style](docs/export-notepad-style.md)
- [Roadmap](docs/roadmap.md)
