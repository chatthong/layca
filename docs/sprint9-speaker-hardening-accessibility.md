# Sprint 9 — Speaker-ID Hardening + Accessibility Polish

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Apply the four code-review findings to the uncommitted speaker-ID fix, commit it cleanly, then knock out the pending accessibility quick-wins and small UI polish items from TODO.md.

**Architecture:** All changes are in existing files — no new files required. Tasks 1–5 fix the uncommitted speaker-ID changes before they are committed. Tasks 6–15 are independent small improvements that can be done in any order after Task 5.

**Tech Stack:** Swift, SwiftUI, AVFoundation, CoreML, AccessibilityKit (no new dependencies)

---

## Phase A — Speaker-ID Review Fixes (commit these together)

### Task 1: Share the WeSpeaker diarizer instance [H1 — double model load]

**Problem:** `PostSaveSpeakerClassifier` creates its own `SpeakerDiarizationCoreMLService`, loading the WeSpeaker CoreML model a second time alongside `LiveSessionPipeline`'s copy. Two model weight copies in memory.

**Files:**
- Modify: `xcode/layca/App/AppBackend.swift`

**Step 1: Read the diarizer property in LiveSessionPipeline**

Find `private let speakerDiarizer = SpeakerDiarizationCoreMLService()` inside `actor LiveSessionPipeline`. Note the exact line.

Also find `init()` of `LiveSessionPipeline` and the `PostSaveSpeakerClassifier` init.

**Step 2: Add an initializer to `PostSaveSpeakerClassifier` that accepts an external diarizer**

Change `PostSaveSpeakerClassifier`:
```swift
// BEFORE
actor PostSaveSpeakerClassifier {
    private let diarizer = SpeakerDiarizationCoreMLService()
    private var diarizerReady = false
    ...

// AFTER
actor PostSaveSpeakerClassifier {
    private let diarizer: SpeakerDiarizationCoreMLService
    private var diarizerReady = false

    init(diarizer: SpeakerDiarizationCoreMLService) {
        self.diarizer = diarizer
    }
    ...
```

**Step 3: Expose `speakerDiarizer` from `LiveSessionPipeline`**

In `LiveSessionPipeline`, change `private let speakerDiarizer` to `let speakerDiarizer` (internal access, still read-only from outside).

**Step 4: Thread the shared instance through `AppBackend`**

In `AppBackend`, find where `LiveSessionPipeline` and `PostSaveSpeakerClassifier` are created. Make the pipeline's diarizer available before `PostSaveSpeakerClassifier` init:

```swift
// AppBackend: create pipeline first, then share its diarizer
private lazy var pipeline = LiveSessionPipeline()
private lazy var postSaveSpeakerClassifier = PostSaveSpeakerClassifier(
    diarizer: pipeline.speakerDiarizer
)
```

If `pipeline` is not a stored property on `AppBackend` (it may be created on demand), find where the pipeline is instantiated and adapt accordingly — the key principle is one diarizer instance shared by both.

**Step 5: Verify `diarizerReady` logic still works**

After the change, `PostSaveSpeakerClassifier.classify` calls `diarizer.prepareIfNeeded()`. If the live pipeline already prepared the model, this call will be a no-op (the diarizer guards internally with `guard model == nil`). Verify this is the case by reading `SpeakerDiarizationCoreMLService.prepareIfNeeded()`.

---

### Task 2: Reset interrupt counter on inference timeout [M1]

**Problem:** When the 250ms inference timeout fires, `MLModel.prediction` continues running on the diarizer actor. The `consecutiveInterruptWindows` counter can be incremented by that background task *after* the pipeline has already moved on, causing a phantom speaker boundary on the next check.

**Files:**
- Modify: `xcode/layca/App/AppBackend.swift`

**Step 1: Find the interrupt inference race in `LiveSessionPipeline`**

Search for `interruptInferenceTimeoutNanoseconds` in AppBackend.swift. The code uses `withTaskGroup` to race inference vs a sleep timeout, returning `false` on timeout.

**Step 2: Add `resetInterruptState()` call on the timeout path**

