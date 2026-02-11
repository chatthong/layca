//
//  ContentView.swift
//  layca
//
//  Created by Chatthong Rimthong on 8/2/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var backend = AppBackend()
    @State private var isExportPresented = false

    @State private var selectedTab: AppTab = .chat

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
#else
        mobileTabLayout
#endif
    }

    var mobileTabLayout: some View {
        TabView(selection: $selectedTab) {
            TabSection {
                Tab("Layca Chat", systemImage: "bubble.left.and.bubble.right.fill", value: AppTab.chat) {
                    chatScreen(showsTopToolbar: true)
                }

                Tab("Library", systemImage: "books.vertical.fill", value: AppTab.library) {
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
    }

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
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            if selectedTab == .newChat {
                selectedTab = .chat
            }
        }
    }

    @ViewBuilder
    var macDetailScreen: some View {
        switch macSection {
        case .chat:
            macChatScreen
        case .library:
            macLibraryScreen
        case .setting:
            macSettingScreen
        }
    }

    var macSection: MacWorkspaceSection {
        switch selectedTab {
        case .chat:
            return .chat
        case .library:
            return .library
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
                case .library:
                    selectedTab = .library
                case .setting:
                    selectedTab = .setting
                }
            }
        )
    }

    var macChatScreen: some View {
        MacChatWorkspaceView(
            isRecording: backend.isRecording,
            recordingTimeText: backend.recordingTimeText,
            waveformBars: backend.waveformBars,
            activeSessionTitle: backend.activeSessionTitle,
            activeSessionDateText: backend.activeSessionDateText,
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
            onExportTap: { isExportPresented = true },
            onRenameSessionTitle: backend.renameActiveSessionTitle,
            onNewChatTap: startNewChatAndReturnToChat,
            onOpenSettingsTap: {
                selectedTab = .setting
            }
        )
    }

    var macLibraryScreen: some View {
        MacLibraryWorkspaceView(
            sessions: backend.sessions,
            activeSessionID: backend.activeSessionID,
            onSelectSession: { session in
                backend.activateSession(session)
                selectedTab = .chat
            },
            onRenameSession: backend.renameSession,
            onDeleteSession: backend.deleteSession,
            shareTextForSession: backend.shareText
        )
    }

    var macSettingScreen: some View {
        MacSettingsWorkspaceView(
            totalHours: backend.totalHours,
            usedHours: backend.usedHours,
            selectedLanguageCodes: selectedLanguageCodesBinding,
            languageSearchText: languageSearchTextBinding,
            focusContextKeywords: focusContextKeywordsBinding,
            filteredFocusLanguages: filteredFocusLanguages,
            isICloudSyncEnabled: iCloudSyncBinding,
            whisperCoreMLEncoderEnabled: whisperCoreMLEncoderBinding,
            whisperGGMLGPUDecodeEnabled: whisperGGMLGPUDecodeBinding,
            whisperModelProfile: whisperModelProfileBinding,
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

    func chatScreen(showsTopToolbar: Bool) -> some View {
        ChatTabView(
            isRecording: backend.isRecording,
            recordingTimeText: backend.recordingTimeText,
            waveformBars: backend.waveformBars,
            activeSessionTitle: backend.activeSessionTitle,
            activeSessionDateText: backend.activeSessionDateText,
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
            onExportTap: { isExportPresented = true },
            onRenameSessionTitle: backend.renameActiveSessionTitle,
            showsTopToolbar: showsTopToolbar
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
            focusContextKeywords: focusContextKeywordsBinding,
            filteredFocusLanguages: filteredFocusLanguages,
            isICloudSyncEnabled: iCloudSyncBinding,
            whisperCoreMLEncoderEnabled: whisperCoreMLEncoderBinding,
            whisperGGMLGPUDecodeEnabled: whisperGGMLGPUDecodeBinding,
            whisperModelProfile: whisperModelProfileBinding,
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

    var focusLanguages: [FocusLanguage] {
        [
            FocusLanguage(name: "Russian", code: "ru", iso3: "rus"),
            FocusLanguage(name: "Polish", code: "pl", iso3: "pol"),
            FocusLanguage(name: "Sindhi", code: "sd", iso3: "snd"),
            FocusLanguage(name: "Javanese", code: "jv", iso3: "jav"),
            FocusLanguage(name: "Spanish", code: "es", iso3: "spa"),
            FocusLanguage(name: "Slovak", code: "sk", iso3: "slk"),
            FocusLanguage(name: "Romanian", code: "ro", iso3: "ron"),
            FocusLanguage(name: "Portuguese", code: "pt", iso3: "por"),
            FocusLanguage(name: "Nynorsk", code: "nn", iso3: "nno"),
            FocusLanguage(name: "Norwegian", code: "no", iso3: "nor"),
            FocusLanguage(name: "Lithuanian", code: "lt", iso3: "lit"),
            FocusLanguage(name: "Galician", code: "gl", iso3: "glg"),
            FocusLanguage(name: "Swedish", code: "sv", iso3: "swe"),
            FocusLanguage(name: "English", code: "en", iso3: "eng"),
            FocusLanguage(name: "Italian", code: "it", iso3: "ita"),
            FocusLanguage(name: "Hebrew", code: "he", iso3: "heb"),
            FocusLanguage(name: "French", code: "fr", iso3: "fra"),
            FocusLanguage(name: "Bulgarian", code: "bg", iso3: "bul"),
            FocusLanguage(name: "Japanese", code: "ja", iso3: "jpn"),
            FocusLanguage(name: "Indonesian", code: "id", iso3: "ind"),
            FocusLanguage(name: "Azerbaijani", code: "az", iso3: "aze"),
            FocusLanguage(name: "Ukrainian", code: "uk", iso3: "ukr"),
            FocusLanguage(name: "Serbian", code: "sr", iso3: "srp"),
            FocusLanguage(name: "Malay", code: "ms", iso3: "msa"),
            FocusLanguage(name: "Macedonian", code: "mk", iso3: "mkd"),
            FocusLanguage(name: "Korean", code: "ko", iso3: "kor"),
            FocusLanguage(name: "Bengali", code: "bn", iso3: "ben"),
            FocusLanguage(name: "Arabic", code: "ar", iso3: "ara"),
            FocusLanguage(name: "German", code: "de", iso3: "deu"),
            FocusLanguage(name: "Dutch", code: "nl", iso3: "nld"),
            FocusLanguage(name: "Vietnamese", code: "vi", iso3: "vie"),
            FocusLanguage(name: "Turkish", code: "tr", iso3: "tur"),
            FocusLanguage(name: "Thai", code: "th", iso3: "tha"),
            FocusLanguage(name: "Slovenian", code: "sl", iso3: "slv"),
            FocusLanguage(name: "Hungarian", code: "hu", iso3: "hun"),
            FocusLanguage(name: "Finnish", code: "fi", iso3: "fin"),
            FocusLanguage(name: "Welsh", code: "cy", iso3: "cym"),
            FocusLanguage(name: "Tagalog", code: "tl", iso3: "tgl"),
            FocusLanguage(name: "Bashkir", code: "ba", iso3: "bak"),
            FocusLanguage(name: "Icelandic", code: "is", iso3: "isl"),
            FocusLanguage(name: "Bosnian", code: "bs", iso3: "bos"),
            FocusLanguage(name: "Urdu", code: "ur", iso3: "urd"),
            FocusLanguage(name: "Turkmen", code: "tk", iso3: "tuk"),
            FocusLanguage(name: "Telugu", code: "te", iso3: "tel"),
            FocusLanguage(name: "Shona", code: "sn", iso3: "sna"),
            FocusLanguage(name: "Persian", code: "fa", iso3: "fas"),
            FocusLanguage(name: "Maori", code: "mi", iso3: "mri"),
            FocusLanguage(name: "Latin", code: "la", iso3: "lat"),
            FocusLanguage(name: "Lao", code: "lo", iso3: "lao"),
            FocusLanguage(name: "Kazakh", code: "kk", iso3: "kaz"),
            FocusLanguage(name: "Greek", code: "el", iso3: "ell"),
            FocusLanguage(name: "Tamil", code: "ta", iso3: "tam"),
            FocusLanguage(name: "Punjabi", code: "pa", iso3: "pan"),
            FocusLanguage(name: "Luxembourgish", code: "lb", iso3: "ltz"),
            FocusLanguage(name: "Danish", code: "da", iso3: "dan"),
            FocusLanguage(name: "Croatian", code: "hr", iso3: "hrv"),
            FocusLanguage(name: "Catalan", code: "ca", iso3: "cat"),
            FocusLanguage(name: "Armenian", code: "hy", iso3: "hye"),
            FocusLanguage(name: "Albanian", code: "sq", iso3: "sqi"),
            FocusLanguage(name: "Chinese", code: "zh", iso3: "zho"),
            FocusLanguage(name: "Belarusian", code: "be", iso3: "bel"),
            FocusLanguage(name: "Tibetan", code: "bo", iso3: "bod"),
            FocusLanguage(name: "Khmer", code: "km", iso3: "khm"),
            FocusLanguage(name: "Kannada", code: "kn", iso3: "kan"),
            FocusLanguage(name: "Hawaiian", code: "haw", iso3: "haw"),
            FocusLanguage(name: "Yiddish", code: "yi", iso3: "yid"),
            FocusLanguage(name: "Tajik", code: "tg", iso3: "tgk"),
            FocusLanguage(name: "Sundanese", code: "su", iso3: "sun"),
            FocusLanguage(name: "Somali", code: "so", iso3: "som"),
            FocusLanguage(name: "Sinhala", code: "si", iso3: "sin"),
            FocusLanguage(name: "Sanskrit", code: "sa", iso3: "san"),
            FocusLanguage(name: "Pashto", code: "ps", iso3: "pus"),
            FocusLanguage(name: "Myanmar (Burmese)", code: "my", iso3: "mya"),
            FocusLanguage(name: "Mongolian", code: "mn", iso3: "mon"),
            FocusLanguage(name: "Maltese", code: "mt", iso3: "mlt"),
            FocusLanguage(name: "Lingala", code: "ln", iso3: "lin"),
            FocusLanguage(name: "Latvian", code: "lv", iso3: "lav"),
            FocusLanguage(name: "Hausa", code: "ha", iso3: "hau"),
            FocusLanguage(name: "Haitian Creole", code: "ht", iso3: "hat"),
            FocusLanguage(name: "Gujarati", code: "gu", iso3: "guj"),
            FocusLanguage(name: "Faroese", code: "fo", iso3: "fao"),
            FocusLanguage(name: "Breton", code: "br", iso3: "bre"),
            FocusLanguage(name: "Basque", code: "eu", iso3: "eus"),
            FocusLanguage(name: "Amharic", code: "am", iso3: "amh"),
            FocusLanguage(name: "Nepali", code: "ne", iso3: "nep"),
            FocusLanguage(name: "Czech", code: "cs", iso3: "ces")
        ]
    }
}

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
