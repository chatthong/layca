//
//  ContentView.swift
//  layca
//
//  Created by Chatthong Rimthong on 8/2/26.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

struct ContentView: View {
    @StateObject private var backend = AppBackend()
    @State private var isExportPresented = false
    @State private var exportSheetPresentationID = UUID()
    @State private var isSettingsPresented = false
    @State private var settingsSheetPresentationID = UUID()

    @State private var selectedTab: AppTab = .chat
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isIOSSidebarPresented = false
    @State private var iosSidebarDragOffset: CGFloat = 0
#endif

    var body: some View {
        rootLayout
        .sheet(isPresented: $isExportPresented) {
            exportScreen
                .id(exportSheetPresentationID)
        }
        .sheet(isPresented: $isSettingsPresented) {
            settingsSheetScreen
        }
    }
}

#Preview {
    ContentView()
}

private extension ContentView {
    @ViewBuilder
    var rootLayout: some View {
#if os(macOS)
        macDesktopLayout
#elseif os(iOS)
        if horizontalSizeClass == .regular {
            ipadSplitLayout
        } else {
            iosDrawerLayout
        }
#else
        mobileTabLayout
#endif
    }

    @ViewBuilder
    var mobileTabLayout: some View {
        let tabs = TabView(selection: $selectedTab) {
            TabSection {
                Tab("Layca Chat", systemImage: "bubble.left.and.bubble.right.fill", value: AppTab.chat) {
                    chatScreen(showsTopToolbar: true)
                }

                Tab("Recent", systemImage: "books.vertical.fill", value: AppTab.library) {
                    libraryScreen
                }

                Tab("Settings", systemImage: "square.stack.3d.up", value: AppTab.setting) {
                    settingScreen
                }
            }

            TabSection {
                Tab(value: AppTab.newChat, role: .search) {
                    Color.clear
                } label: {
                    Label("New Chat", systemImage: "plus.bubble")
                }
            }
        }
        .tint(.accentColor)
        .laycaApplyTabBarBackgroundStyle()
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .newChat {
                startNewChatAndReturnToChat()
            }
        }

#if os(iOS)
        tabs
#else
        tabs
#endif
    }