```swift
// BEFORE (timeout path):
for await result in group {
    group.cancelAll()
    if let result {
        return result
    }
    return false  // timeout
}

// AFTER:
for await result in group {
    group.cancelAll()
    if let result {
        return result
    }
    // Timeout: the diarizer actor may still be running inference.
    // Reset the consecutive-window counter so a stale increment
    // from the background task cannot trigger a false speaker cut.
    await speakerDiarizer.resetInterruptState()
    return false
}
```

**Step 3: Verify `resetInterruptState()` exists**

Confirm `SpeakerDiarizationCoreMLService.resetInterruptState()` exists (it was added in Sprint 1–3). It sets `consecutiveInterruptWindows = 0`.

---

### Task 3: Seed `PostSaveSpeakerClassifier` with existing session speaker labels [M2]

**Problem:** `PostSaveSpeakerClassifier` starts with an empty embedding store per session. After app restart, it reassigns from "Speaker A" regardless of what labels already exist in `SessionStore`. This can call `changeTranscriptRowSpeaker` with labels that auto-create orphan `SpeakerProfile` entries.

**Files:**
- Modify: `xcode/layca/App/AppBackend.swift`

**Step 1: Add a `seedSession` method to `PostSaveSpeakerClassifier`**

```swift
/// Seeds the classifier with speaker labels that already exist in the session,
/// so post-save labels remain consistent with the live pipeline's assignment.
/// Call this once per session before the first `classify` call.
func seedSession(sessionID: UUID, existingLabels: Set<String>) {
    // Only seed if we have no existing state for this session.
    guard speakerEmbeddingsBySession[sessionID] == nil else { return }
    // Initialize the label space with empty (placeholder) entries so the
    // classifier won't re-use "Speaker A" for a genuinely new speaker.
    var placeholders: [String: [Float]] = [:]
    for label in existingLabels {
        // Zero vector — will be replaced on first real embedding assignment.
        placeholders[label] = []
    }
    speakerEmbeddingsBySession[sessionID] = placeholders
    speakerObservationCountsBySession[sessionID] = Dictionary(
        uniqueKeysWithValues: existingLabels.map { ($0, 0) }
    )
}
```

**Step 2: Call `seedSession` in the chunk-save flow**

In `AppBackend`, immediately before calling `postSaveSpeakerClassifier.classify(...)`, add:

```swift
// Seed so post-save labels stay in the same namespace as the live pipeline.
let existingLabels = Set(
    await sessionStore.session(for: sessionID)?.speakers.keys ?? []
)
await postSaveSpeakerClassifier.seedSession(
    sessionID: sessionID,
    existingLabels: existingLabels
)
```

Find `sessionStore.session(for:)` — it may be named differently. Look for how AppBackend reads session data from SessionStore and adapt accordingly.

**Step 3: Update `closestSpeaker` to skip placeholder (empty) embeddings**

In `PostSaveSpeakerClassifier.closestSpeaker(for:in:)`, skip entries with empty embedding vectors:

```swift
for (label, reference) in speakerEmbeddings {
    guard !reference.isEmpty else { continue }  // skip placeholders
    let similarity = cosineSimilarity(embedding, reference)
    ...
}
```

---

### Task 4: Add `finalizeSession` cleanup [L1]

**Problem:** `pendingCandidateBySession` accumulates per-session entries that are never removed when a session ends, growing unbounded across many sessions.

**Files:**
- Modify: `xcode/layca/App/AppBackend.swift`

**Step 1: Add `finalizeSession` to `PostSaveSpeakerClassifier`**

```swift
/// Removes all in-progress state for a session. Call after the last chunk
/// of a session has been classified.
func finalizeSession(sessionID: UUID) {
    pendingCandidateBySession[sessionID] = nil
    // Optionally clear embeddings too if memory is a concern in very long
    // recording sessions. For now keep them for potential future re-classification.
}
```

**Step 2: Call `finalizeSession` when a session ends**

In `AppBackend`, find where recording stops and the session is finalized (after the last chunk is saved and transcribed). Add:

```swift
await postSaveSpeakerClassifier.finalizeSession(sessionID: sessionID)
```

This is typically near where `streamTask` is cancelled or where the pipeline `stop()` is called.

---

### Task 5: Commit the complete speaker-ID fix

**Step 1: Verify build**

Open the Xcode project and build for the iOS simulator to confirm no compile errors from Tasks 1–4.

