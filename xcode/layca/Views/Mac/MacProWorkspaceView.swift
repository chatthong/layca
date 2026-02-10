import SwiftUI
import AVFoundation
#if os(macOS)
import AppKit
#endif

#if os(macOS)
enum MacWorkspaceSection: String, CaseIterable, Identifiable {
    case chat
    case library
    case setting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chat:
            return "Chat"
        case .library:
            return "Library"
        case .setting:
            return "Setting"
        }
    }

    var symbol: String {
        switch self {
        case .chat:
            return "bubble.left.and.bubble.right"
        case .library:
            return "books.vertical"
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
    let onCreateSession: () -> Void

    @State private var sessionPendingRename: ChatSession?
    @State private var renameDraft = ""
    @State private var sessionPendingDelete: ChatSession?

    var body: some View {
        List {
            workspaceSection
            recentChatsSection
            createChatSection
        }
        .listStyle(.sidebar)
        .navigationTitle("Layca")
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
                    selectedSection = section
                } label: {
                    HStack(spacing: 8) {
                        Label(section.title, systemImage: section.symbol)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selectedSection == section ? Color.accentColor.opacity(0.20) : .clear)
                )
            }
        }
    }

    private var recentChatsSection: some View {
        Section("Recent Chats") {
            if sessions.isEmpty {
                Text("No chats yet")
                    .foregroundStyle(.secondary)
            } else {
                SwiftUI.ForEach(0..<sessions.count, id: \.self) { (index: Int) in
                    let session = sessions[index]
                    Button {
                        selectedSection = .chat
                        onSelectSession(session)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.title)
                                .lineLimit(1)
                            Text(session.formattedDate)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .trailing) {
                                if activeSessionID == session.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 3)
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

    private var createChatSection: some View {
        Section {
            Button(action: onCreateSession) {
                Label("New Chat", systemImage: "plus.bubble")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
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
    let isRecording: Bool
    let recordingTimeText: String
    let waveformBars: [Double]
    let activeSessionTitle: String
    let activeSessionDateText: String
    let liveChatItems: [TranscriptRow]
    let transcribingRowIDs: Set<UUID>
    let isTranscriptionBusy: Bool
    let preflightMessage: String?
    let canPlayTranscriptChunks: Bool
    let onRecordTap: () -> Void
    let onTranscriptTap: (TranscriptRow) -> Void
    let onManualEditTranscript: (TranscriptRow, String) -> Void
    let onEditSpeakerName: (TranscriptRow, String) -> Void
    let onChangeSpeaker: (TranscriptRow, String) -> Void
    let onRetranscribeTranscript: (TranscriptRow) -> Void
    let onExportTap: () -> Void
    let onRenameSessionTitle: () -> Void

    var body: some View {
        ZStack {
            background

            HSplitView {
                leftPane
                    .frame(minWidth: 300, idealWidth: 340, maxWidth: 420)

                transcriptPane
                    .frame(minWidth: 520)
            }
            .padding(16)
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color(nsColor: .underPageBackgroundColor).opacity(0.94)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 240, height: 240)
                .blur(radius: 42)
                .offset(x: 70, y: -80)
        }
        .ignoresSafeArea()
    }

    private var leftPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            sessionSummaryCard
            recorderCard
            Spacer(minLength: 0)
        }
    }

    private var sessionSummaryCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text(activeSessionTitle)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)

                Text(activeSessionDateText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Divider()

                LabeledContent("Rows", value: "\(liveChatItems.count)")
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            HStack {
                Label("Session", systemImage: "bubble.left.and.bubble.right")
                Spacer()
                ControlGroup {
                    Button(action: onRenameSessionTitle) {
                        Image(systemName: "pencil")
                    }
                    .help("Rename")

                    Button(action: onExportTap) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .help("Export")
                }
            }
        }
    }

    private var recorderCard: some View {
        GroupBox("Recorder") {
            VStack(alignment: .leading, spacing: 12) {
                waveformView

                Text(recordingTimeText)
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Button {
                    onRecordTap()
                } label: {
                    Label(
                        isRecording ? "Stop Recording" : "Start Recording",
                        systemImage: isRecording ? "stop.circle.fill" : "record.circle.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(isRecording ? .red : .accentColor)
                .controlSize(.large)

                if let preflightMessage {
                    VStack(alignment: .leading, spacing: 6) {
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
                }
            }
        }
    }

    private var waveformView: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(waveformBars.enumerated()), id: \.offset) { _, level in
                Capsule(style: .continuous)
                    .fill(isRecording ? Color.red.opacity(0.82) : Color.accentColor.opacity(0.68))
                    .frame(width: 4, height: max(CGFloat(level) * 58, 8))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 86, maxHeight: 86)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary.opacity(0.58))
        )
    }

    private var transcriptPane: some View {
        GroupBox {
            if liveChatItems.isEmpty {
                ContentUnavailableView(
                    "No Transcript Yet",
                    systemImage: "waveform.badge.magnifyingglass",
                    description: Text("Start recording to stream transcript rows here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(liveChatItems, id: \.id) { item in
                        TranscriptBubbleOptionButton(
                            item: item,
                            liveChatItems: liveChatItems,
                            isRecording: isRecording,
                            isTranscriptionBusy: isTranscriptionBusy,
                            isItemTranscribing: transcribingRowIDs.contains(item.id),
                            isPlayable: isRowPlayable(item),
                            onTap: {
                                onTranscriptTap(item)
                            },
                            onManualEditTranscript: onManualEditTranscript,
                            onEditSpeakerName: onEditSpeakerName,
                            onChangeSpeaker: onChangeSpeaker,
                            onRetranscribeTranscript: onRetranscribeTranscript
                        ) {
                            transcriptRow(for: item)
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        } label: {
            HStack {
                Label("Transcript", systemImage: "text.bubble")
                Spacer()
                if isRecording {
                    Label("Live", systemImage: "dot.radiowaves.left.and.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func transcriptRow(for item: TranscriptRow) -> some View {
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
            Text(displayText(for: item))
                .font(.subheadline)
                .foregroundStyle(.primary.opacity(0.90))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(.primary.opacity(0.08), lineWidth: 0.8)
        )
    }

    private func displayText(for item: TranscriptRow) -> String {
        let trimmed = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "No transcript text." : trimmed
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
                    SwiftUI.ForEach(0..<sessions.count, id: \.self) { (index: Int) in
                        let session = sessions[index]
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
                                Text("\(session.rows.count) rows")
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
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .underPageBackgroundColor).opacity(0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
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
    @Binding var focusContextKeywords: String
    let filteredFocusLanguages: [FocusLanguage]
    @Binding var isICloudSyncEnabled: Bool
    let isRestoringPurchases: Bool
    let restoreStatusMessage: String?
    let onToggleLanguage: (String) -> Void
    let onRestorePurchases: () -> Void
    @State private var microphonePermission: AVAudioApplication.recordPermission = .undetermined

    private var remainingHours: Double {
        max(totalHours - usedHours, 0)
    }

    var body: some View {
        Form {
            Section("Credits") {
                LabeledContent("Remaining") {
                    Text("\(remainingHours, specifier: "%.1f")h")
                        .fontWeight(.semibold)
                }
                ProgressView(value: usedHours, total: totalHours)
                HStack {
                    Text("\(usedHours, specifier: "%.1f")h used")
                    Spacer()
                    Text("Total \(totalHours, specifier: "%.1f")h")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Microphone Access") {
                HStack(spacing: 8) {
                    Image(systemName: microphonePermissionStatusSymbol)
                        .foregroundStyle(microphonePermissionStatusColor)
                    Text(microphonePermissionStatusTitle)
                        .font(.subheadline.weight(.semibold))
                }

                Text(microphonePermissionHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                switch microphonePermission {
                case .granted:
                    Button("Open System Settings") {
                        _ = MacMicrophonePermissionSupport.openMicrophoneSettings()
                    }
                case .undetermined:
                    Button("Allow Microphone Access") {
                        requestMicrophoneAccess()
                    }
                    .buttonStyle(.borderedProminent)
                case .denied:
                    Button("Open System Settings") {
                        _ = MacMicrophonePermissionSupport.openMicrophoneSettings()
                    }
                    .buttonStyle(.borderedProminent)
                @unknown default:
                    Button("Open System Settings") {
                        _ = MacMicrophonePermissionSupport.openMicrophoneSettings()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Section("Language Focus") {
                TextField("Search language (en, th, japanese...)", text: $languageSearchText)
                    .textFieldStyle(.roundedBorder)
                TextField("Context keywords", text: $focusContextKeywords)
                    .textFieldStyle(.roundedBorder)

                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 8)], spacing: 8) {
                        ForEach(filteredFocusLanguages, id: \.id) { language in
                            languageChip(for: language)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 220)
            }

            Section("Cloud & Purchases") {
                Toggle("Sync via iCloud", isOn: $isICloudSyncEnabled)

                Button(action: onRestorePurchases) {
                    HStack(spacing: 8) {
                        if isRestoringPurchases {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isRestoringPurchases ? "Restoring..." : "Restore Purchases")
                    }
                }
                .disabled(isRestoringPurchases)

                if let restoreStatusMessage {
                    Text(restoreStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .underPageBackgroundColor).opacity(0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .onAppear {
            refreshMicrophonePermission()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshMicrophonePermission()
        }
    }

    @ViewBuilder
    private func languageChip(for language: FocusLanguage) -> some View {
        let isSelected = selectedLanguageCodes.contains(language.code)

        if isSelected {
            Button {
                onToggleLanguage(language.code)
            } label: {
                languageChipLabel(for: language)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        } else {
            Button {
                onToggleLanguage(language.code)
            } label: {
                languageChipLabel(for: language)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func languageChipLabel(for language: FocusLanguage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(language.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text("\(language.code.uppercased()) • \(language.iso3.uppercased())")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var microphonePermissionStatusTitle: String {
        switch microphonePermission {
        case .granted:
            return "Microphone access granted"
        case .undetermined:
            return "Microphone access not requested yet"
        case .denied:
            return "Microphone access denied"
        @unknown default:
            return "Microphone access status unknown"
        }
    }

    private var microphonePermissionHint: String {
        switch microphonePermission {
        case .granted:
            return "Layca can record normally."
        case .undetermined:
            return "Allow access once to start recording."
        case .denied:
            return "macOS blocks recording until you enable Layca in Privacy & Security > Microphone."
        @unknown default:
            return "Open System Settings to verify microphone access."
        }
    }

    private var microphonePermissionStatusSymbol: String {
        switch microphonePermission {
        case .granted:
            return "checkmark.circle.fill"
        case .undetermined:
            return "questionmark.circle"
        case .denied:
            return "xmark.circle.fill"
        @unknown default:
            return "exclamationmark.circle"
        }
    }

    private var microphonePermissionStatusColor: Color {
        switch microphonePermission {
        case .granted:
            return .green
        case .undetermined:
            return .orange
        case .denied:
            return .red
        @unknown default:
            return .secondary
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