#if os(iOS)
    var ipadSplitLayout: some View {
        NavigationSplitView {
            IOSWorkspaceSidebarView(
                selectedSection: iosSectionBinding,
                sessions: backend.sessions,
                activeSessionID: backend.activeSessionID,
                onSelectSession: { session in
                    backend.activateSession(session)
                    selectedTab = .chat
                },
                onRenameSession: backend.renameSession,
                onDeleteSession: backend.deleteSession,
                shareTextForSession: backend.shareText,
                onSelectChatWorkspace: openLaycaChatWorkspace,
                onCreateSession: startNewChatAndReturnToChat
            )
            .navigationSplitViewColumnWidth(min: 230, ideal: 280, max: 360)
        } detail: {
            iosDetailScreen
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            if selectedTab == .newChat || selectedTab == .setting {
                selectedTab = .chat
            }
        }
    }

    var iosDrawerLayout: some View {
        GeometryReader { proxy in
            let sidebarWidth = min(max(proxy.size.width * 0.82, 300), 360)
            let sidebarOffset = iosSidebarOffsetX(width: sidebarWidth)
            let reveal = max(0, min(1, 1 + (sidebarOffset / sidebarWidth)))

            ZStack(alignment: .leading) {
                iosDetailScreen
                    .offset(x: reveal * 24)
                    .animation(.spring(response: 0.28, dampingFraction: 0.9), value: reveal)

                if reveal > 0.001 {
                    Color.black
                        .opacity(0.34 * reveal)
                        .ignoresSafeArea()
                        .onTapGesture {
                            setIOSSidebarPresented(false)
                        }
                }

                IOSWorkspaceSidebarView(
                    selectedSection: iosSectionBinding,
                    sessions: backend.sessions,
                    activeSessionID: backend.activeSessionID,
                    onSelectSession: { session in
                        backend.activateSession(session)
                        selectedTab = .chat
                        setIOSSidebarPresented(false)
                    },
                    onRenameSession: backend.renameSession,
                    onDeleteSession: backend.deleteSession,
                    shareTextForSession: backend.shareText,
                    onSelectChatWorkspace: {
                        openLaycaChatWorkspace()
                        setIOSSidebarPresented(false)
                    },
                    onCreateSession: {
                        startNewChatAndReturnToChat()
                        setIOSSidebarPresented(false)
                    }
                )
                .frame(width: sidebarWidth)
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .offset(x: sidebarOffset)
            }
            .contentShape(Rectangle())
            .overlay {
                IOSGlobalPanCaptureInstaller(
                    onChanged: { recognizer in
                        handleIOSSidebarPanChanged(recognizer, width: sidebarWidth)
                    },
                    onEnded: { recognizer in
                        handleIOSSidebarPanEnded(recognizer, width: sidebarWidth)
                    }
                )
            }
            .onAppear {
                if selectedTab == .newChat || selectedTab == .setting {
                    selectedTab = .chat
                }
            }
        }
    }

    @ViewBuilder
    var iosDetailScreen: some View {
        switch selectedTab {
        case .chat, .newChat:
            chatScreen(
                showsTopToolbar: true,
                onSidebarToggle: {
                    setIOSSidebarPresented(!isIOSSidebarPresented)
                }
            )
        case .library:
            libraryScreen
        case .setting:
            chatScreen(
                showsTopToolbar: true,
                onSidebarToggle: {
                    setIOSSidebarPresented(!isIOSSidebarPresented)
                }
            )
        }
    }

    var iosSection: IOSWorkspaceSection {
        if isSettingsPresented {
            return .setting
        }
        return .chat
    }

    var iosSectionBinding: Binding<IOSWorkspaceSection> {
        Binding(
            get: { iosSection },
            set: { section in
                switch section {
                case .chat:
                    selectedTab = .chat
                case .setting:
                    presentSettingsSheet()
                    setIOSSidebarPresented(false)
                }
            }
        )
    }

    func setIOSSidebarPresented(_ isPresented: Bool) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            isIOSSidebarPresented = isPresented
            iosSidebarDragOffset = 0
        }
    }

    func iosSidebarOffsetX(width: CGFloat) -> CGFloat {
        let base: CGFloat = isIOSSidebarPresented ? 0 : -width
        return min(0, max(-width, base + iosSidebarDragOffset))
    }

    func isHorizontalSidebarPan(_ recognizer: UIPanGestureRecognizer) -> Bool {
        let translation = recognizer.translation(in: recognizer.view)
        return abs(translation.x) > abs(translation.y) * 1.1
    }

    func predictedTranslationX(for recognizer: UIPanGestureRecognizer) -> CGFloat {
        let translation = recognizer.translation(in: recognizer.view).x
        let velocity = recognizer.velocity(in: recognizer.view).x
        return translation + (velocity * 0.18)
    }

    func handleIOSSidebarPanChanged(_ recognizer: UIPanGestureRecognizer, width: CGFloat) {
        let translationX = recognizer.translation(in: recognizer.view).x

        if isIOSSidebarPresented {
            iosSidebarDragOffset = min(0, translationX)
        } else if isHorizontalSidebarPan(recognizer), translationX > 0 {
            iosSidebarDragOffset = max(0, translationX)
        }
    }

    func handleIOSSidebarPanEnded(_ recognizer: UIPanGestureRecognizer, width: CGFloat) {
        let closeSwipeThreshold = width * 0.22
        let closePredictedThreshold = width * 0.15
        let openSwipeThreshold = max(24, width * 0.12)
        let openPredictedThreshold = max(20, width * 0.09)
        let translationX = recognizer.translation(in: recognizer.view).x
        let predictedX = predictedTranslationX(for: recognizer)

        defer { iosSidebarDragOffset = 0 }

        if isIOSSidebarPresented {
            let shouldClose = predictedX < -closePredictedThreshold || translationX < -closeSwipeThreshold
            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                isIOSSidebarPresented = !shouldClose
            }
            return
        }

        let shouldOpen = isHorizontalSidebarPan(recognizer)
            && translationX > 0
            && (predictedX > openPredictedThreshold || translationX > openSwipeThreshold)
        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            isIOSSidebarPresented = shouldOpen
        }
    }
