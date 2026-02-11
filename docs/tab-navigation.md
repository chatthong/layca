# Navigation Model

## Objective
- Use native Apple navigation patterns per platform.
- Keep core app experience chat-first and simple.

## iOS-family Layout (iOS, iPadOS, visionOS, tvOS)
- Group 1 tabs:
  - `Layca Chat`
  - `Library`
  - `Setting`
- Group 2 tab:
  - `New Chat` (special role, isolated in right-side group)
- Header identity:
  - Active chat badge (`Layca` in draft, or saved chat title such as `chat N`) supports tap-to-rename inline editing when a saved chat is active.
- Header action:
  - `Export` icon (top-right on chat screen, next to active chat badge)

## iOS-family Implementation Detail
- SwiftUI `TabView` with `TabSection` groups.
- `New Chat` uses a special tab role to stay in a separate group.
- Tabs are split into dedicated files:
  - `Features/Chat/ChatTabView.swift`
  - `Features/Settings/SettingsTabView.swift`
  - `Features/Library/LibraryTabView.swift`
- `App/ContentView.swift` keeps shared state and dispatches actions across tab components.
- Launch behavior opens draft mode by default (`activeSessionID == nil`).
- `Layca Chat` tab shows current selection (draft or an activated saved chat).
- `New Chat` tab action resets UI to draft mode and returns focus to `Layca Chat`.

## macOS Layout
- App shell uses `NavigationSplitView` instead of bottom tabs.
- Sidebar has workspace sections:
  - `Layca Chat`
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
- App launch starts in draft mode on both iOS-family and macOS.
- `New Chat` acts as a draft-reset action:
  - Triggering it clears active saved session selection.
  - App returns focus to `Layca Chat`.
  - A persisted session is created only when recording starts from draft.
- `Library` acts as session switcher:
  - Shows available chat sessions.
  - Tapping a session loads it and switches to `Layca Chat`.
  - Long-press/right-click on a session row opens:
    - `Rename`
    - `Share this chat`
    - `Delete`
- macOS-only `Layca Chat` sidebar behavior:
  - Clicking `Layca Chat` while an old chat is active returns to draft mode (when not recording).
  - Sidebar checkmark for `Layca Chat` appears only in draft mode; old chat selection is shown in `Recent Chats`.
- iOS-only `Layca Chat` tab behavior:
  - Returning from `Library` to `Layca Chat` keeps the selected old chat.
  - Draft reset is triggered by `New Chat`, not by switching back to `Layca Chat`.
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
- Recorder timer behavior:
  - Draft mode shows `00:00:00`.
  - Saved chats show accumulated prior recorded duration.
  - Continuing recording on a saved chat resumes from the previous duration.
- iOS-family pages use plain `systemBackground` and native material cards/surfaces, so light/dark appearance follows device setting automatically.
- Transcript bubbles are tappable for per-message playback only when recording is stopped.
- During live recording, new rows may temporarily show `Message queued for automatic transcription...` until queue processing finishes.
- Long-press on a transcript bubble opens actions for:
  - `Edit Text`
  - `Edit Speaker Name` (syncs all rows with same `speakerID`)
  - `Change Speaker` (pick another existing speaker profile)
  - `Transcribe Again` submenu:
    - `Transcribe Auto`
    - `Transcribe in <Focus Language>` (selected focus languages only)
- Bubble long-press is disabled while recording and while queued/active transcription is in progress.
- Forced `TH` / `EN` retries validate script output and retry once without prompt before keeping existing text.
- `Transcribe Again` execution is currently gated while recording and shows `Stop recording before running Transcribe Again.`.
- Chunk transcription runs automatically in queue order and keeps original spoken language (auto-detect + no translation).

## Why This Design
- Preserves native behavior and consistency with Apple navigation guidance on each platform.
- Keeps frequent actions (`Layca Chat`, `Setting`, `Library`) stable across device families.
- Gives macOS a desktop-native workspace model instead of an iOS-style tab chrome.
- Keeps `New Chat` visually distinct as a quick action.
