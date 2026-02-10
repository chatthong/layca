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
    @State private var isMacRenameSheetPresented = false
    @State private var macRenameDraft = ""

    var body: some View {
        rootLayout
        .sheet(isPresented: $isExportPresented) {
            exportScreen
        }
#if os(macOS)
        .sheet(isPresented: $isMacRenameSheetPresented) {
            macRenameSheet
        }
#endif
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
                Tab("Chat", systemImage: "bubble.left.and.bubble.right.fill", value: AppTab.chat) {
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
        .tint(.black.opacity(0.88))
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
                onCreateSession: startNewChatAndReturnToChat
            )
            .navigationSplitViewColumnWidth(min: 230, ideal: 280, max: 360)
        } detail: {
            macDetailScreen
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Workspace", selection: macSectionBinding) {
                    Text("Chat").tag(MacWorkspaceSection.chat)
                    Text("Library").tag(MacWorkspaceSection.library)
                    Text("Setting").tag(MacWorkspaceSection.setting)
                }
                .pickerStyle(.segmented)
                .frame(width: 290)
            }

            ToolbarItemGroup(placement: .primaryAction) {
                ControlGroup {
                    Button {
                        beginMacRename()
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }

                    Button {
                        isExportPresented = true
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        startNewChatAndReturnToChat()
                    } label: {
                        Label("New Chat", systemImage: "plus.bubble")
                    }
                }
                .controlSize(.regular)
            }
        }
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
            transcribingRowIDs: backend.transcribingRowIDs,
            isTranscriptionBusy: backend.isTranscriptionBusy,
            preflightMessage: backend.preflightStatusMessage,
            canPlayTranscriptChunks: !backend.isRecording,
            onRecordTap: backend.toggleRecording,
            onTranscriptTap: backend.playTranscriptChunk,
            onManualEditTranscript: backend.editTranscriptRow,
            onEditSpeakerName: backend.editSpeakerName,
            onChangeSpeaker: backend.changeSpeaker,
            onRetranscribeTranscript: backend.retranscribeTranscriptRow,
            onExportTap: { isExportPresented = true },
            onRenameSessionTitle: beginMacRename
        )
    }

    var macLibraryScreen: some View {
        MacLibraryWorkspaceView(
            sessions: backend.sessions,
            activeSessionID: backend.activeSessionID,
            onSelectSession: { session in
                backend.activateSession(session)
                selectedTab = .chat
            }
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
            isRestoringPurchases: backend.isRestoringPurchases,
            restoreStatusMessage: backend.restoreStatusMessage,
            onToggleLanguage: backend.toggleLanguageFocus,
            onRestorePurchases: backend.restorePurchases
        )
    }

    var macRenameSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename Active Chat")
                .font(.title3.weight(.semibold))
            TextField("Chat name", text: $macRenameDraft)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    commitMacRename()
                }

            HStack {
                Spacer()
                Button("Cancel") {
                    isMacRenameSheetPresented = false
                }
                Button("Save") {
                    commitMacRename()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(macRenameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
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
            transcribingRowIDs: backend.transcribingRowIDs,
            isTranscriptionBusy: backend.isTranscriptionBusy,
            preflightMessage: backend.preflightStatusMessage,
            canPlayTranscriptChunks: !backend.isRecording,
            onRecordTap: backend.toggleRecording,
            onTranscriptTap: backend.playTranscriptChunk,
            onManualEditTranscript: backend.editTranscriptRow,
            onEditSpeakerName: backend.editSpeakerName,
            onChangeSpeaker: backend.changeSpeaker,
            onRetranscribeTranscript: backend.retranscribeTranscriptRow,
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
            }
        )
    }

    var settingScreen: some View {
        SettingTabView(
            totalHours: backend.totalHours,
            usedHours: backend.usedHours,
            selectedLanguageCodes: selectedLanguageCodesBinding,
            languageSearchText: languageSearchTextBinding,
            focusContextKeywords: focusContextKeywordsBinding,
            filteredFocusLanguages: filteredFocusLanguages,
            isICloudSyncEnabled: iCloudSyncBinding,
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

#if os(macOS)
    func beginMacRename() {
        macRenameDraft = backend.activeSessionTitle
        isMacRenameSheetPresented = true
    }

    func commitMacRename() {
        let trimmed = macRenameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        backend.renameActiveSessionTitle(trimmed)
        isMacRenameSheetPresented = false
    }
#endif

    var exportScreen: some View {
        let gradientColors: [Color]
#if os(macOS)
        gradientColors = [
            Color(red: 0.91, green: 0.94, blue: 0.98),
            Color(red: 0.95, green: 0.96, blue: 0.99),
            Color(red: 0.90, green: 0.94, blue: 0.96)
        ]
#else
        gradientColors = [
            Color(red: 0.88, green: 0.95, blue: 1.0),
            Color(red: 0.95, green: 0.98, blue: 1.0),
            Color(red: 0.90, green: 0.96, blue: 0.95)
        ]
#endif

        return NavigationStack {
            ZStack {
                LinearGradient(
                    colors: gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                LiquidBackdrop()
                    .ignoresSafeArea()

                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Export")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(.black.opacity(0.9))
                        Text("Use Notepad style during export only")
                            .font(.subheadline)
                            .foregroundStyle(.black.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 8) {
                        ExportRow(title: "Markdown", subtitle: "Notepad Minutes preset")
                        ExportRow(title: "PDF", subtitle: "Clean sharing format")
                        ExportRow(title: "Text", subtitle: "Plain transcript")
                    }
                }
                .padding(18)
                .liquidCard()
                .padding(.horizontal, 18)
            }
            .laycaHideNavigationBar()
        }
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
                    .foregroundStyle(.black.opacity(0.82))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.black.opacity(0.6))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.black.opacity(0.45))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.52))
        )
    }
}