```bash
cd /Users/ter/Desktop/layca/xcode
xcodebuild -scheme layca -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -30
```

Expected: `BUILD SUCCEEDED`

**Step 2: Commit**

```bash
cd /Users/ter/Desktop/layca
git add xcode/layca/App/AppBackend.swift \
        xcode/layca/Features/Chat/ChatTabView.swift \
        xcode/layca/Libraries/SpeakerDiarizationCoreMLService.swift \
        xcode/layca/Models/Domain/TranscriptRow.swift
git commit -m "$(cat <<'EOF'
fix: speaker-ID collapse after Sprint 7/8 chunk architecture

Root cause: minimumSamples default (1600) silently disabled interrupt
detection at 48kHz — 4096 source samples resample to only 1365 samples,
below the 1600 threshold. Combined with 80ms inference timeout (shorter
than one 85ms audio window), speaker boundaries were never detected.

Fixes applied (Sprint 9 code-review hardening):
- minimumSamples: 1200 (1365 ≥ 1200 at 48kHz, 1485 at 44.1kHz)
- interruptCheckWindowSize reverted 8192→4096 (aligns accumulator with
  service's internal 4096-sample window; 512ms→256ms cadence)
- interruptInferenceTimeoutNanoseconds 80ms→250ms (3× window duration)
- speakerAssignmentLooseSimilarityThreshold: 0.62 — separate from probe
  threshold; stops centroid contamination in 0.62–0.65 similarity zone
- PostSaveSpeakerClassifier — second-pass re-classification after Whisper
  save, with stricter thresholds (0.72 vs 0.65) and shared diarizer
- consecutiveInterruptWindows reset on inference timeout (false-cut fix)
- lastKnownSpeakerEmbedding seeded on first probe assignment (blind window)
- Notification handler guard+Task[self] pattern (TOCTOU fix)
- PostSaveSpeakerClassifier seeded from existing session labels (label sync)
- finalizeSession cleanup for pendingCandidateBySession

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Phase B — Accessibility Quick-Wins

*All tasks below are independent and can be done in any order. Each is S-sized.*

### Task 6: Fix waveform bar color [Bug — High]

**Files:**
- Modify: `xcode/layca/Features/Chat/ChatTabView.swift`

**Step 1: Find `waveformPanel` in ChatTabView.swift**

Search for `Color.red.opacity(0.78)` — the hardcoded bar fill color.

**Step 2: Replace with computed recorder state color**

```swift
// BEFORE:
.fill(Color.red.opacity(0.78))

// AFTER:
.fill(recorderActionColor.opacity(0.78))
```

`recorderActionColor` is already a computed property on ChatTabView. Confirm it exists by searching for it.

**Step 3: Build and verify**

The waveform bars should now be red when recording, green during playback, and grey when idle.

**Step 4: Commit**

```bash
git add xcode/layca/Features/Chat/ChatTabView.swift
git commit -m "fix: waveform bars now reflect recorder state color

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 7: Accessibility — waveform panel label

**Files:**
- Modify: `xcode/layca/Features/Chat/ChatTabView.swift`

**Step 1: Find `waveformPanel` view builder**

Search for `waveformPanel` in ChatTabView.swift. Find the outermost container of the waveform view.

**Step 2: Add accessibility modifiers to the container and hide individual bars**

```swift
// On the waveform container (outermost HStack or ZStack):
.accessibilityLabel("Audio waveform, \(isRecording ? "recording active" : "idle")")

// On each individual bar Capsule:
.accessibilityHidden(true)
```

**Step 3: Commit**

```bash
git add xcode/layca/Features/Chat/ChatTabView.swift
git commit -m "a11y: add VoiceOver label to waveform panel

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 8: Accessibility — group transcript bubble elements

**Files:**
- Modify: `xcode/layca/Features/Chat/ChatTabView.swift`

**Step 1: Find `messageBubble(for:)` in ChatTabView.swift**

Search for `func messageBubble` or the comment referencing bubble content layout.

**Step 2: Add element grouping and hint to the bubble VStack**

```swift
// On the main bubble VStack that contains speaker name + timestamp + text:
.accessibilityElement(children: .combine)
.accessibilityHint(isTranscriptBubblePlayable(row) ? "Double tap to play" : "")
```

**Step 3: Commit**

```bash
git add xcode/layca/Features/Chat/ChatTabView.swift
git commit -m "a11y: combine transcript bubble elements for VoiceOver

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 9: Accessibility — avatar circle label

