import SwiftUI
#if os(macOS)
import AppKit
#endif
import AVFoundation
#if os(macOS)
import AppKit
#endif

#if os(macOS)
enum MacWorkspaceSection: String, CaseIterable, Identifiable {
    case chat
    case setting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chat:
            return "Layca Chat"
        case .setting:
            return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .chat:
            return "bubble.left.and.bubble.right"
        case .setting:
            return "slider.horizontal.3"
        }
    }
}

struct MacWorkspaceSidebarView: View {
    @Binding var selectedSection: MacWorkspaceSection
    let sessions: [ChatSession]
    let activeSessionID: UUID?
    let onSelectSession: (ChatSession) -> Void
    let onRenameSession: (ChatSession, String) -> Void
    let onDeleteSession: (ChatSession) -> Void
    let shareTextForSession: (ChatSession) -> String
    let onSelectChatWorkspace: () -> Void
    let onCreateSession: () -> Void

    @State private var sessionPendingRename: ChatSession?
    @State private var renameDraft = ""
    @State private var sessionPendingDelete: ChatSession?

    var body: some View {
        List {
            workspaceSection
            recentChatsSection
        }
        .listStyle(.sidebar)
        .navigationTitle("Layca")
        .toolbar {
            ToolbarItem {
                Button(action: onCreateSession) {
                    Image(systemName: "plus.bubble")
                }
                .help("New Chat")
            }
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                NotificationCenter.default.post(
                    name: Notification.Name("LaycaCancelTitleRenameEditing"),
                    object: nil
                )
            }
        )
        .alert("Rename Chat", isPresented: renameAlertBinding, actions: {
            TextField("Chat name", text: $renameDraft)
            Button("Cancel", role: .cancel) {
                sessionPendingRename = nil
                renameDraft = ""
            }
            Button("Save") {
                if let session = sessionPendingRename {
                    onRenameSession(session, renameDraft)
                }
                sessionPendingRename = nil
                renameDraft = ""
            }
        }, message: {
            Text("Enter a new name for this chat.")
        })
        .confirmationDialog(
            "Delete this chat?",
            isPresented: deleteDialogBinding,
            titleVisibility: .visible
        ) {
            Button("Delete Chat", role: .destructive) {
                if let session = sessionPendingDelete {
                    onDeleteSession(session)
                }
                sessionPendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                sessionPendingDelete = nil
            }
        } message: {
            if let sessionPendingDelete {
                Text("This will permanently remove \"\(sessionPendingDelete.title)\" and its recording.")
            } else {
                Text("This will permanently remove this chat and its recording.")
            }
        }
    }

    private var workspaceSection: some View {
        Section("Workspace") {
            ForEach(Array(MacWorkspaceSection.allCases), id: \.self) { section in
                Button {
                    if section == .chat {
                        onSelectChatWorkspace()
                    } else {
                        selectedSection = section
                    }
                } label: {
                    Label(section.title, systemImage: section.symbol)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 8)
                .padding(.horizontal, 8)
                .background(
                    isWorkspaceSectionSelected(section)
                        ? RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(nsColor: .quaternaryLabelColor))
                        : nil
                )
            }
        }
    }

    private func isWorkspaceSectionSelected(_ section: MacWorkspaceSection) -> Bool {
        switch section {
        case .chat:
            return selectedSection == .chat && activeSessionID == nil
        case .setting:
            return selectedSection == section
        }
    }

    private var recentChatsSection: some View {
        Section("Recent Chats") {
            if sessions.isEmpty {
                Text("No chats yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sessions) { session in
                    Button {
                        selectedSection = .chat
                        onSelectSession(session)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.title)
                                .lineLimit(1)
                                .fontWeight(activeSessionID == session.id ? .semibold : .regular)
                            Text(session.formattedDate)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)
                    .background(
                        activeSessionID == session.id
                            ? RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color(nsColor: .quaternaryLabelColor))
                            : nil
                    )
                    .contextMenu {
                        Section("Chat Actions") {
                            Button {
                                sessionPendingRename = session
                                renameDraft = session.title
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }

                            ShareLink(
                                item: shareTextForSession(session),
                                subject: Text(session.title),
                                message: Text("Shared from Layca")
                            ) {
                                Label("Share this chat", systemImage: "square.and.arrow.up")
                            }

                            Button(role: .destructive) {
                                sessionPendingDelete = session
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { sessionPendingRename != nil },
            set: { isPresented in
                if !isPresented {
                    sessionPendingRename = nil
                    renameDraft = ""
                }
            }
        )
    }

    private var deleteDialogBinding: Binding<Bool> {
        Binding(
            get: { sessionPendingDelete != nil },
            set: { isPresented in
                if !isPresented {
                    sessionPendingDelete = nil
                }
            }
        )
    }
}

struct MacChatWorkspaceView: View {
    private let toolbarTitleMaxWidth: CGFloat = 280

    let isRecording: Bool
    let isTranscriptChunkPlaying: Bool
    let isDraftSession: Bool
    let recordingTimeText: String
    let transcriptChunkPlaybackRemainingText: String
    let waveformBars: [Double]
    let activeSessionTitle: String
    let activeSessionDateText: String
    let transcriptChunkPlaybackRangeText: String?
    let activePlaybackRowID: UUID?
    let liveChatItems: [TranscriptRow]
    let selectedFocusLanguageCodes: Set<String>
    let transcribingRowIDs: Set<UUID>
    let queuedRetranscriptionRowIDs: Set<UUID>
    let isTranscriptionBusy: Bool
    let preflightMessage: String?
    let canPlayTranscriptChunks: Bool
    let onRecordTap: () -> Void
    let onTranscriptTap: (TranscriptRow) -> Void
    let onManualEditTranscript: (TranscriptRow, String) -> Void
    let onEditSpeakerName: (TranscriptRow, String) -> Void
    let onChangeSpeaker: (TranscriptRow, String) -> Void
    let onRetranscribeTranscript: (TranscriptRow, String?) -> Void
    let canPlaySessionFromStart: Bool
    let onPlayFromStartTap: () -> Void
    let onExportTap: () -> Void
    let onDeleteActiveSessionTap: () -> Void
    let onRenameSessionTitle: (String) -> Void
    let onOpenSettingsTap: () -> Void
    @State private var titleDraft = ""
    @State private var isEditingTitle = false
    @State private var isDeleteDialogPresented = false

    @FocusState private var isTitleFieldFocused: Bool
    @State private var isTranscriptNearBottom = true
    @State private var hasPendingNewMessage = false
    @State private var isAutoScrollModeEnabled = false

    private let transcriptBottomAnchorID = "layca.mac.transcript.bottom"
    private let recordingSpectrumRowID = "layca.mac.recording.spectrum.row"

    var body: some View {
        transcriptPane
        .overlay {
            if isEditingTitle {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        cancelTitleRename()
                    }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            recorderBottomBar
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
        }
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                if isEditingTitle {
                    toolbarTitleEditor
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    toolbarTitleLabel
                }
            }

            if !isEditingTitle {
                ToolbarSpacer(.flexible)

                ToolbarItemGroup {
                    Button(action: onPlayFromStartTap) {
                        Image(systemName: "play.fill")
                    }
                    .labelStyle(.iconOnly)
                    .help("Play from 00:00 to end")
                    .disabled(!canPlaySessionFromStart)

                    Menu {
                        Button {
                            onExportTap()
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }

                        Button {
                            beginTitleRename()
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        .disabled(isDraftSession)

                        Button(role: .destructive) {
                            isDeleteDialogPresented = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .disabled(isDraftSession)
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuIndicator(.hidden)
                    .disabled(isDraftSession)
                }
            }

            ToolbarSpacer(.fixed)
        }
        .onAppear {
            titleDraft = activeSessionTitle
        }
        .onChange(of: activeSessionTitle) { _, newTitle in
            if !isEditingTitle {
                titleDraft = newTitle
            }
        }
        .task(id: isEditingTitle) {
            if isEditingTitle {
                isTitleFieldFocused = true
            }
        }
        .onChange(of: isTitleFieldFocused) { _, focused in
            if isEditingTitle && !focused {
                cancelTitleRename()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LaycaCancelTitleRenameEditing"))) { _ in
            if isEditingTitle {
                cancelTitleRename()
            }
        }
        .confirmationDialog(
            "Delete this chat?",
            isPresented: $isDeleteDialogPresented,
            titleVisibility: .visible
        ) {
            Button("Delete Chat", role: .destructive) {
                onDeleteActiveSessionTap()
            }
            Button("Cancel", role: .cancel) {
                isDeleteDialogPresented = false
            }
        } message: {
            Text("This will permanently remove \"\(activeSessionTitle)\" and its recording.")
        }
    }


    private var toolbarTitleLabel: some View {
        Button(action: beginTitleRename) {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(activeSessionTitle)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)

            }
            .frame(maxWidth: toolbarTitleMaxWidth, alignment: .leading)
        }
        .help("Rename Chat")
    }

    @ViewBuilder
    private var toolbarTitleEditor: some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField("Chat name", text: $titleDraft)
                .textFieldStyle(.plain)
                .font(.headline.weight(.semibold))
                .lineLimit(1)
                .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
                .focused($isTitleFieldFocused)
                .onSubmit {
                    commitTitleRename()
                }

            Button(action: commitTitleRename) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("Save")

            Button(action: cancelTitleRename) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("Cancel")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(minWidth: 320, idealWidth: 320, maxWidth: 320, alignment: .leading)
    }

    private var recorderBottomBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let preflightMessage {
                VStack(alignment: .leading, spacing: 4) {
                    Text(preflightMessage)
                        .font(.caption)
                        .foregroundStyle(.red)

                    if isMicrophonePermissionMessage(preflightMessage) {
                        Button("Open System Settings") {
                            _ = MacMicrophonePermissionSupport.openMicrophoneSettings()
                        }
                        .buttonStyle(.link)
                        .font(.caption.weight(.semibold))
                    }
                }
                .padding(.horizontal, 2)
            }

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    if recorderShowsDraftPrompt {
                        Text(recorderTimerText)
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                    } else {
                        Text(recorderTimerText)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                    }

                    Text(recorderSubtitleText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Button(action: onRecordTap) {
                    HStack(spacing: 7) {
                        Image(systemName: recorderActionSymbol)
                        Text(recorderActionTitle)
                    }
                    .font(.headline.weight(.semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .foregroundStyle(recorderActionColor)
                .glassEffect(recorderControlGlass, in: Capsule(style: .continuous))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .glassEffect(recorderContainerGlass, in: Capsule(style: .continuous))
        }
    }

    private var recorderContainerGlass: Glass {
        Glass.regular
            .tint(recorderContainerTintColor)
            .interactive(false)
    }

    private var recorderControlGlass: Glass {
        Glass.regular.interactive(false)
    }

    private var recorderActionIsStopMode: Bool {
        isRecording || isTranscriptChunkPlaying
    }

    private var recorderActionTitle: String {
        recorderActionIsStopMode ? "Stop" : "Record"
    }

    private var recorderActionSymbol: String {
        recorderActionIsStopMode ? "stop.fill" : "record.circle.fill"
    }

    private var recorderActionColor: Color {
        if isRecording {
            return Color.red.opacity(0.90)
        }
        if isTranscriptChunkPlaying {
            return Color.green.opacity(0.90)
        }
        return Color.accentColor
    }

    private var recorderContainerTintColor: Color? {
        if isRecording {
            return Color.red.opacity(0.12)
        }
        if isTranscriptChunkPlaying {
            return Color.green.opacity(0.12)
        }
        return nil
    }

    private var recorderTimerText: String {
        if isTranscriptChunkPlaying {
            return transcriptChunkPlaybackRemainingText
        }
        if recorderShowsDraftPrompt {
            return "Click to start record"
        }
        return recordingTimeText
    }

    private var recorderSubtitleText: String {
        if isTranscriptChunkPlaying {
            return transcriptChunkPlaybackRangeText ?? "Segment Range"
        }
        return activeSessionDateText
    }

    private var recorderShowsDraftPrompt: Bool {
        isDraftSession && !isRecording && !isTranscriptChunkPlaying
    }

    private var transcriptPane: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if liveChatItems.isEmpty && !isRecording {
                        ContentUnavailableView(
                            "No Messages Yet",
                            systemImage: "waveform.badge.magnifyingglass",
                            description: Text("Start recording to stream transcript messages here.")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            ForEach(liveChatItems, id: \.id) { item in
                                TranscriptBubbleOptionButton(
                                    item: item,
                                    liveChatItems: liveChatItems,
                                    selectedFocusLanguageCodes: selectedFocusLanguageCodes,
                                    isRecording: isRecording,
                                    isTranscriptionBusy: isTranscriptionBusy,
                                    isItemTranscribing: transcribingRowIDs.contains(item.id),
                                    isItemQueuedForRetranscription: queuedRetranscriptionRowIDs.contains(item.id),
                                    isPlayable: isRowPlayable(item),
                                    onTap: {
                                        onTranscriptTap(item)
                                    },
                                    onManualEditTranscript: onManualEditTranscript,
                                    onEditSpeakerName: onEditSpeakerName,
                                    onChangeSpeaker: onChangeSpeaker,
                                    onRetranscribeTranscript: onRetranscribeTranscript
                                ) {
                                    transcriptRow(
                                        for: item,
                                        isTranscribing: transcribingRowIDs.contains(item.id),
                                        isQueued: queuedRetranscriptionRowIDs.contains(item.id),
                                        isPlaybackActive: item.id == activePlaybackRowID
                                    )
                                }
                                .id(item.id)
                                .onAppear {
                                    handleTranscriptRowVisible(item.id)
                                }
                                .onDisappear {
                                    handleTranscriptRowHidden(item.id)
                                }
                                .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            }

                            if isRecording {
                                recordingSpectrumListRow
                                    .id(recordingSpectrumRowID)
                                    .onAppear {
                                        handleRecordingSpectrumRowVisible()
                                    }
                                    .onDisappear {
                                        handleRecordingSpectrumRowHidden()
                                    }
                                    .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                            }

                            Color.clear
                                .frame(height: 1)
                                .id(transcriptBottomAnchorID)
                                .listRowInsets(EdgeInsets())
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }

                if hasPendingNewMessage {
                    Button {
                        scrollToTranscriptBottom(using: proxy, animated: true)
                        isAutoScrollModeEnabled = true
                        hasPendingNewMessage = false
                    } label: {
                        Label("New message", systemImage: "arrow.down.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .background(
                        Capsule(style: .continuous)
                            .fill(.regularMaterial)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(.primary.opacity(0.16), lineWidth: 0.9)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
                    .padding(.trailing, 20)
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.18), value: hasPendingNewMessage)
            .onChange(of: transcriptUpdateSignature) { _, _ in
                handleTranscriptUpdate(using: proxy)
            }
            .onChange(of: isTranscriptNearBottom) { _, nearBottom in
                if !nearBottom {
                    isAutoScrollModeEnabled = false
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var recordingSpectrumListRow: some View {
        HStack {
            RecordingSpectrumBubble(
                waveformBars: waveformBars,
                cornerRadius: 11,
                horizontalPadding: 10,
                verticalPadding: 10,
                strokeOpacity: 0.08
            )
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .allowsHitTesting(false)
    }

    private func transcriptRow(
        for item: TranscriptRow,
        isTranscribing: Bool,
        isQueued: Bool,
        isPlaybackActive: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(item.speaker)
                    .font(.headline)
                Spacer()
                Text(item.time)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(item.language)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(.quaternary.opacity(0.75))
                    )
            }

            if isTranscribing {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Transcribing message...")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red.opacity(0.86))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            } else if isQueued {
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange.opacity(0.88))
                    Text("Queued for Transcribe Again...")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange.opacity(0.88))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            } else {
                Text(displayText(for: item))
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.90))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(isPlaybackActive ? Color.green.opacity(0.18) : Color.clear)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(.regularMaterial)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(
                    isPlaybackActive ? Color.green.opacity(0.45) : .primary.opacity(0.08),
                    lineWidth: 0.8
                )
        )
        .animation(
            .easeInOut(duration: 0.2),
            value: isTranscribing || isQueued || isPlaybackActive
        )
    }

    private func displayText(for item: TranscriptRow) -> String {
        let trimmed = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "No message text." : trimmed
    }

    private func isRowPlayable(_ item: TranscriptRow) -> Bool {
        guard canPlayTranscriptChunks else {
            return false
        }
        guard let start = item.startOffset, let end = item.endOffset else {
            return false
        }
        return end > start
    }

    private func isMicrophonePermissionMessage(_ message: String) -> Bool {
        message.localizedCaseInsensitiveContains("microphone permission")
    }

    private var transcriptUpdateSignature: Int {
        var hasher = Hasher()
        hasher.combine(liveChatItems.count)
        hasher.combine(isRecording)
        for item in liveChatItems {
            hasher.combine(item.id)
            hasher.combine(item.text)
            hasher.combine(item.startOffset ?? -1)
            hasher.combine(item.endOffset ?? -1)
            hasher.combine(transcribingRowIDs.contains(item.id))
            hasher.combine(queuedRetranscriptionRowIDs.contains(item.id))
        }
        return hasher.finalize()
    }

    private func handleTranscriptRowVisible(_ rowID: UUID) {
        guard rowID == liveChatItems.last?.id else {
            return
        }
        isTranscriptNearBottom = true
    }

    private func handleTranscriptRowHidden(_ rowID: UUID) {
        guard rowID == liveChatItems.last?.id else {
            return
        }
        isTranscriptNearBottom = false
    }

    private func handleRecordingSpectrumRowVisible() {
        guard isRecording else {
            return
        }
        isTranscriptNearBottom = true
    }

    private func handleRecordingSpectrumRowHidden() {
        guard isRecording else {
            return
        }
        isTranscriptNearBottom = false
    }

    private func handleTranscriptUpdate(using proxy: ScrollViewProxy) {
        guard isRecording else {
            hasPendingNewMessage = false
            isAutoScrollModeEnabled = false
            return
        }

        if isAutoScrollModeEnabled {
            scrollToTranscriptBottom(using: proxy, animated: true)
            hasPendingNewMessage = false
        } else {
            hasPendingNewMessage = true
        }
    }

    private func scrollToTranscriptBottom(using proxy: ScrollViewProxy, animated: Bool) {
        let scrollAction = {
            if isRecording {
                proxy.scrollTo(recordingSpectrumRowID, anchor: .bottom)
            } else if let lastID = liveChatItems.last?.id {
                proxy.scrollTo(lastID, anchor: .bottom)
            } else {
                proxy.scrollTo(transcriptBottomAnchorID, anchor: .bottom)
            }
        }

        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                scrollAction()
            }
        } else {
            scrollAction()
        }
    }

    private func beginTitleRename() {
        titleDraft = activeSessionTitle
        isEditingTitle = true
    }

    private func commitTitleRename() {
        let trimmedTitle = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            onRenameSessionTitle(trimmedTitle)
            titleDraft = trimmedTitle
        } else {
            titleDraft = activeSessionTitle
        }
        isEditingTitle = false
        isTitleFieldFocused = false
    }

    private func cancelTitleRename() {
        titleDraft = activeSessionTitle
        isEditingTitle = false
        isTitleFieldFocused = false
    }

}

