//
//  ContentView.swift
//  layca
//
//  Created by Chatthong Rimthong on 8/2/26.
//

import SwiftUI

struct ContentView: View {
    @State private var isRecording = false
    @State private var modelProgress = 0.68
    @State private var isExportPresented = false
    @State private var liveChatItems: [TranscriptRow]
    @State private var sessions: [ChatSession]
    @State private var activeSessionID: UUID?
    @State private var chatCount: Int
    @State private var selectedTab: AppTab = .chat

    init() {
        let firstSession = ChatSession.makeDemoSession(chatNumber: 1)
        _liveChatItems = State(initialValue: firstSession.rows)
        _sessions = State(initialValue: [firstSession])
        _activeSessionID = State(initialValue: firstSession.id)
        _chatCount = State(initialValue: 1)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            TabSection {
                Tab("Chat", systemImage: "bubble.left.and.bubble.right.fill", value: AppTab.chat) {
                    chatScreen
                }

                Tab("Setting", systemImage: "square.stack.3d.up", value: AppTab.setting) {
                    settingScreen
                }

                Tab("Library", systemImage: "books.vertical.fill", value: AppTab.library) {
                    libraryScreen
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
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .newChat {
                startNewChat()
                selectedTab = .chat
            }
        }
        .sheet(isPresented: $isExportPresented) {
            exportScreen
        }
    }
}

#Preview {
    ContentView()
}

private extension ContentView {
    var chatScreen: some View {
        NavigationStack {
            ZStack {
                backgroundGradient
                LiquidBackdrop()
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        header
                        recorderCard
                        liveSegmentsCard
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 30)
                }
            }
            .navigationBarHidden(true)
        }
    }

    var exportScreen: some View {
        NavigationStack {
            ZStack {
                backgroundGradient
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
            .navigationBarHidden(true)
        }
    }

    var settingScreen: some View {
        NavigationStack {
            ZStack {
                backgroundGradient
                LiquidBackdrop()
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 14) {
                    Text("Setting")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.black.opacity(0.9))

                    HStack {
                        Text("Large v3 Turbo")
                            .font(.headline)
                        Spacer()
                        Text("\(Int(modelProgress * 100))%")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.black.opacity(0.6))
                    }

                    ProgressView(value: modelProgress)
                        .tint(.black.opacity(0.6))

                    Text("Chat remains simple. Model settings live here.")
                        .font(.subheadline)
                        .foregroundStyle(.black.opacity(0.6))
                }
                .padding(18)
                .liquidCard()
                .padding(.horizontal, 18)
            }
            .navigationBarHidden(true)
        }
    }

    var libraryScreen: some View {
        NavigationStack {
            ZStack {
                backgroundGradient
                LiquidBackdrop()
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Library")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(.black.opacity(0.9))
                        Text("Switch and load saved chat sessions")
                            .font(.subheadline)
                            .foregroundStyle(.black.opacity(0.6))
                    }

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 10) {
                            ForEach(sessions) { session in
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                                        activateSession(session)
                                        selectedTab = .chat
                                    }
                                } label: {
                                    SessionRow(
                                        session: session,
                                        isActive: session.id == activeSessionID
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(18)
                .liquidCard()
                .padding(.horizontal, 18)
            }
            .navigationBarHidden(true)
        }
    }

    var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.88, green: 0.95, blue: 1.0),
                Color(red: 0.95, green: 0.98, blue: 1.0),
                Color(red: 0.90, green: 0.96, blue: 0.95)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Layca")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.black.opacity(0.9))
                    Text("Offline meeting secretary")
                        .font(.headline)
                        .foregroundStyle(.black.opacity(0.65))
                }

                Spacer()

                HStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                    Text(activeSessionTitle)
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .glassCapsuleStyle()

                Button {
                    isExportPresented = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.plain)
                .glassCapsuleStyle()
            }

            Text(activeSessionDateText)
                .font(.subheadline)
                .foregroundStyle(.black.opacity(0.5))
        }
    }

    var recorderCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Session Ready", systemImage: "waveform.and.mic")
                    .font(.headline)
                    .foregroundStyle(.black.opacity(0.75))

                Spacer()

                Text(isRecording ? "REC" : "IDLE")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isRecording ? .red : .black.opacity(0.55))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(.white.opacity(0.65))
                    )
            }

            HStack(alignment: .bottom, spacing: 10) {
                Text(isRecording ? "00:12:42" : "00:00:00")
                    .font(.system(size: 42, weight: .semibold, design: .rounded))
                    .foregroundStyle(.black.opacity(0.86))
                    .monospacedDigit()

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        isRecording.toggle()
                    }
                } label: {
                    Image(systemName: isRecording ? "stop.fill" : "record.circle.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(isRecording ? .black.opacity(0.82) : .red)
                        .frame(width: 60, height: 60)
                        .background(
                            Circle()
                                .fill(.white.opacity(0.72))
                        )
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Large v3 Turbo")
                    Spacer()
                    Text("\(Int(modelProgress * 100))%")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.black.opacity(0.55))

                ProgressView(value: modelProgress)
                    .tint(.black.opacity(0.5))
                    .progressViewStyle(.linear)
            }
        }
        .padding(18)
        .liquidCard()
    }

    var liveSegmentsCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("Latest Transcript")
                    .font(.headline)
                    .foregroundStyle(.black.opacity(0.75))
                Spacer()
                Label("Live", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.black.opacity(0.55))
            }

            ForEach(liveChatItems) { item in
                HStack(alignment: .top, spacing: 10) {
                    avatarView(for: item)
                    messageBubble(for: item)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(18)
        .liquidCard()
    }

    func startNewChat() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            chatCount += 1
            let newSession = ChatSession.makeDemoSession(chatNumber: chatCount)
            sessions.insert(newSession, at: 0)
            activateSession(newSession)
        }
    }

    func activateSession(_ session: ChatSession) {
        activeSessionID = session.id
        liveChatItems = session.rows
    }

    var activeSessionTitle: String {
        sessions.first(where: { $0.id == activeSessionID })?.title ?? "Chat"
    }

    var activeSessionDateText: String {
        sessions.first(where: { $0.id == activeSessionID })?.formattedDate ?? "No active chat"
    }

    func avatarView(for item: TranscriptRow) -> some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: item.avatarPalette,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(systemName: item.avatarSymbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
        }
        .frame(width: 34, height: 34)
        .overlay(
            Circle()
                .stroke(.white.opacity(0.6), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.12), radius: 7, x: 0, y: 4)
    }

    func messageBubble(for item: TranscriptRow) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                speakerMeta(for: item)
                Spacer(minLength: 8)
                timestampView(for: item)
            }

            Text(item.text)
                .font(.body)
                .foregroundStyle(.black.opacity(0.82))
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(0.50))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.55), lineWidth: 0.8)
        )
    }

    func speakerMeta(for item: TranscriptRow) -> some View {
        HStack(spacing: 6) {
            Text(item.speaker)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.black.opacity(0.60))
            HStack(spacing: 3) {
                Image(systemName: "globe")
                    .font(.caption2.weight(.bold))
                Text(item.language)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.black.opacity(0.45))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(.white.opacity(0.52))
            )
        }
    }

    func timestampView(for item: TranscriptRow) -> some View {
        Text(item.time)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.black.opacity(0.43))
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