struct FocusLanguage: Identifiable {
    let name: String
    let code: String
    let iso3: String

    var id: String { code }
}

struct LiquidBackdrop: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.cyan.opacity(laycaDesktopOptimized ? 0.18 : 0.35))
                .frame(
                    width: laycaDesktopOptimized ? 340 : 260,
                    height: laycaDesktopOptimized ? 340 : 260
                )
                .blur(radius: laycaDesktopOptimized ? 54 : 36)
                .offset(x: -110, y: -250)

            Circle()
                .fill(Color.blue.opacity(laycaDesktopOptimized ? 0.16 : 0.25))
                .frame(
                    width: laycaDesktopOptimized ? 280 : 220,
                    height: laycaDesktopOptimized ? 280 : 220
                )
                .blur(radius: laycaDesktopOptimized ? 56 : 40)
                .offset(x: 130, y: -160)

            Circle()
                .fill(Color.mint.opacity(laycaDesktopOptimized ? 0.16 : 0.28))
                .frame(
                    width: laycaDesktopOptimized ? 360 : 280,
                    height: laycaDesktopOptimized ? 360 : 280
                )
                .blur(radius: laycaDesktopOptimized ? 68 : 55)
                .offset(x: 120, y: 380)
        }
    }

    private var laycaDesktopOptimized: Bool {
#if os(macOS)
        true
#else
        false
#endif
    }
}

struct ChatSession: Identifiable {
    let id: UUID
    var title: String
    let createdAt: Date
    let rows: [TranscriptRow]

    var formattedDate: String {
        createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    static func makeDemoSession(chatNumber: Int) -> ChatSession {
        ChatSession(
            id: UUID(),
            title: "Chat \(chatNumber)",
            createdAt: Date(),
            rows: TranscriptRow.makeDemoRows(chatNumber: chatNumber)
        )
    }
}

struct TranscriptRow: Identifiable {
    let id: UUID
    let speakerID: String
    let speaker: String
    let text: String
    let time: String
    let language: String
    let avatarSymbol: String
    let avatarPalette: [Color]
    let startOffset: Double?
    let endOffset: Double?