struct MacLibraryWorkspaceView: View {
    let sessions: [ChatSession]
    let activeSessionID: UUID?
    let onSelectSession: (ChatSession) -> Void
    let onRenameSession: (ChatSession, String) -> Void
    let onDeleteSession: (ChatSession) -> Void
    let shareTextForSession: (ChatSession) -> String

    @State private var sessionPendingRename: ChatSession?
    @State private var renameDraft = ""
    @State private var sessionPendingDelete: ChatSession?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Library", systemImage: "books.vertical")
                    .font(.title2.weight(.semibold))
                Spacer()
                Text("\(sessions.count) chats")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)

            if sessions.isEmpty {
                ContentUnavailableView(
                    "No Sessions",
                    systemImage: "tray",
                    description: Text("Create a new chat to start recording.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(sessions) { session in
                        Button {
                            onSelectSession(session)
                        } label: {
                            HStack(alignment: .center, spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(session.title)
                                        .font(.headline)
                                        .lineLimit(1)
                                    Text(session.formattedDate)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(session.rows.count) messages")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(.quaternary.opacity(0.72))
                                    )
                                if activeSessionID == session.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 2)
                        .contextMenu {
                            Section("Chat Actions") {
                                Button {
                                    sessionPendingRename = session
                                    renameDraft = session.title
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }

                                ShareLink(
                                    item: shareTextForSession(session),
                                    subject: Text(session.title),
                                    message: Text("Shared from Layca")
                                ) {
                                    Label("Share this chat", systemImage: "square.and.arrow.up")
                                }

                                Button(role: .destructive) {
                                    sessionPendingDelete = session
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Library")
        .alert("Rename Chat", isPresented: renameAlertBinding, actions: {
            TextField("Chat name", text: $renameDraft)
            Button("Cancel", role: .cancel) {
                sessionPendingRename = nil
                renameDraft = ""
            }
            Button("Save") {
                if let session = sessionPendingRename {
                    onRenameSession(session, renameDraft)
                }
                sessionPendingRename = nil
                renameDraft = ""
            }
        }, message: {
            Text("Enter a new name for this chat.")
        })
        .confirmationDialog(
            "Delete this chat?",
            isPresented: deleteDialogBinding,
            titleVisibility: .visible
        ) {
            Button("Delete Chat", role: .destructive) {
                if let session = sessionPendingDelete {
                    onDeleteSession(session)
                }
                sessionPendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                sessionPendingDelete = nil
            }
        } message: {
            if let sessionPendingDelete {
                Text("This will permanently remove \"\(sessionPendingDelete.title)\" and its recording.")
            } else {
                Text("This will permanently remove this chat and its recording.")
            }
        }
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { sessionPendingRename != nil },
            set: { isPresented in
                if !isPresented {
                    sessionPendingRename = nil
                    renameDraft = ""
                }
            }
        )
    }

    private var deleteDialogBinding: Binding<Bool> {
        Binding(
            get: { sessionPendingDelete != nil },
            set: { isPresented in
                if !isPresented {
                    sessionPendingDelete = nil
                }
            }
        )
    }
}

struct MacSettingsWorkspaceView: View {
    let totalHours: Double
    let usedHours: Double
    @Binding var selectedLanguageCodes: Set<String>
    @Binding var languageSearchText: String
    let filteredFocusLanguages: [FocusLanguage]
    let groupedFocusLanguages: [LanguageRegionGroup]
    @Binding var isICloudSyncEnabled: Bool
    @Binding var whisperCoreMLEncoderEnabled: Bool
    @Binding var whisperGGMLGPUDecodeEnabled: Bool
    @Binding var whisperModelProfile: WhisperModelProfile
    @Binding var mainTimerDisplayStyle: MainTimerDisplayStyle
    let whisperCoreMLEncoderRecommendationText: String
    let whisperGGMLGPUDecodeRecommendationText: String
    let whisperModelRecommendationText: String
    let isRestoringPurchases: Bool
    let restoreStatusMessage: String?
    let onToggleLanguage: (String) -> Void
    let onRestorePurchases: () -> Void
    @State private var microphonePermission: AVAudioApplication.recordPermission = .undetermined

    var body: some View {
        SettingsSheetFlowView(
            totalHours: totalHours,
            usedHours: usedHours,
            selectedLanguageCodes: $selectedLanguageCodes,
            languageSearchText: $languageSearchText,
            filteredFocusLanguages: filteredFocusLanguages,
            groupedFocusLanguages: groupedFocusLanguages,
            isICloudSyncEnabled: $isICloudSyncEnabled,
            whisperCoreMLEncoderEnabled: $whisperCoreMLEncoderEnabled,
            whisperGGMLGPUDecodeEnabled: $whisperGGMLGPUDecodeEnabled,
            whisperModelProfile: $whisperModelProfile,
            mainTimerDisplayStyle: $mainTimerDisplayStyle,
            whisperCoreMLEncoderRecommendationText: whisperCoreMLEncoderRecommendationText,
            whisperGGMLGPUDecodeRecommendationText: whisperGGMLGPUDecodeRecommendationText,
            whisperModelRecommendationText: whisperModelRecommendationText,
            isRestoringPurchases: isRestoringPurchases,
            restoreStatusMessage: restoreStatusMessage,
            onToggleLanguage: onToggleLanguage,
            onRestorePurchases: onRestorePurchases,
            showsMicrophoneMenu: true,
            microphonePermissionState: microphonePermissionState,
            onRequestMicrophoneAccess: requestMicrophoneAccess,
            onOpenMicrophoneSettings: { _ = MacMicrophonePermissionSupport.openMicrophoneSettings() }
        )
        .navigationTitle("Settings")
        .onAppear {
            refreshMicrophonePermission()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshMicrophonePermission()
        }
    }

    private var microphonePermissionState: SettingsMicrophonePermissionState {
        switch microphonePermission {
        case .granted:
            return .granted
        case .undetermined:
            return .undetermined
        case .denied:
            return .denied
        @unknown default:
            return .unknown
        }
    }

    private func refreshMicrophonePermission() {
        microphonePermission = AVAudioApplication.shared.recordPermission
    }

    private func requestMicrophoneAccess() {
        AVAudioApplication.requestRecordPermission { _ in
            DispatchQueue.main.async {
                refreshMicrophonePermission()
            }
        }
    }
}

private enum MacMicrophonePermissionSupport {
    static func openMicrophoneSettings() -> Bool {
        let workspace = NSWorkspace.shared
        let candidateURLs: [URL] = [
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"),
            URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Microphone"),
            URL(fileURLWithPath: "/System/Applications/System Settings.app")
        ]
        .compactMap { $0 }

        for url in candidateURLs where workspace.open(url) {
            return true
        }
        return false
    }
}
#endif
