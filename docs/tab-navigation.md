# Navigation Model

## Objective
- Use native Apple navigation patterns per platform.
- Keep core app experience chat-first and simple.

## iOS-family Layout (iOS, iPadOS, visionOS, tvOS)
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

## iOS-family Implementation Detail
- SwiftUI `TabView` with `TabSection` groups.
- `New Chat` uses a special tab role to stay in a separate group.
- Tabs are split into dedicated files:
  - `Features/Chat/ChatTabView.swift`
  - `Features/Settings/SettingsTabView.swift`
  - `Features/Library/LibraryTabView.swift`
- `App/ContentView.swift` keeps shared state and dispatches actions across tab components.

## macOS Layout
- App shell uses `NavigationSplitView` instead of bottom tabs.
- Sidebar has workspace sections:
  - `Chat`
  - `Library`
  - `Setting`
- Sidebar also contains:
  - recent chats list
  - `New Chat` action button
- Sidebar recent-chat rows support context menu actions:
  - `Rename`
  - `Share this chat`
  - `Delete`
- Toolbar uses:
  - no segmented workspace picker in the title area
  - native SwiftUI toolbar items on Chat detail:
    - `Share` (`ToolbarItem`)
    - grouped `Rename` + `New Chat` (`ToolbarItemGroup`)
    - `Info` (`ToolbarItem`, opens `Setting`)
- Chat detail view is split:
  - left pane: session summary + recorder controls
  - right pane: transcript list

## Cross-platform UX Notes
- `New Chat` acts like an action tab:
  - Triggering it creates a new chat/session.
  - App returns focus to `Chat`.
- `Library` acts as session switcher:
  - Shows available chat sessions.
  - Tapping a session loads it and switches to `Chat`.
  - Long-press/right-click on a session row opens:
    - `Rename`
    - `Share this chat`
    - `Delete`
- `Setting` currently contains:
  - Hours credit
  - Language focus
  - Context keywords (for Whisper prompt context)
  - Advanced Zone:
    - Whisper ggml GPU Decode toggle
    - Whisper CoreML Encoder toggle
    - Model Switch (`Fast` / `Normal` / `Pro`)
  - iCloud sync + restore purchases
- macOS `Setting` additionally includes:
  - microphone permission status
  - request permission action
  - System Settings deep-link action
- Active chat badge supports inline rename:
  - Tap chat title in the Chat header to edit.
  - Saved title appears in both Chat and Library.
- Renaming from Library/sidebar context menu updates the same persisted session title used by Chat header.
- `Export` opens from a header/toolbar action instead of a tab.
  - On macOS, this action is the top-right `Share` toolbar item in Chat detail.
- On some compact layouts, iOS may prioritize icon rendering for special-role grouped tabs even if text is provided.
- iOS-family pages use plain `systemBackground` and native material cards/surfaces, so light/dark appearance follows device setting automatically.
- Transcript bubbles are tappable for per-message playback only when recording is stopped.
- During live recording, new rows may temporarily show `Message queued for automatic transcription...` until queue processing finishes.
- Long-press on a transcript bubble opens actions for:
  - `Edit Text`
  - `Edit Speaker Name` (syncs all rows with same `speakerID`)
  - `Change Speaker` (pick another existing speaker profile)
  - `Transcribe Again`
- Bubble long-press is disabled while recording and while queued/active transcription is in progress.
- `Transcribe Again` execution is currently gated while recording and shows `Stop recording before running Transcribe Again.`.
- Chunk transcription runs automatically in queue order and keeps original spoken language (auto-detect + no translation).

## Why This Design
- Preserves native behavior and consistency with Apple navigation guidance on each platform.
- Keeps frequent actions (`Chat`, `Setting`, `Library`) stable across device families.
- Gives macOS a desktop-native workspace model instead of an iOS-style tab chrome.
- Keeps `New Chat` visually distinct as a quick action.