    nonisolated init(
        id: UUID = UUID(),
        speakerID: String,
        speaker: String,
        text: String,
        time: String,
        language: String,
        avatarSymbol: String,
        avatarPalette: [Color],
        startOffset: Double?,
        endOffset: Double?
    ) {
        self.id = id
        self.speakerID = speakerID
        self.speaker = speaker
        self.text = text
        self.time = time
        self.language = language
        self.avatarSymbol = avatarSymbol
        self.avatarPalette = avatarPalette
        self.startOffset = startOffset
        self.endOffset = endOffset
    }

    static func makeDemoRows(chatNumber: Int) -> [TranscriptRow] {
        struct BaseMessage {
            let speaker: String
            let text: String
            let time: String
            let language: String
        }

        let avatarSymbols = [
            "person.fill",
            "person.2.fill",
            "person.crop.circle.fill.badge.checkmark",
            "person.crop.circle.badge.clock",
            "person.crop.circle.badge.questionmark"
        ]
        let avatarPalettes: [[Color]] = [
            [.blue, .cyan],
            [.teal, .mint],
            [.indigo, .blue],
            [.orange, .pink],
            [.purple, .indigo]
        ]

        let baseMessages: [BaseMessage] = [
            BaseMessage(
                speaker: "Speaker A",
                text: "Chat \(chatNumber): Let's lock the roadmap and keep settings focused.",
                time: "00:04:32",
                language: "EN"
            ),
            BaseMessage(
                speaker: "Speaker B",
                text: "Agreed. Then we can add VAD controls in the next pass.",
                time: "00:04:47",
                language: "TH"
            ),
            BaseMessage(
                speaker: "Speaker A",
                text: "I'll finalize the checklist and send a clean summary tonight.",
                time: "00:05:03",
                language: "EN"
            )
        ]

        var speakerAvatars: [String: (String, [Color])] = [:]

        func avatarForSpeaker(_ speaker: String) -> (String, [Color]) {
            if let existing = speakerAvatars[speaker] {
                return existing
            }
            let symbol = avatarSymbols.randomElement() ?? "person.fill"
            let palette = avatarPalettes.randomElement() ?? [.blue, .cyan]
            let generated = (symbol, palette)
            speakerAvatars[speaker] = generated
            return generated
        }

        return baseMessages.map { message in
            let avatar = avatarForSpeaker(message.speaker)
            return TranscriptRow(
                speakerID: message.speaker,
                speaker: message.speaker,
                text: message.text,
                time: message.time,
                language: message.language,
                avatarSymbol: avatar.0,
                avatarPalette: avatar.1,
                startOffset: nil,
                endOffset: nil
            )
        }
    }
}

extension View {
    func liquidCard() -> some View {
#if os(macOS)
        self
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.regularMaterial)
                    .allowsHitTesting(false)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.36), lineWidth: 0.7)
                    .allowsHitTesting(false)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.16), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .allowsHitTesting(false)
            )
            .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 6)
#else
        self
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .allowsHitTesting(false)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.55), lineWidth: 0.9)
                    .allowsHitTesting(false)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.26), .white.opacity(0.03)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .allowsHitTesting(false)
            )
            .shadow(color: .black.opacity(0.08), radius: 20, x: 0, y: 14)
#endif
    }

    func glassCapsuleStyle() -> some View {
#if os(macOS)
        self
            .background(.regularMaterial, in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(.white.opacity(0.36), lineWidth: 0.75)
                    .allowsHitTesting(false)
            )
            .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
#else
        self
            .background(.ultraThinMaterial, in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(.white.opacity(0.55), lineWidth: 0.9)
                    .allowsHitTesting(false)
            )
            .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 6)
#endif
    }
}
