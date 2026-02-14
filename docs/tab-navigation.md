# Navigation Model

## Objective
- Use native Apple navigation patterns per platform.
- Keep core app experience chat-first and simple.

## iOS/iPadOS Layout
- App shell uses a custom drawer sidebar overlay (`iosDrawerLayout`) instead of bottom tabs.
- Sidebar open/close interactions:
  - swipe from left edge to open
  - drag left to close
  - tap dimmed detail area to close
  - chat-header sidebar toggle button opens/closes the drawer (positioned before chat title)
- Sidebar top area is fixed (non-scrolling):
  - search pill (visual shell)
  - `New Chat` compose button
- Sidebar scroll area contains:
  - `Workspace` rows: `Layca Chat`, `Setting`
  - `Recent Chats` list (session switcher)
- `Recent Chats` rows support context menu actions:
  - `Rename`
  - `Share this chat`
  - `Delete`
- Active row highlight is subtle and compact to match macOS workspace style.

## iOS/iPadOS Implementation Detail
- Root shell lives in `App/ContentView.swift` (`iosDrawerLayout`).
- Drawer body lives in `Views/Components/IOSWorkspaceSidebarView.swift`.
- Drawer state is controlled by:
  - `isIOSSidebarPresented`
  - `iosSidebarDragOffset`
- Launch behavior opens draft mode by default (`activeSessionID == nil`).
- `New Chat` action in sidebar resets UI to draft and keeps focus on `Layca Chat`.

## visionOS/tvOS Layout (Current Fallback)
- Uses `TabView` with `TabSection`.
- Primary tabs:
  - `Layca Chat`
  - `Library`
  - `Setting`
- Dedicated action tab:
  - `New Chat`

## macOS Layout
- App shell uses `NavigationSplitView`.
- Sidebar has workspace sections:
  - `Layca Chat`
  - `Library`
  - `Setting`
- Sidebar also contains:
  - `Recent Chats` list
  - `New Chat` action button
- Sidebar recent-chat rows support context menu actions:
  - `Rename`
  - `Share this chat`
  - `Delete`
- Toolbar uses native SwiftUI toolbar items on Chat detail:
  - `Share` (`ToolbarItem`)
  - grouped `Rename` + `New Chat` (`ToolbarItemGroup`)
  - `Info` (`ToolbarItem`, opens `Setting`)

## Cross-platform UX Notes
- App launch starts in draft mode on both iOS-family and macOS.
- `New Chat` acts as a draft-reset action:
  - clears active saved session selection
  - returns focus to `Layca Chat`
  - persisted session is created only when recording starts from draft
- iOS/iPadOS uses `Recent Chats` in the drawer as the primary session switcher.
- macOS keeps both workspace `Library` and `Recent Chats` in sidebar.
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
  - tap chat title in the Chat header to edit
  - saved title appears in both Chat and session lists
- While chat-title editing is active (iOS + macOS):
  - non-title header actions are hidden
  - tapping outside the edit form (content/sidebar/toolbar focus-loss path) cancels editing
- Renaming from Library/sidebar context menu updates the same persisted session title used by Chat header.
- `Export` opens from a header/toolbar action instead of a tab.
- Recorder timer behavior:
  - draft mode shows `00:00:00`
  - saved chats show accumulated prior recorded duration
  - continuing recording on a saved chat resumes from previous duration
- Recorder accessory glass tint switches to red while recording (`.tint(.red.opacity(0.12))`).
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
- Keeps chat and settings workflows stable while adapting shell style to device class.
- Gives iOS/iPadOS a gesture-driven workspace drawer and macOS a desktop-native split workspace.
- Keeps `New Chat` visually prominent as a quick action.
