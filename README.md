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
2. **Dual-View Interface:** Switch instantly between a **"Group Chat"** view (who said what) and a **"Notepad"** view (clean text for editing).
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

## 3. UI/UX Strategy: "The Switch" 🔀

Layca features a toggle at the top of the session view to switch modes instantly.

### Mode A: "Group Chat" Style (The Default) 💬

- **Visual:** Bubbles (Left/Right aligned based on Speaker ID).
- **Interaction:**
  - **Tap-to-Play:** Tapping a bubble plays the specific audio slice for that sentence.
  - **Export:** Export single bubble audio or text.
- **Use Case:** Reviewing who said what, resolving arguments, checking translations.

### Mode B: "Notepad" Style (The Editor) 📝

- **Visual:** A continuous rich text document (like Apple Notes).
- **Interaction:**
  - Text is editable (fix typos, bold key points).
  - Timestamps are hidden or small markers in the margin.
- **Use Case:** Creating Meeting Minutes, copying to email, summarizing.

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

- [ ] **Dual Views:** Build `ChatView` and `NoteView` and the toggle logic.
- [ ] **Speaker Labels:** Simple "Speaker A/B" assignment.
- [ ] **Export:** Generate a PDF or Markdown file from the Notepad view.

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
- [Roadmap](docs/roadmap.md)
