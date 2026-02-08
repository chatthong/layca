# Tab Navigation

## Objective
- Use native Apple tab-bar patterns for top-level navigation.
- Keep core app experience chat-first and simple.

## Current Native Layout
- Group 1 tabs:
  - `Chat`
  - `Setting`
  - `Library`
- Group 2 tab:
  - `New Chat` (special role, isolated in right-side group)
- Header identity:
  - Active chat badge (`Chat N`) supports tap-to-rename inline editing.
- Header action:
  - `Export` icon (top-right on Chat, next to active chat badge)

## Implementation Detail
- SwiftUI `TabView` with `TabSection` groups.
- `New Chat` uses a special tab role to stay in a separate group.
- Tabs are split into dedicated files:
  - `ChatTabView.swift`
  - `SettingTabView.swift`
  - `LibraryTabView.swift`
- `ContentView.swift` keeps shared state and dispatches actions across tab components.

## UX Notes
- `New Chat` acts like an action tab:
  - Tapping creates a new chat/session.
  - App returns focus to `Chat`.
- `Library` acts as session switcher:
  - Shows available chat sessions.
  - Tapping a session loads it and switches to `Chat`.
- Active chat badge supports inline rename:
  - Tap chat title in the Chat header to edit.
  - Saved title appears in both Chat and Library.
- `Export` opens from the Chat header icon instead of a tab.
- On some compact layouts, iOS may prioritize icon rendering for special-role grouped tabs even if text is provided.

## Why This Design
- Native behavior and consistency with Apple navigation guidance.
- Keeps frequent actions (`Chat`, `Setting`, `Library`) stable.
- Keeps `New Chat` visually distinct as a quick action.