private struct SessionRow: View {
    let session: ChatSession
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isActive ? Color.cyan.opacity(0.95) : Color.white.opacity(0.66))
                Image(systemName: isActive ? "checkmark.bubble.fill" : "bubble.left.and.bubble.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isActive ? .white : .black.opacity(0.62))
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.headline)
                    .foregroundStyle(.black.opacity(0.82))
                Text(session.formattedDate)
                    .font(.caption)
                    .foregroundStyle(.black.opacity(0.58))
            }

            Spacer()

            Text("\(session.rows.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.black.opacity(0.55))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(.white.opacity(0.58))
                )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isActive ? .white.opacity(0.68) : .white.opacity(0.50))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.60), lineWidth: 0.8)
        )
    }
}

private struct LiquidBackdrop: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.cyan.opacity(0.35))
                .frame(width: 260, height: 260)
                .blur(radius: 36)
                .offset(x: -110, y: -250)

            Circle()
                .fill(Color.blue.opacity(0.25))
                .frame(width: 220, height: 220)
                .blur(radius: 40)
                .offset(x: 130, y: -160)

            Circle()
                .fill(Color.mint.opacity(0.28))
                .frame(width: 280, height: 280)
                .blur(radius: 55)
                .offset(x: 120, y: 380)
        }
    }
}

private struct ChatSession: Identifiable {
    let id: UUID
    let title: String
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

private struct TranscriptRow: Identifiable {
    let id = UUID()
    let speaker: String
    let text: String
    let time: String
    let language: String
    let avatarSymbol: String
    let avatarPalette: [Color]

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
                text: "Chat \(chatNumber): Let's lock the roadmap for model download before we ship.",
                time: "00:04:32",
                language: "EN"
            ),
            BaseMessage(
                speaker: "Speaker B",
                text: "Agreed. Keep install optional and show clear storage impact.",
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
                speaker: message.speaker,
                text: message.text,
                time: message.time,
                language: message.language,
                avatarSymbol: avatar.0,
                avatarPalette: avatar.1
            )
        }
    }
}

private extension View {
    func liquidCard() -> some View {
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
    }

    func glassCapsuleStyle() -> some View {
        self
            .background(.ultraThinMaterial, in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(.white.opacity(0.55), lineWidth: 0.9)
                    .allowsHitTesting(false)
            )
            .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 6)
    }
}