#endif

#if os(macOS)
    var macDesktopLayout: some View {
        NavigationSplitView {
            MacWorkspaceSidebarView(
                selectedSection: macSectionBinding,
                sessions: backend.sessions,
                activeSessionID: backend.activeSessionID,
                onSelectSession: { session in
                    backend.activateSession(session)
                    selectedTab = .chat
                },
                onRenameSession: backend.renameSession,
                onDeleteSession: backend.deleteSession,
                shareTextForSession: backend.shareText,
                onSelectChatWorkspace: openLaycaChatWorkspace,
                onCreateSession: startNewChatAndReturnToChat
            )
            .navigationSplitViewColumnWidth(min: 230, ideal: 280, max: 360)
        } detail: {
            macDetailScreen
                .navigationSplitViewColumnWidth(min: 524, ideal: 920)
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            if selectedTab == .newChat || selectedTab == .library || selectedTab == .setting {
                selectedTab = .chat
            }
        }
    }

    @ViewBuilder
    var macDetailScreen: some View {
        switch macSection {
        case .chat:
            macChatScreen
        case .setting:
            macChatScreen
        }
    }

    var macSection: MacWorkspaceSection {
        if isSettingsPresented {
            return .setting
        }

        switch selectedTab {
        case .chat:
            return .chat
        case .library:
            return .chat
        case .setting:
            return .chat
        case .newChat:
            return .chat
        }
    }

    var macSectionBinding: Binding<MacWorkspaceSection> {
        Binding(
            get: { macSection },
            set: { section in
                switch section {
                case .chat:
                    selectedTab = .chat
                case .setting:
                    presentSettingsSheet()
                }
            }
        )
    }

    var macChatScreen: some View {
        MacChatWorkspaceView(
            isRecording: backend.isRecording,
            isTranscriptChunkPlaying: backend.isTranscriptChunkPlaying,
            isDraftSession: backend.activeSessionID == nil,
            recordingTimeText: backend.recordingTimeText,
            transcriptChunkPlaybackRemainingText: backend.transcriptChunkPlaybackRemainingText,
            waveformBars: backend.waveformBars,
            activeSessionTitle: backend.activeSessionTitle,
            activeSessionDateText: backend.activeSessionDateText,
            transcriptChunkPlaybackRangeText: backend.transcriptChunkPlaybackRangeText,
            activePlaybackRowID: backend.activeTranscriptPlaybackRowID,
            liveChatItems: backend.activeTranscriptRows,
            selectedFocusLanguageCodes: backend.selectedLanguageCodes,
            transcribingRowIDs: backend.transcribingRowIDs,
            queuedRetranscriptionRowIDs: backend.queuedManualRetranscriptionRowIDs,
            isTranscriptionBusy: backend.isTranscriptionBusy,
            preflightMessage: backend.preflightStatusMessage,
            canPlayTranscriptChunks: !backend.isRecording,
            onRecordTap: backend.toggleRecording,
            onTranscriptTap: backend.playTranscriptChunk,
            onManualEditTranscript: backend.editTranscriptRow,
            onEditSpeakerName: backend.editSpeakerName,
            onChangeSpeaker: backend.changeSpeaker,
            onRetranscribeTranscript: { row, languageCode in
                backend.retranscribeTranscriptRow(row, preferredLanguageCodeOverride: languageCode)
            },
            canPlaySessionFromStart: backend.canPlayActiveSessionFromStart,
            onPlayFromStartTap: backend.playActiveSessionFromStart,
            onExportTap: presentExportSheet,
            onDeleteActiveSessionTap: backend.deleteActiveSession,
            onRenameSessionTitle: backend.renameActiveSessionTitle,
            onOpenSettingsTap: {
                presentSettingsSheet()
            }
        )
    }

    var macSettingScreen: some View {
        MacSettingsWorkspaceView(
            totalHours: backend.totalHours,
            usedHours: backend.usedHours,
            selectedLanguageCodes: selectedLanguageCodesBinding,
            languageSearchText: languageSearchTextBinding,
            filteredFocusLanguages: filteredFocusLanguages,
            groupedFocusLanguages: groupedFocusLanguages,
            isICloudSyncEnabled: iCloudSyncBinding,
            whisperCoreMLEncoderEnabled: whisperCoreMLEncoderBinding,
            whisperGGMLGPUDecodeEnabled: whisperGGMLGPUDecodeBinding,
            whisperModelProfile: whisperModelProfileBinding,
            mainTimerDisplayStyle: mainTimerDisplayStyleBinding,
            whisperCoreMLEncoderRecommendationText: backend.whisperCoreMLEncoderRecommendationText,
            whisperGGMLGPUDecodeRecommendationText: backend.whisperGGMLGPUDecodeRecommendationText,
            whisperModelRecommendationText: backend.whisperModelRecommendationText,
            isRestoringPurchases: backend.isRestoringPurchases,
            restoreStatusMessage: backend.restoreStatusMessage,
            onToggleLanguage: backend.toggleLanguageFocus,
            onRestorePurchases: backend.restorePurchases
        )
    }