**Files:**
- Modify: `xcode/layca/Features/Chat/ChatTabView.swift`

**Step 1: Find `avatarView(for:)` in ChatTabView.swift**

Search for `func avatarView` or `"person.fill"`.

**Step 2: Add accessibilityLabel to the avatar Image/ZStack**

```swift
// On the avatar view (ZStack or Image):
.accessibilityLabel("Speaker: \(item.speaker)")
```

Where `item.speaker` is the display name for that transcript row's speaker. If the speaker name is derived differently, adapt to the correct property.

**Step 3: Commit**

```bash
git add xcode/layca/Features/Chat/ChatTabView.swift
git commit -m "a11y: add speaker name to avatar VoiceOver label

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 10: Accessibility — language badge label

**Files:**
- Modify: `xcode/layca/Features/Chat/ChatTabView.swift`

**Step 1: Find `speakerMeta(for:)` and the language badge HStack**

Search for `"globe"` or `speakerMeta` in ChatTabView.swift. Find the HStack that contains the globe icon + language code text.

**Step 2: Add semantic label to the HStack and hide the globe icon**

```swift
// On the language HStack:
.accessibilityLabel("Language: \(resolvedLanguageName(item.language))")

// On the globe Image:
.accessibilityHidden(true)
```

If `resolvedLanguageName` doesn't exist, use `Locale.current.localizedString(forLanguageCode: item.language) ?? item.language`.

**Step 3: Commit**

```bash
git add xcode/layca/Features/Chat/ChatTabView.swift
git commit -m "a11y: add semantic VoiceOver label to language badge

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 11: Accessibility — replace hardcoded font sizes with Dynamic Type

**Files:**
- Modify: `xcode/layca/Features/Chat/ChatTabView.swift`

**Step 1: Find the three hardcoded font sizes**

Search for `size: 46`, `size: 22`, `size: 19` in ChatTabView.swift.

**Step 2: Replace with Dynamic Type equivalents**

```swift
// size: 46  →  .system(.largeTitle, design: .rounded, weight: .semibold)
// size: 22  →  .system(.title2, design: .rounded, weight: .bold)
// size: 19  →  .system(.title3, design: .rounded, weight: .semibold)
```

**Step 3: Find `waveformPanel` fixed height**

Search for `frame(width: 120, height: 126)` in the waveform panel. Change the height to flexible:

```swift
// BEFORE:
.frame(width: 120, height: 126)

// AFTER:
.frame(width: 120)
.frame(minHeight: 80, idealHeight: 126)
```

**Step 4: Build and verify**

In iOS simulator, go to Settings → Accessibility → Display & Text Size → Larger Text. Set to maximum. Verify the main timer and waveform panel don't overflow.

**Step 5: Commit**

```bash
git add xcode/layca/Features/Chat/ChatTabView.swift
git commit -m "a11y: replace hardcoded font sizes with Dynamic Type

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Phase C — UI Polish

### Task 12: Add play affordance to transcript bubbles

**Files:**
- Modify: `xcode/layca/Features/Chat/ChatTabView.swift`

**Step 1: Find `messageBubble(for:)` and `isTranscriptBubblePlayable`**

Locate both the bubble builder and the `isTranscriptBubblePlayable` helper.

**Step 2: Add a subtle play icon overlay on playable bubbles**

Inside the bubble, add a small `play.circle` icon in the trailing-bottom corner, visible only when playable:

```swift
if isTranscriptBubblePlayable(row) {
    Image(systemName: "play.circle")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary.opacity(0.6))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(.trailing, 8)
        .padding(.bottom, 4)
        .allowsHitTesting(false)
}
```

Place this as an overlay on the bubble content ZStack/VStack.

**Step 3: Commit**

```bash
git add xcode/layca/Features/Chat/ChatTabView.swift
git commit -m "feat: show play.circle affordance on playable transcript bubbles

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 13: Replace NotificationCenter rename-cancel with state nonce

**Files:**
- Modify: `xcode/layca/Features/Chat/ChatTabView.swift`
- Modify: `xcode/layca/App/ContentView.swift`

