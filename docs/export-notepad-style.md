# Export Notepad Style

## Purpose
- Keep the app UI chat-first and simple.
- Provide Notepad-style readability only in exported documents.

## Scope
- Applies only to transcript export output.
- Does not add an in-app Notepad tab or editor mode.

## Style Presets
1. `notepadMinutes`
- Timestamp as prefix per paragraph.
- Speaker label included.
- Compact spacing for meeting minutes.

2. `notepadClean`
- Speaker label optional.
- Wider spacing and cleaner paragraph flow.
- Good for sharing summaries in email/docs.

## Suggested Export Header
- Session title
- Date/time range
- Language(s)
- Optional participant labels

## Example Snippet
```text
[00:04:32] Speaker A (EN)
Let's lock the roadmap and keep the settings page minimal.

[00:04:47] Speaker B (TH)
Agreed. We can add VAD options after cleanup.
```

## Implementation Notes
- Reuse transcript segments and timestamps from storage.
- Apply style transform at export time only.
- Keep raw transcript unchanged in persistence.