#endif

    func chatScreen(showsTopToolbar: Bool, onSidebarToggle: (() -> Void)? = nil) -> some View {
        ChatTabView(
            isRecording: backend.isRecording,
            isTranscriptChunkPlaying: backend.isTranscriptChunkPlaying,
            recordingTimeText: backend.recordingTimeText,
            transcriptChunkPlaybackRemainingText: backend.transcriptChunkPlaybackRemainingText,
            waveformBars: backend.waveformBars,
            activeSessionTitle: backend.activeSessionTitle,
            activeSessionDateText: backend.activeSessionDateText,
            transcriptChunkPlaybackRangeText: backend.transcriptChunkPlaybackRangeText,
            activePlaybackRowID: backend.activeTranscriptPlaybackRowID,
            isDraftSession: backend.activeSessionID == nil,
            liveChatItems: backend.activeTranscriptRows,
            selectedFocusLanguageCodes: backend.selectedLanguageCodes,
            transcribingRowIDs: backend.transcribingRowIDs,
            queuedRetranscriptionRowIDs: backend.queuedManualRetranscriptionRowIDs,
            isTranscriptionBusy: backend.isTranscriptionBusy,
            preflightMessage: backend.preflightStatusMessage,
            canPlayTranscriptChunks: !backend.isRecording,
            onRecordTap: backend.toggleRecording,
            onTranscriptTap: backend.playTranscriptChunk,
            onManualEditTranscript: backend.editTranscriptRow,
            onEditSpeakerName: backend.editSpeakerName,
            onChangeSpeaker: backend.changeSpeaker,
            onRetranscribeTranscript: { row, languageCode in
                backend.retranscribeTranscriptRow(row, preferredLanguageCodeOverride: languageCode)
            },
            canPlaySessionFromStart: backend.canPlayActiveSessionFromStart,
            onPlayFromStartTap: backend.playActiveSessionFromStart,
            onExportTap: presentExportSheet,
            onDeleteActiveSessionTap: backend.deleteActiveSession,
            onRenameSessionTitle: backend.renameActiveSessionTitle,
            onSidebarToggle: onSidebarToggle,
            showsTopToolbar: showsTopToolbar,
            showsBottomRecorderAccessory: !usesMergedTabBarRecorderAccessory,
            showsMergedTabBarRecorderAccessory: usesMergedTabBarRecorderAccessory
        )
    }

    var libraryScreen: some View {
        LibraryTabView(
            sessions: backend.sessions,
            activeSessionID: backend.activeSessionID,
            onSelectSession: { session in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    backend.activateSession(session)
                    selectedTab = .chat
                }
            },
            onRenameSession: backend.renameSession,
            onDeleteSession: backend.deleteSession,
            shareTextForSession: backend.shareText
        )
    }

    var settingScreen: some View {
        SettingsTabView(
            totalHours: backend.totalHours,
            usedHours: backend.usedHours,
            selectedLanguageCodes: selectedLanguageCodesBinding,
            languageSearchText: languageSearchTextBinding,
            filteredFocusLanguages: filteredFocusLanguages,
            groupedFocusLanguages: groupedFocusLanguages,
            isICloudSyncEnabled: iCloudSyncBinding,
            whisperCoreMLEncoderEnabled: whisperCoreMLEncoderBinding,
            whisperGGMLGPUDecodeEnabled: whisperGGMLGPUDecodeBinding,
            whisperModelProfile: whisperModelProfileBinding,
            mainTimerDisplayStyle: mainTimerDisplayStyleBinding,
            whisperCoreMLEncoderRecommendationText: backend.whisperCoreMLEncoderRecommendationText,
            whisperGGMLGPUDecodeRecommendationText: backend.whisperGGMLGPUDecodeRecommendationText,
            whisperModelRecommendationText: backend.whisperModelRecommendationText,
            isRestoringPurchases: backend.isRestoringPurchases,
            restoreStatusMessage: backend.restoreStatusMessage,
            onToggleLanguage: backend.toggleLanguageFocus,
            onRestorePurchases: backend.restorePurchases
        )
    }

    @ViewBuilder
    var settingsSheetScreen: some View {
#if os(macOS)
        NavigationStack {
            macSettingScreen
        }
        .id(settingsSheetPresentationID)
        .frame(minWidth: 620, minHeight: 640)
#else
        settingScreen
            .id(settingsSheetPresentationID)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
#endif
    }

    func startNewChatAndReturnToChat() {
        backend.startNewChat()
        selectedTab = .chat
    }

    func presentSettingsSheet() {
        selectedTab = .chat
        settingsSheetPresentationID = UUID()
        isSettingsPresented = true
    }

    func presentExportSheet() {
        exportSheetPresentationID = UUID()
        isExportPresented = true
    }

    func openLaycaChatWorkspace() {
        selectedTab = .chat

        guard !backend.isRecording else {
            return
        }

        // If user is currently viewing an existing saved chat, tapping "Layca Chat"
        // returns to a fresh draft room before any new recording starts.
        if backend.activeSessionID != nil {
            backend.startNewChat()
        }
    }

    @ViewBuilder
    var exportScreen: some View {
        let snapshot = exportSessionSnapshot
        ExportSheetFlowView(
            sessionTitle: snapshot.title,
            createdAtText: snapshot.createdAtText,
            buildPayload: buildExportPayload
        )
#if os(macOS)
        .frame(minWidth: 620, minHeight: 640)
#else
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
#endif
    }

    private var exportSessionSnapshot: ExportSessionSnapshot {
        if let activeSessionID = backend.activeSessionID,
           let session = backend.sessions.first(where: { $0.id == activeSessionID }) {
            return ExportSessionSnapshot(
                title: session.title,
                createdAtText: session.formattedDate,
                rows: session.rows
            )
        }

        return ExportSessionSnapshot(
            title: backend.activeSessionTitle,
            createdAtText: backend.activeSessionDateText,
            rows: backend.activeTranscriptRows
        )
    }

    private func buildExportPayload(for format: ExportFormat) -> String {
        let snapshot = exportSessionSnapshot
        switch format {
        case .notepadMinutes:
            return buildNotepadMinutesText(snapshot: snapshot)
        case .markdown:
            return buildMarkdownText(snapshot: snapshot)
        case .plainText:
            return buildPlainTranscriptText(snapshot: snapshot)
        case .videoSubtitlesSRT:
            return buildVideoSubtitlesSRTText(snapshot: snapshot)
        }
    }

    private func buildPlainTranscriptText(snapshot: ExportSessionSnapshot) -> String {
        let lines = snapshot.rows.compactMap { row -> String? in
            let trimmed = row.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        if lines.isEmpty {
            return "No messages in this chat yet."
        }

        return lines.joined(separator: "\n\n")
    }

    private func buildNotepadMinutesText(snapshot: ExportSessionSnapshot) -> String {
        let header = [
            snapshot.title,
            "Created: \(snapshot.createdAtText)",
            "",
            ""
        ]
        .joined(separator: "\n")

        guard !snapshot.rows.isEmpty else {
            return "\(header)No messages in this chat yet."
        }

        let lines = snapshot.rows.map { row in
            "[\(row.time)] \(row.speaker) (\(row.language))\n\(row.text)"
        }
        .joined(separator: "\n\n")

        return "\(header)\(lines)"
    }

    private func buildMarkdownText(snapshot: ExportSessionSnapshot) -> String {
        var lines: [String] = [
            "# \(snapshot.title)",
            "",
            "- Created: \(snapshot.createdAtText)",
            "- Export style: Markdown",
            "",
            "## Transcript",
            ""
        ]

        if snapshot.rows.isEmpty {
            lines.append("_No messages in this chat yet._")
        } else {
            for row in snapshot.rows {
                lines.append("### [\(row.time)] \(row.speaker) (\(row.language))")
                lines.append(row.text)
                lines.append("")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func buildVideoSubtitlesSRTText(snapshot: ExportSessionSnapshot) -> String {
        guard !snapshot.rows.isEmpty else {
            return ""
        }

        let minimumCueDuration: Double = 0.8
        var cues: [String] = []
        cues.reserveCapacity(snapshot.rows.count)

        for (index, row) in snapshot.rows.enumerated() {
            let start = resolvedSRTStartSeconds(
                for: row,
                at: index,
                rows: snapshot.rows
            )
            let end = resolvedSRTEndSeconds(
                for: row,
                at: index,
                rows: snapshot.rows,
                start: start,
                minimumCueDuration: minimumCueDuration
            )
            let cueText = row.text
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !cueText.isEmpty else {
                continue
            }

            cues.append(
                [
                    "\(cues.count + 1)",
                    "\(formatSRTTimestamp(seconds: start)) --> \(formatSRTTimestamp(seconds: end))",
                    cueText
                ]
                .joined(separator: "\n")
            )
        }

        return cues.joined(separator: "\n\n")
    }

    private func resolvedSRTStartSeconds(
        for row: TranscriptRow,
        at index: Int,
        rows: [TranscriptRow]
    ) -> Double {
        if let startOffset = row.startOffset, startOffset >= 0 {
            return startOffset
        }

        if let parsed = parseHHMMSSTimestampToSeconds(row.time) {
            return parsed
        }

        guard index > 0 else {
            return 0
        }

        let previous = rows[index - 1]
        if let previousEnd = previous.endOffset, previousEnd >= 0 {
            return previousEnd
        }
        if let previousStart = previous.startOffset, previousStart >= 0 {
            return previousStart + 2
        }
        if let previousParsed = parseHHMMSSTimestampToSeconds(previous.time) {
            return previousParsed + 2
        }

        return Double(index) * 2
    }

    private func resolvedSRTEndSeconds(
        for row: TranscriptRow,
        at index: Int,
        rows: [TranscriptRow],
        start: Double,
        minimumCueDuration: Double
    ) -> Double {
        if let endOffset = row.endOffset, endOffset > start {
            return endOffset
        }

        if index + 1 < rows.count {
            let nextRow = rows[index + 1]
            let candidateNextStart = nextRow.startOffset ?? parseHHMMSSTimestampToSeconds(nextRow.time)
            if let candidateNextStart, candidateNextStart > start {
                return max(candidateNextStart, start + minimumCueDuration)
            }
        }

        return start + minimumCueDuration
    }

    private func parseHHMMSSTimestampToSeconds(_ value: String) -> Double? {
        let parts = value.split(separator: ":")
        guard parts.count == 3,
              let hours = Int(parts[0]),
              let minutes = Int(parts[1]),
              let seconds = Int(parts[2]) else {
            return nil
        }

        return Double((hours * 3600) + (minutes * 60) + seconds)
    }

    private func formatSRTTimestamp(seconds: Double) -> String {
        let clamped = max(0, seconds)
        let totalMilliseconds = Int((clamped * 1000).rounded())
        let hours = totalMilliseconds / 3_600_000
        let minutes = (totalMilliseconds % 3_600_000) / 60_000
        let secs = (totalMilliseconds % 60_000) / 1_000
        let milliseconds = totalMilliseconds % 1_000
        return String(
            format: "%02d:%02d:%02d,%03d",
            hours,
            minutes,
            secs,
            milliseconds
        )
    }

    var selectedLanguageCodesBinding: Binding<Set<String>> {
        Binding(
            get: { backend.selectedLanguageCodes },
            set: { backend.selectedLanguageCodes = $0 }
        )
    }

    var languageSearchTextBinding: Binding<String> {
        Binding(
            get: { backend.languageSearchText },
            set: { backend.languageSearchText = $0 }
        )
    }

    var focusContextKeywordsBinding: Binding<String> {
        Binding(
            get: { backend.focusContextKeywords },
            set: { backend.focusContextKeywords = $0 }
        )
    }

    var iCloudSyncBinding: Binding<Bool> {
        Binding(
            get: { backend.isICloudSyncEnabled },
            set: { backend.isICloudSyncEnabled = $0 }
        )
    }

    var whisperCoreMLEncoderBinding: Binding<Bool> {
        Binding(
            get: { backend.whisperCoreMLEncoderEnabled },
            set: { backend.whisperCoreMLEncoderEnabled = $0 }
        )
    }

    var whisperGGMLGPUDecodeBinding: Binding<Bool> {
        Binding(
            get: { backend.whisperGGMLGPUDecodeEnabled },
            set: { backend.whisperGGMLGPUDecodeEnabled = $0 }
        )
    }

    var whisperModelProfileBinding: Binding<WhisperModelProfile> {
        Binding(
            get: { backend.whisperModelProfile },
            set: { backend.whisperModelProfile = $0 }
        )
    }

    var mainTimerDisplayStyleBinding: Binding<MainTimerDisplayStyle> {
        Binding(
            get: { backend.mainTimerDisplayStyle },
            set: { backend.mainTimerDisplayStyle = $0 }
        )
    }

    var filteredFocusLanguages: [FocusLanguage] {
        let query = backend.languageSearchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if query.isEmpty {
            return FocusLanguage.all
        }

        return FocusLanguage.all.filter { language in
            language.name.lowercased().contains(query)
                || language.code.contains(query)
                || language.iso3.contains(query)
        }
    }

    var groupedFocusLanguages: [LanguageRegionGroup] {
        let filtered = filteredFocusLanguages
        return LanguageRegion.allCases.compactMap { region in
            let langs = filtered.filter { $0.region == region }
            return langs.isEmpty ? nil : LanguageRegionGroup(region: region, languages: langs)
        }
    }

    var usesMergedTabBarRecorderAccessory: Bool {
#if os(iOS)
        false
#else
        false
#endif
    }

}

#if os(iOS)
private struct IOSGlobalPanCaptureInstaller: UIViewRepresentable {
    let onChanged: (UIPanGestureRecognizer) -> Void
    let onEnded: (UIPanGestureRecognizer) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChanged: onChanged, onEnded: onEnded)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        context.coordinator.installIfNeeded(from: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        context.coordinator.installIfNeeded(from: uiView)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.removeRecognizer()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onChanged: (UIPanGestureRecognizer) -> Void
        var onEnded: (UIPanGestureRecognizer) -> Void

        private weak var attachedView: UIView?
        private var recognizer: UIPanGestureRecognizer?

        init(
            onChanged: @escaping (UIPanGestureRecognizer) -> Void,
            onEnded: @escaping (UIPanGestureRecognizer) -> Void
        ) {
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        func installIfNeeded(from hostView: UIView) {
            guard let targetView = hostView.window else {
                return
            }
            guard attachedView !== targetView else {
                return
            }

            removeRecognizer()

            let panRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            panRecognizer.cancelsTouchesInView = false
            panRecognizer.delaysTouchesBegan = false
            panRecognizer.delaysTouchesEnded = false
            panRecognizer.delegate = self

            targetView.addGestureRecognizer(panRecognizer)
            recognizer = panRecognizer
            attachedView = targetView
        }

        func removeRecognizer() {
            if let recognizer, let attachedView {
                attachedView.removeGestureRecognizer(recognizer)
            }
            recognizer = nil
            attachedView = nil
        }

        @objc
        private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            switch recognizer.state {
            case .began, .changed:
                onChanged(recognizer)
            case .ended, .cancelled, .failed:
                onEnded(recognizer)
            default:
                break
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
#endif

private enum AppTab: Hashable {
    case chat
    case setting
    case library
    case newChat
}

private struct ExportSessionSnapshot {
    let title: String
    let createdAtText: String
    let rows: [TranscriptRow]
}
