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

    @State private var selectedTab: AppTab = .chat
#if os(iOS)
    @State private var isIOSSidebarPresented = false
    @State private var iosSidebarDragOffset: CGFloat = 0
#endif

    var body: some View {
        rootLayout
        .sheet(isPresented: $isExportPresented) {
            exportScreen
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
        iosDrawerLayout
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

                Tab("Setting", systemImage: "square.stack.3d.up", value: AppTab.setting) {
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
                if selectedTab == .newChat {
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
            settingScreen
        }
    }

    var iosSection: IOSWorkspaceSection {
        switch selectedTab {
        case .setting:
            return .setting
        case .chat, .library, .newChat:
            return .chat
        }
    }

    var iosSectionBinding: Binding<IOSWorkspaceSection> {
        Binding(
            get: { iosSection },
            set: { section in
                switch section {
                case .chat:
                    selectedTab = .chat
                case .setting:
                    selectedTab = .setting
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
            if selectedTab == .newChat || selectedTab == .library {
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
            macSettingScreen
        }
    }

    var macSection: MacWorkspaceSection {
        switch selectedTab {
        case .chat:
            return .chat
        case .library:
            return .chat
        case .setting:
            return .setting
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
                    selectedTab = .setting
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
            onExportTap: { isExportPresented = true },
            onDeleteActiveSessionTap: backend.deleteActiveSession,
            onRenameSessionTitle: backend.renameActiveSessionTitle,
            onOpenSettingsTap: {
                selectedTab = .setting
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
            onExportTap: { isExportPresented = true },
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

    func startNewChatAndReturnToChat() {
        backend.startNewChat()
        selectedTab = .chat
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

    var exportScreen: some View {
        return NavigationStack {
            ZStack {
                exportBackground

                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Export")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("Use Notepad style during export only")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 8) {
                        ExportRow(title: "Markdown", subtitle: "Notepad Minutes preset")
                        ExportRow(title: "PDF", subtitle: "Clean sharing format")
                        ExportRow(title: "Text", subtitle: "Plain transcript")
                    }
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.regularMaterial)
                )
                .padding(.horizontal, 18)
            }
            .laycaHideNavigationBar()
        }
    }

    @ViewBuilder
    var exportBackground: some View {
#if os(macOS)
        LinearGradient(
            colors: [
                Color(red: 0.91, green: 0.94, blue: 0.98),
                Color(red: 0.95, green: 0.96, blue: 0.99),
                Color(red: 0.90, green: 0.94, blue: 0.96)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        LiquidBackdrop()
            .ignoresSafeArea()
#else
        Color(uiColor: .systemBackground)
            .ignoresSafeArea()
#endif
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
            return focusLanguages
        }

        return focusLanguages.filter { language in
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

    var focusLanguages: [FocusLanguage] {
        [
            // ── The United States, Canada, and Puerto Rico ──
            FocusLanguage(name: "English", code: "en", iso3: "eng", region: .americas, hello: "Hello"),
            FocusLanguage(name: "Hawaiian", code: "haw", iso3: "haw", region: .americas, hello: "Aloha"),

            // ── Europe ──
            FocusLanguage(name: "French", code: "fr", iso3: "fra", region: .europe, hello: "Bonjour"),
            FocusLanguage(name: "German", code: "de", iso3: "deu", region: .europe, hello: "Hallo"),
            FocusLanguage(name: "Spanish", code: "es", iso3: "spa", region: .europe, hello: "Hola"),
            FocusLanguage(name: "Italian", code: "it", iso3: "ita", region: .europe, hello: "Ciao"),
            FocusLanguage(name: "Portuguese", code: "pt", iso3: "por", region: .europe, hello: "Olá"),
            FocusLanguage(name: "Dutch", code: "nl", iso3: "nld", region: .europe, hello: "Hallo"),
            FocusLanguage(name: "Russian", code: "ru", iso3: "rus", region: .europe, hello: "Привет"),
            FocusLanguage(name: "Polish", code: "pl", iso3: "pol", region: .europe, hello: "Cześć"),
            FocusLanguage(name: "Ukrainian", code: "uk", iso3: "ukr", region: .europe, hello: "Привіт"),
            FocusLanguage(name: "Czech", code: "cs", iso3: "ces", region: .europe, hello: "Ahoj"),
            FocusLanguage(name: "Slovak", code: "sk", iso3: "slk", region: .europe, hello: "Ahoj"),
            FocusLanguage(name: "Romanian", code: "ro", iso3: "ron", region: .europe, hello: "Salut"),
            FocusLanguage(name: "Bulgarian", code: "bg", iso3: "bul", region: .europe, hello: "Здравей"),
            FocusLanguage(name: "Serbian", code: "sr", iso3: "srp", region: .europe, hello: "Здраво"),
            FocusLanguage(name: "Croatian", code: "hr", iso3: "hrv", region: .europe, hello: "Bok"),
            FocusLanguage(name: "Bosnian", code: "bs", iso3: "bos", region: .europe, hello: "Zdravo"),
            FocusLanguage(name: "Slovenian", code: "sl", iso3: "slv", region: .europe, hello: "Živjo"),
            FocusLanguage(name: "Macedonian", code: "mk", iso3: "mkd", region: .europe, hello: "Здраво"),
            FocusLanguage(name: "Albanian", code: "sq", iso3: "sqi", region: .europe, hello: "Përshëndetje"),
            FocusLanguage(name: "Greek", code: "el", iso3: "ell", region: .europe, hello: "Γεια σου"),
            FocusLanguage(name: "Hungarian", code: "hu", iso3: "hun", region: .europe, hello: "Szia"),
            FocusLanguage(name: "Lithuanian", code: "lt", iso3: "lit", region: .europe, hello: "Labas"),
            FocusLanguage(name: "Latvian", code: "lv", iso3: "lav", region: .europe, hello: "Sveiki"),
            FocusLanguage(name: "Belarusian", code: "be", iso3: "bel", region: .europe, hello: "Прывітанне"),
            FocusLanguage(name: "Swedish", code: "sv", iso3: "swe", region: .europe, hello: "Hej"),
            FocusLanguage(name: "Norwegian", code: "no", iso3: "nor", region: .europe, hello: "Hei"),
            FocusLanguage(name: "Nynorsk", code: "nn", iso3: "nno", region: .europe, hello: "Hei"),
            FocusLanguage(name: "Danish", code: "da", iso3: "dan", region: .europe, hello: "Hej"),
            FocusLanguage(name: "Finnish", code: "fi", iso3: "fin", region: .europe, hello: "Hei"),
            FocusLanguage(name: "Icelandic", code: "is", iso3: "isl", region: .europe, hello: "Halló"),
            FocusLanguage(name: "Faroese", code: "fo", iso3: "fao", region: .europe, hello: "Hey"),
            FocusLanguage(name: "Welsh", code: "cy", iso3: "cym", region: .europe, hello: "Helo"),
            FocusLanguage(name: "Breton", code: "br", iso3: "bre", region: .europe, hello: "Demat"),
            FocusLanguage(name: "Galician", code: "gl", iso3: "glg", region: .europe, hello: "Ola"),
            FocusLanguage(name: "Catalan", code: "ca", iso3: "cat", region: .europe, hello: "Hola"),
            FocusLanguage(name: "Basque", code: "eu", iso3: "eus", region: .europe, hello: "Kaixo"),
            FocusLanguage(name: "Maltese", code: "mt", iso3: "mlt", region: .europe, hello: "Bonġu"),
            FocusLanguage(name: "Luxembourgish", code: "lb", iso3: "ltz", region: .europe, hello: "Moien"),
            FocusLanguage(name: "Armenian", code: "hy", iso3: "hye", region: .europe, hello: "Բարև"),
            FocusLanguage(name: "Bashkir", code: "ba", iso3: "bak", region: .europe, hello: "Сәләм"),
            FocusLanguage(name: "Yiddish", code: "yi", iso3: "yid", region: .europe, hello: "שלום"),
            FocusLanguage(name: "Latin", code: "la", iso3: "lat", region: .europe, hello: "Salve"),

            // ── Asia Pacific ──
            FocusLanguage(name: "Chinese", code: "zh", iso3: "zho", region: .asiaPacific, hello: "你好"),
            FocusLanguage(name: "Japanese", code: "ja", iso3: "jpn", region: .asiaPacific, hello: "こんにちは"),
            FocusLanguage(name: "Korean", code: "ko", iso3: "kor", region: .asiaPacific, hello: "안녕하세요"),
            FocusLanguage(name: "Thai", code: "th", iso3: "tha", region: .asiaPacific, hello: "สวัสดี"),
            FocusLanguage(name: "Vietnamese", code: "vi", iso3: "vie", region: .asiaPacific, hello: "Xin chào"),
            FocusLanguage(name: "Indonesian", code: "id", iso3: "ind", region: .asiaPacific, hello: "Halo"),
            FocusLanguage(name: "Malay", code: "ms", iso3: "msa", region: .asiaPacific, hello: "Hai"),
            FocusLanguage(name: "Tagalog", code: "tl", iso3: "tgl", region: .asiaPacific, hello: "Kumusta"),
            FocusLanguage(name: "Javanese", code: "jv", iso3: "jav", region: .asiaPacific, hello: "Halo"),
            FocusLanguage(name: "Sundanese", code: "su", iso3: "sun", region: .asiaPacific, hello: "Halo"),
            FocusLanguage(name: "Khmer", code: "km", iso3: "khm", region: .asiaPacific, hello: "សួស្ដី"),
            FocusLanguage(name: "Lao", code: "lo", iso3: "lao", region: .asiaPacific, hello: "ສະບາຍດີ"),
            FocusLanguage(name: "Myanmar (Burmese)", code: "my", iso3: "mya", region: .asiaPacific, hello: "မင်္ဂလာပါ"),
            FocusLanguage(name: "Mongolian", code: "mn", iso3: "mon", region: .asiaPacific, hello: "Сайн уу"),
            FocusLanguage(name: "Tibetan", code: "bo", iso3: "bod", region: .asiaPacific, hello: "བཀྲ་ཤིས་བདེ་ལེགས"),
            FocusLanguage(name: "Maori", code: "mi", iso3: "mri", region: .asiaPacific, hello: "Kia ora"),
            FocusLanguage(name: "Kazakh", code: "kk", iso3: "kaz", region: .asiaPacific, hello: "Сәлем"),
            FocusLanguage(name: "Tajik", code: "tg", iso3: "tgk", region: .asiaPacific, hello: "Салом"),
            FocusLanguage(name: "Turkmen", code: "tk", iso3: "tuk", region: .asiaPacific, hello: "Salam"),

            // ── Africa, Middle East, and India ──
            FocusLanguage(name: "Arabic", code: "ar", iso3: "ara", region: .africaMiddleEastIndia, hello: "مرحبا"),
            FocusLanguage(name: "Hebrew", code: "he", iso3: "heb", region: .africaMiddleEastIndia, hello: "שלום"),
            FocusLanguage(name: "Persian", code: "fa", iso3: "fas", region: .africaMiddleEastIndia, hello: "سلام"),
            FocusLanguage(name: "Turkish", code: "tr", iso3: "tur", region: .africaMiddleEastIndia, hello: "Merhaba"),
            FocusLanguage(name: "Azerbaijani", code: "az", iso3: "aze", region: .africaMiddleEastIndia, hello: "Salam"),
            FocusLanguage(name: "Urdu", code: "ur", iso3: "urd", region: .africaMiddleEastIndia, hello: "سلام"),
            FocusLanguage(name: "Pashto", code: "ps", iso3: "pus", region: .africaMiddleEastIndia, hello: "سلام"),
            FocusLanguage(name: "Hindi", code: "hi", iso3: "hin", region: .africaMiddleEastIndia, hello: "नमस्ते"),
            FocusLanguage(name: "Bengali", code: "bn", iso3: "ben", region: .africaMiddleEastIndia, hello: "হ্যালো"),
            FocusLanguage(name: "Gujarati", code: "gu", iso3: "guj", region: .africaMiddleEastIndia, hello: "નમસ્તે"),
            FocusLanguage(name: "Kannada", code: "kn", iso3: "kan", region: .africaMiddleEastIndia, hello: "ನಮಸ್ಕಾರ"),
            FocusLanguage(name: "Tamil", code: "ta", iso3: "tam", region: .africaMiddleEastIndia, hello: "வணக்கம்"),
            FocusLanguage(name: "Telugu", code: "te", iso3: "tel", region: .africaMiddleEastIndia, hello: "నమస్కారం"),
            FocusLanguage(name: "Punjabi", code: "pa", iso3: "pan", region: .africaMiddleEastIndia, hello: "ਸਤ ਸ੍ਰੀ ਅਕਾਲ"),
            FocusLanguage(name: "Sindhi", code: "sd", iso3: "snd", region: .africaMiddleEastIndia, hello: "سلام"),
            FocusLanguage(name: "Sinhala", code: "si", iso3: "sin", region: .africaMiddleEastIndia, hello: "ආයුබෝවන්"),
            FocusLanguage(name: "Nepali", code: "ne", iso3: "nep", region: .africaMiddleEastIndia, hello: "नमस्ते"),
            FocusLanguage(name: "Sanskrit", code: "sa", iso3: "san", region: .africaMiddleEastIndia, hello: "नमस्कारः"),
            FocusLanguage(name: "Amharic", code: "am", iso3: "amh", region: .africaMiddleEastIndia, hello: "ሰላም"),
            FocusLanguage(name: "Hausa", code: "ha", iso3: "hau", region: .africaMiddleEastIndia, hello: "Sannu"),
            FocusLanguage(name: "Somali", code: "so", iso3: "som", region: .africaMiddleEastIndia, hello: "Salaan"),
            FocusLanguage(name: "Shona", code: "sn", iso3: "sna", region: .africaMiddleEastIndia, hello: "Mhoro"),
            FocusLanguage(name: "Lingala", code: "ln", iso3: "lin", region: .africaMiddleEastIndia, hello: "Mbote"),
            FocusLanguage(name: "Swahili", code: "sw", iso3: "swa", region: .africaMiddleEastIndia, hello: "Habari"),
            FocusLanguage(name: "Yoruba", code: "yo", iso3: "yor", region: .africaMiddleEastIndia, hello: "Bawo"),

            // ── Latin America and the Caribbean ──
            FocusLanguage(name: "Haitian Creole", code: "ht", iso3: "hat", region: .latinAmerica, hello: "Bonjou"),
        ]
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

private struct ExportRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
        )
    }
}
