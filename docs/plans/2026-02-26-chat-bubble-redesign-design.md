# Chat Bubble Redesign — Design Doc

**Date:** 2026-02-26
**Status:** Approved

## Goal

Make transcript bubbles look like a real chat app — content-hugging widths, avatar only on the last bubble of each speaker run, clean layout on all platforms including macOS.

## What Changes

### Bubble Width
Remove all full-width constraints from the bubble background. `Text` wraps naturally at its container edge. Short messages produce a small pill; long messages wrap to fill available space. No `maxWidth` cap.

### Speaker-Run Avatar Rule
- `isLastInRun`: `index == items.count - 1 || items[index+1].speakerID != item.speakerID`
- When `isLastInRun` → show 34×34 avatar circle + speaker name label
- All other bubbles in the run → left side is empty (reserved width = 34+10pt gap so bubbles stay aligned)

### Removals
- 3pt vertical color accent `Capsule` on the left edge of every bubble — gone
- 8×8 colored dot (continuation avatar placeholder) — gone

### macOS
Currently macOS skips the avatar column. Remove the `#if os(iOS)` guard (or equivalent) so macOS renders the same `avatarView` as iOS.

### Sizing
- Bubble padding: 10pt H / 8pt V (was 13/11)
- Corner radius: 14pt (was 16)
- Same-speaker inter-bubble spacing: 4pt (was 7)
- Speaker-change gap: 12pt

## Platform
iOS · iPadOS · macOS — identical layout.