**Step 1: Find the NotificationCenter coupling in ChatTabView**

Search for `"LaycaCancelTitleRenameEditing"` in ChatTabView.swift. Note the `onReceive` handler that cancels editing.

**Step 2: Replace with a UUID nonce passed from ContentView**

In `ContentView`, add:
```swift
@State private var cancelRenameNonce = UUID()
```

Pass it into ChatTabView (find the ChatTabView init and add the parameter):
```swift
// In ContentView where ChatTabView is created:
ChatTabView(..., cancelRenameNonce: cancelRenameNonce)
```

In ChatTabView, add:
```swift
let cancelRenameNonce: UUID
```

Replace the `onReceive(NotificationCenter...)` with:
```swift
.onChange(of: cancelRenameNonce) { _, _ in
    isEditingTitle = false
}
```

In places that previously posted the notification (sidebar row taps, etc.), instead mutate `cancelRenameNonce = UUID()` through the backend or environment.

**Step 3: Remove the old NotificationCenter post sites**

Search for `.post(name: Notification.Name("LaycaCancelTitleRenameEditing")` and replace with `cancelRenameNonce = UUID()` at each call site.

**Step 4: Commit**

```bash
git add xcode/layca/Features/Chat/ChatTabView.swift xcode/layca/App/ContentView.swift
git commit -m "refactor: replace NotificationCenter rename-cancel with UUID nonce

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 14: Fix ChatTabView `beginTitleRename` DispatchQueue hack

**Files:**
- Modify: `xcode/layca/Features/Chat/ChatTabView.swift`

**Step 1: Find `beginTitleRename()` in ChatTabView**

Search for `beginTitleRename` or `asyncAfter` in ChatTabView.swift. There may be multiple `DispatchQueue.main.asyncAfter` calls used to delay focus.

**Step 2: Replace with `.task(id:)` focus pattern**

The macOS equivalent was already fixed (Sprint 2). Apply the same pattern to ChatTabView:

```swift
// BEFORE (in beginTitleRename or similar):
DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
    self.isTitleFieldFocused = true
}

// AFTER — remove beginTitleRename entirely.
// Instead, use .task(id: isEditingTitle) on the title TextField:
.task(id: isEditingTitle) {
    guard isEditingTitle else { return }
    // Small yield lets SwiftUI finish layout before focusing.
    try? await Task.sleep(nanoseconds: 50_000_000)
    isTitleFieldFocused = true
}
```

**Step 3: Commit**

```bash
git add xcode/layca/Features/Chat/ChatTabView.swift
git commit -m "fix: replace DispatchQueue focus hack with task(id:) in ChatTabView

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 15: Replace macOS background gradient with adaptive Color asset

**Files:**
- Modify: `xcode/layca/Features/Chat/ChatTabView.swift`

**Step 1: Find the macOS hardcoded gradient**

Search for `Color(red: 0.91` in ChatTabView.swift (the macOS background gradient).

**Step 2: Replace with adaptive system color**

```swift
// BEFORE:
Color(red: 0.91, green: 0.91, blue: 0.93)  // (or similar hardcoded values)

// AFTER:
Color(.windowBackground)   // macOS adaptive, respects dark mode
// or:
Color(NSColor.windowBackgroundColor)
```

If the gradient uses multiple stops, replace all stops with `Color(.windowBackground)` / `Color(.underPageBackgroundColor)` as appropriate for the visual intent.

**Step 3: Commit**

```bash
git add xcode/layca/Features/Chat/ChatTabView.swift
git commit -m "fix: replace hardcoded macOS background gradient with adaptive Color

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Sprint Summary

| Phase | Tasks | Effort |
|---|---|---|
| A — Speaker-ID hardening | 1–5 | M total (apply code review + commit) |
| B — Accessibility | 6–11 | S each |
| C — UI polish | 12–15 | S each |

**Total: 15 tasks, ~1 Codex session**

After this sprint:
- Speaker-ID fix is committed and hardened against the 4 review issues
- All 5 pending accessibility items from TODO.md are cleared
- Waveform color bug, play affordance, and NotificationCenter tech debt resolved
- App is ready for Sprint 10 focus: **StoreKit 2 IAP + on-device LLM summary (Qwen 2.5 MLX)**
