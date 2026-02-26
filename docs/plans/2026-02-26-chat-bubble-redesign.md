# Chat Bubble Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make transcript bubbles look like a normal chat app — content-hugging widths, avatar + speaker name shown only on the last bubble of each speaker run, no color accent bar, clean on all platforms.

**Architecture:** Single file change — `ChatTabView.swift`. Replace the `isContinuation` concept with two booleans: `isSameAsPrevious` (for spacing) and `isLastInRun` (for avatar + header visibility). The bubble background drops its `.frame(maxWidth: .infinity)` so it shrinks to content width.

**Tech Stack:** SwiftUI, no new dependencies

---

### Task 1: Replace `isContinuation` with `isSameAsPrevious` + `isLastInRun`

**File:** `xcode/layca/Features/Chat/ChatTabView.swift:858–892`

**Step 1: Replace the two computed booleans (lines 858–892)**

Find this block:
```swift
// A bubble is a "continuation" when the same speaker produced the immediately
// preceding bubble — this happens when two-pass VAD sub-chunking splits one
// speaker's speech at breath-pause boundaries.
let isContinuation = index > 0
    && liveChatItems[index - 1].speakerID == item.speakerID

HStack(alignment: .top, spacing: 10) {
    avatarView(for: item, isContinuation: isContinuation)
    TranscriptBubbleOptionButton(
        ...
    ) {
        messageBubble(
            for: item,
            isContinuation: isContinuation,
            isPlaybackActive: item.id == activePlaybackRowID
        )
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
// Tighten vertical gap between consecutive same-speaker sub-chunks.
.padding(.top, isContinuation ? 2 : 0)
```

Replace with:
```swift
// isSameAsPrevious: controls inter-bubble vertical spacing.
let isSameAsPrevious = index > 0
    && liveChatItems[index - 1].speakerID == item.speakerID
// isLastInRun: controls avatar + speaker-name visibility.
// Avatar and name appear only on the last bubble of each speaker's run.
let isLastInRun = index == liveChatItems.count - 1
    || liveChatItems[index + 1].speakerID != item.speakerID

HStack(alignment: .top, spacing: 10) {
    avatarView(for: item, isLastInRun: isLastInRun)
    TranscriptBubbleOptionButton(
        ...
    ) {
        messageBubble(
            for: item,
            isLastInRun: isLastInRun,
            isPlaybackActive: item.id == activePlaybackRowID
        )
    }
}
// Tighter gap between same-speaker bubbles; larger gap on speaker change.
.padding(.top, isSameAsPrevious ? 4 : 12)
```

Note: the `TranscriptBubbleOptionButton` init arguments between the two `{` are unchanged — only the surrounding lines change.

---

### Task 2: Update `avatarView` — show full avatar on last-in-run, empty space otherwise

**File:** `xcode/layca/Features/Chat/ChatTabView.swift:958–991`

Find this entire function:
```swift
private func avatarView(for item: TranscriptRow, isContinuation: Bool = false) -> some View {
    Group {
        if isContinuation {
            // Continuation bubble: replace the full avatar with a small dot in the
            // speaker's color. The dot is vertically centred in the same 34 pt column
            // so the message bubble aligns with non-continuation rows.
            ZStack {
                Circle()
                    .fill(item.avatarColor.opacity(0.55))
                    .frame(width: 8, height: 8)
            }
            .frame(width: 34, height: 34)
            // Mirror the accessibility information that the full avatar carries so
            // VoiceOver users still know whose sub-chunk this is.
            .accessibilityLabel("Continued: \(item.speaker)")
            .accessibilityHidden(false)
        } else {
            ZStack {
                Circle()
                    .fill(item.avatarColor)

                Image(systemName: item.avatarSymbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
            }
            .frame(width: 34, height: 34)
            .overlay(
                Circle()
                    .stroke(.white.opacity(0.6), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.12), radius: 7, x: 0, y: 4)
        }
    }
}
```

Replace with:
```swift
private func avatarView(for item: TranscriptRow, isLastInRun: Bool = true) -> some View {
    Group {
        if isLastInRun {
            ZStack {
                Circle()
                    .fill(item.avatarColor)

                Image(systemName: item.avatarSymbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
            }
            .frame(width: 34, height: 34)
            .overlay(
                Circle()
                    .stroke(.white.opacity(0.6), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.12), radius: 7, x: 0, y: 4)
            .accessibilityLabel("Speaker: \(item.speaker)")
        } else {
            // Non-last bubble in a same-speaker run: empty column to keep
            // bubbles left-aligned with last bubble in the group.
            Color.clear
                .frame(width: 34, height: 1)
                .accessibilityHidden(true)
        }
    }
}
```

---

### Task 3: Update `messageBubble` — header on last-in-run, no color bar, compact sizing, no full-width

**File:** `xcode/layca/Features/Chat/ChatTabView.swift:993–1069`

