//
//  ContentView.swift
//  layca
//
//  Created by Chatthong Rimthong on 8/2/26.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedMode: SessionMode = .groupChat
    @State private var isRecording = false
    @State private var modelProgress = 0.68
    @State private var liveChatItems: [TranscriptRow] = TranscriptRow.makeDemoRows()
    @State private var noteStyle: NoteStyle = .minutes
    @State private var noteText: String = TranscriptRow.defaultNotepadText

    var body: some View {
        NavigationStack {
            ZStack {
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

                LiquidBackdrop()
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        header
                        recorderCard
                        modeCard
                        liveSegmentsCard
                        quickActionsCard
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 30)
                }
            }
            .navigationBarHidden(true)
        }
    }
}

#Preview {
    ContentView()
}

private extension ContentView {
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
                    Image(systemName: "brain.head.profile")
                    Text("Brain 68%")
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .glassCapsuleStyle()
            }

            Text("Sunday, February 8")
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

    var modeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("View Mode")
                .font(.headline)
                .foregroundStyle(.black.opacity(0.75))

            HStack(spacing: 8) {
                ForEach(SessionMode.allCases) { mode in
                    Button {
                        selectMode(mode)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: mode.icon)
                                .font(.subheadline.weight(.semibold))
                            Text(mode.title)
                                .font(.title3.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(selectedMode == mode ? .black.opacity(0.86) : .black.opacity(0.5))
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(selectedMode == mode ? .white.opacity(0.75) : .clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            selectMode(mode)
                        }
                    )
                }
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.white.opacity(0.33))
            )
        }
        .padding(18)
        .liquidCard()
    }

    var liveSegmentsCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            if selectedMode == .groupChat {
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
            } else {
                notepadSection
            }
        }
        .padding(18)
        .liquidCard()
    }

    var quickActionsCard: some View {
        HStack(spacing: 10) {
            QuickActionButton(title: "New Session", icon: "plus")
            QuickActionButton(title: "Export", icon: "square.and.arrow.up")
            QuickActionButton(title: "Models", icon: "square.stack.3d.up")
        }
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

    func selectMode(_ mode: SessionMode) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            selectedMode = mode
        }
    }

    var notepadSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Meeting Notepad")
                    .font(.headline)
                    .foregroundStyle(.black.opacity(0.75))
                Spacer()
                Label("Editable", systemImage: "square.and.pencil")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.black.opacity(0.55))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(NoteStyle.allCases) { style in
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                                noteStyle = style
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: style.icon)
                                    .font(.caption.weight(.bold))
                                Text(style.title)
                                    .font(.caption.weight(.semibold))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .foregroundStyle(noteStyle == style ? .black.opacity(0.86) : .black.opacity(0.55))
                            .background(
                                Capsule(style: .continuous)
                                    .fill(noteStyle == style ? .white.opacity(0.72) : .white.opacity(0.36))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            TextEditor(text: $noteText)
                .font(noteStyle.textFont)
                .lineSpacing(noteStyle.lineSpacing)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 210)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.white.opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(.white.opacity(0.6), lineWidth: 0.8)
                )
        }
    }
}

private struct QuickActionButton: View {
    let title: String
    let icon: String

    var body: some View {
        Button {
        } label: {
            VStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.black.opacity(0.75))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .liquidCard()
        }
        .buttonStyle(.plain)
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

private enum SessionMode: String, CaseIterable, Identifiable {
    case groupChat
    case notepad

    var id: String { rawValue }

    var title: String {
        switch self {
        case .groupChat:
            return "Group Chat"
        case .notepad:
            return "Notepad"
        }
    }

    var icon: String {
        switch self {
        case .groupChat:
            return "bubble.left.and.bubble.right.fill"
        case .notepad:
            return "square.and.pencil"
        }
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

    static func makeDemoRows() -> [TranscriptRow] {
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
                text: "Let's lock the roadmap for model download before we ship.",
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

    static var defaultNotepadText: String {
        makeDemoRows()
            .map { "\($0.time)  \($0.speaker) [\($0.language)]\n\($0.text)" }
            .joined(separator: "\n\n")
    }
}

private enum NoteStyle: String, CaseIterable, Identifiable {
    case clean
    case minutes
    case focus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clean:
            return "Clean"
        case .minutes:
            return "Minutes"
        case .focus:
            return "Focus"
        }
    }

    var icon: String {
        switch self {
        case .clean:
            return "text.justify"
        case .minutes:
            return "list.bullet.rectangle"
        case .focus:
            return "textformat.alt"
        }
    }

    var textFont: Font {
        switch self {
        case .clean:
            return .system(size: 17, weight: .regular, design: .rounded)
        case .minutes:
            return .system(size: 16, weight: .medium, design: .default)
        case .focus:
            return .system(size: 15, weight: .regular, design: .monospaced)
        }
    }

    var lineSpacing: CGFloat {
        switch self {
        case .clean:
            return 3
        case .minutes:
            return 5
        case .focus:
            return 2
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
