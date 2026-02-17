# Export Formats

## Purpose
- Keep the app UI chat-first and simple.
- Offer format-specific export outputs for notes, copy/paste, docs, and subtitle workflows.

## Scope
- Applies only to transcript export output.
- Does not add an in-app editor mode.
- Available from chat header/toolbar export action on both iOS-family and macOS layouts.
- On macOS, export is triggered from the Chat-detail top-right `More` menu (`Share` action).

## Styles (Current)
1. `notepadMinutes`
- Output includes:
  - session title
  - `Created: <date>`
  - one extra blank spacer line
  - transcript blocks formatted as `[HH:mm:ss] Speaker (LANG)` + message body
- Intended for meeting-minute readability.

2. `plainText`
- Output includes only transcript message text blocks.
- No title/date header.
- No timestamp/speaker/language prefixes.
- Intended for quick paste into other tools.

3. `markdown`
- Output includes markdown heading and transcript section structure.
- Intended for docs/wiki/notes tools that support markdown.

4. `videoSubtitlesSRT`
- Output uses SubRip format (`.srt`):
  - indexed cues
  - `HH:MM:SS,mmm --> HH:MM:SS,mmm` timing lines
  - cue text body
- Cue timing prefers row `startOffset`/`endOffset`; falls back to parsed row time and minimum duration guards when offsets are unavailable.
- Intended for video editors and players with subtitle track support.

## Share + Copy Behavior
- `Share` writes a temporary file and shares its URL with style-specific extension:
  - `notepadMinutes` -> `.txt`
  - `plainText` -> `.txt`
  - `markdown` -> `.md`
  - `videoSubtitlesSRT` -> `.srt`
- `Copy` always copies the text payload for the selected style.

## Preview Rules
- Export format detail preview is intentionally capped to a short snippet:
  - first 11 lines
  - trailing `…` when additional lines exist
- On macOS export detail step, `Actions` places `Share` and `Copy` on one row.

## Implementation Notes
- Reuse transcript message rows and timestamps/offsets from storage.
- Export uses latest persisted row text (including automatic queued Whisper updates and quality-filtered row removals).
- Apply style transforms at export time only.
- Keep raw transcript unchanged in persistence.