Find this entire function:
```swift
private func messageBubble(for item: TranscriptRow, isContinuation: Bool = false, isPlaybackActive: Bool) -> some View {
    VStack(alignment: .leading, spacing: 7) {
        if isContinuation {
            // Continuation bubble: hide the speaker name / language badge row to avoid
            // repetitive visual noise. The 3 pt left-border Capsule accent (below) still
            // provides the color cue connecting same-speaker sub-chunks.
            // VoiceOver picks up the speaker name from the avatar dot's accessibilityLabel
            // on the left; add it here too so every interactive element is self-describing.
            EmptyView()
                .accessibilityLabel("Continued: \(item.speaker)")
        } else {
            HStack(spacing: 8) {
                speakerMeta(for: item)
                Spacer(minLength: 8)
                timestampView(for: item)
            }
        }
        ... (text / progress content unchanged) ...
    }
    .padding(.horizontal, 13)
    .padding(.vertical, 11)
    .background(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(isPlaybackActive ? Color.green.opacity(0.18) : Color.clear)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.regularMaterial)
            )
    )
    .overlay(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(
                isPlaybackActive ? Color.green.opacity(0.45) : .primary.opacity(0.12),
                lineWidth: 0.8
            )
    )
    .overlay(alignment: .leading) {
        Capsule()
            .fill(item.avatarColor.opacity(0.55))
            .frame(width: 3)
            .padding(.vertical, 6)
    }
    .animation(
        .easeInOut(duration: 0.2),
        value: transcribingRowIDs.contains(item.id)
            || queuedRetranscriptionRowIDs.contains(item.id)
            || isPlaybackActive
    )
}
```

Replace with:
```swift
private func messageBubble(for item: TranscriptRow, isLastInRun: Bool = true, isPlaybackActive: Bool) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        if isLastInRun {
            HStack(spacing: 8) {
                speakerMeta(for: item)
                Spacer(minLength: 8)
                timestampView(for: item)
            }
        }

        if transcribingRowIDs.contains(item.id) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(.red.opacity(0.82))
                Text("Transcribing message...")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red.opacity(0.82))
                    .multilineTextAlignment(.leading)
            }
            .transition(.opacity)
        } else if queuedRetranscriptionRowIDs.contains(item.id) {
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange.opacity(0.88))
                Text("Queued for Transcribe Again...")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange.opacity(0.88))
                    .multilineTextAlignment(.leading)
            }
            .transition(.opacity)
        } else {
            Text(item.text)
                .font(.body)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
        }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(isPlaybackActive ? Color.green.opacity(0.18) : Color.clear)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.regularMaterial)
            )
    )
    .overlay(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(
                isPlaybackActive ? Color.green.opacity(0.45) : .primary.opacity(0.12),
                lineWidth: 0.8
            )
    )
    .animation(
        .easeInOut(duration: 0.2),
        value: transcribingRowIDs.contains(item.id)
            || queuedRetranscriptionRowIDs.contains(item.id)
            || isPlaybackActive
    )
}
```

Key changes from old → new:
- `isContinuation` → `isLastInRun` (logic inverted: show header when `isLastInRun`)
- `VStack spacing: 7` → `4`
- Padding: `.horizontal 13` → `10`, `.vertical 11` → `8`
- Corner radius: `16` → `14` (all three occurrences)
- Removed: the `.overlay(alignment: .leading)` Capsule color bar entirely
- Removed: `EmptyView().accessibilityLabel(...)` (no longer needed)
- No `.frame(maxWidth: .infinity)` here — that was removed in Task 1

---

### Task 4: Commit

```bash
cd /Users/ter/Desktop/layca
git add xcode/layca/Features/Chat/ChatTabView.swift
git commit -m "$(cat <<'EOF'
feat: chat bubble redesign — content-hugging width, last-in-run avatar

- Bubble background no longer stretches to full width; shrinks to
  text content like a normal chat app
- Avatar (34×34) + speaker name shown only on the last bubble of each
  speaker's consecutive run (isLastInRun), not on every bubble
- Middle/non-last same-speaker bubbles: plain text bubble, no avatar,
  no name — completely clean
- Removed: 3pt vertical color accent Capsule on every bubble
- Removed: 8×8 colored dot continuation placeholder
- Spacing: 4pt between same-speaker bubbles, 12pt on speaker change
  (was 2pt / 0pt)
- Padding: 10/8pt (was 13/11pt), corner radius 14pt (was 16)

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Notes for implementer
- The `TranscriptBubbleOptionButton` init arguments inside the HStack are **unchanged** — only the surrounding `isContinuation`→`isLastInRun` renames and the removed `.frame(maxWidth:)` matter there.
- If the build shows any `isContinuation` references you missed, search the whole file for `isContinuation` and rename to the appropriate new variable.
- Do NOT run the simulator — user tests manually.
