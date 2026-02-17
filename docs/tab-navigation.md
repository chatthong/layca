# Navigation Model

## Objective
- Use native Apple navigation patterns per platform.
- Keep core app experience chat-first and simple.

## iOS/iPadOS Layout
- App shell uses a custom drawer sidebar overlay (`iosDrawerLayout`) instead of bottom tabs.
- Sidebar open/close interactions:
  - swipe right from anywhere in detail content to open (including over chat bubbles)
  - drag left to close
  - tap dimmed detail area to close
  - chat-header sidebar toggle button opens/closes the drawer (positioned before chat title)
- Sidebar top area is fixed (non-scrolling):
  - search pill (visual shell)
  - `New Chat` compose button
- Sidebar scroll area contains:
  - `Workspace` rows: `Layca Chat`, `Settings`
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
- Drawer pan capture uses an iOS `UIPanGestureRecognizer` installer so swipe-open is recognized across subviews (including bubble/button-heavy chat content).
- Launch behavior opens draft mode by default (`activeSessionID == nil`).
- `New Chat` action in sidebar resets UI to draft and keeps focus on `Layca Chat`.
- `Settings` action opens a single modal settings sheet with multi-step navigation (instead of switching the detail workspace).

## visionOS/tvOS Layout (Current Fallback)
- Uses `TabView` with `TabSection`.
- Primary tabs:
  - `Layca Chat`
  - `Library`
  - `Settings`
- Dedicated action tab:
  - `New Chat`

## macOS Layout
- App shell uses `NavigationSplitView`.
- Sidebar has workspace sections:
  - `Layca Chat`
  - `Settings`
- Sidebar also contains:
  - `Recent Chats` list
  - `New Chat` action button
- Sidebar recent-chat rows support context menu actions:
  - `Rename`
  - `Share this chat`
  - `Delete`
- Chat detail toolbar keeps:
  - inline chat-title badge (tap to rename)
  - trailing native control group (`Play` + `More`, where `More` includes `Share`, `Rename`, `Delete`)
  - on compact iOS widths, the trailing control group collapses into a single ellipsis overflow button with the same actions

## Cross-platform UX Notes
- App launch starts in draft mode on both iOS-family and macOS.
- `New Chat` acts as a draft-reset action:
  - clears active saved session selection
  - returns focus to `Layca Chat`
  - persisted session is created only when recording starts from draft
- iOS/iPadOS uses `Recent Chats` in the drawer as the primary session switcher.
- macOS uses `Recent Chats` in sidebar as the saved-session switcher (no separate Library workspace).
- `Settings` sheet currently contains:
  - Hours credit
  - Language focus
  - Time Display sub-step (`Friendly` / `Hybrid` / `Professional`) for main timer only
  - Advanced:
    - Acceleration sub-step:
      - Whisper ggml GPU Decode toggle
      - Whisper CoreML Encoder toggle
    - Offline Model Switch sub-step (`Fast` / `Normal` / `Pro`)
  - iCloud sync + restore purchases
- macOS `Settings` additionally includes:
  - microphone permission status
  - request permission action
  - System Settings deep-link action
- Active chat badge supports inline rename:
  - tap chat title in the Chat header to edit
  - saved title appears in both Chat and session lists
- iOS non-edit chat-title pill:
  - auto-sizes by title length
  - keeps a minimum width for short names
  - caps width to avoid toolbar overflow, then uses tail truncation for long names
- While chat-title editing is active (iOS + macOS):
  - non-title header actions are hidden
  - tapping outside the edit form (content/sidebar/toolbar focus-loss path) cancels editing
- Renaming from session context menu (Library where available or sidebar `Recent Chats`) updates the same persisted session title used by Chat header.
- `Export` opens from a header/toolbar action instead of a tab.
- Export format sub-steps show a shortened preview snippet (11 lines + `…` when truncated) on both iOS-family and macOS.
- Export styles are:
  - `Notepad Minutes` (header + spacer line + timestamp/speaker/language blocks)
  - `Plain Text` (raw transcript text only)
  - `Markdown`
  - `Video Subtitles (.srt)`
- Export `Share` sends a style-specific temporary file (`.txt`, `.md`, `.srt`) so receiving apps treat the payload as the intended format.
- macOS export format sub-step keeps `Share` and `Copy` in a single action row.
- Recorder timer behavior:
  - draft idle state shows starter text (`Tap to start record` on iOS/iPadOS, `Click to start record` on macOS)
  - main timer formatting follows setting `Time Display` (`Friendly` / `Hybrid` / `Professional`)
  - saved chats show accumulated prior recorded duration
  - continuing recording on a saved chat resumes from previous duration
- During transcript-bubble playback (player mode):
  - recorder action changes to `Stop`
  - recorder tint switches to green
  - main timer shows countdown (time remaining)
  - subtitle shows segment range (`mm:ss → mm:ss`)
- Recorder accessory glass tint stays red while recording.
- During active recording, new transcript updates do not auto-scroll by default.
- `New message` button appears for pending updates; tapping it jumps to bottom and enables follow mode.
- Follow mode stays enabled until user scrolls away from bottom.
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
- macOS detail pane has a minimum width guard to keep chat layout readable while resizing.

## Why This Design
- Preserves native behavior and consistency with Apple navigation guidance on each platform.
- Keeps chat and settings workflows stable while adapting shell style to device class.
- Gives iOS/iPadOS a gesture-driven workspace drawer and macOS a desktop-native split workspace.
- Keeps `New Chat` visually prominent as a quick action.
