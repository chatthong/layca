import SwiftUI

struct ChatTabView: View {
    let isRecording: Bool
    let recordingTimeText: String
    let waveformBars: [Double]

    let activeSessionTitle: String
    let activeSessionDateText: String
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
    let onExportTap: () -> Void
    let onRenameSessionTitle: (String) -> Void
    let showsTopToolbar: Bool

    @State private var titleDraft = ""
    @State private var isEditingTitle = false
    @FocusState private var isTitleFieldFocused: Bool
    @State private var isUserNearBottom = true
    @State private var hasPendingNewMessage = false
    @State private var scrollViewportHeight: CGFloat = 0
    @State private var scrollContentBottom: CGFloat = 0

    private let transcriptScrollSpace = "layca.chat.transcript.scroll"
    private let transcriptBottomAnchorID = "layca.chat.transcript.bottom"
    private let transcriptBottomTolerance: CGFloat = 78

    init(
        isRecording: Bool,
        recordingTimeText: String,
        waveformBars: [Double],
        activeSessionTitle: String,
        activeSessionDateText: String,
        liveChatItems: [TranscriptRow],
        selectedFocusLanguageCodes: Set<String>,
        transcribingRowIDs: Set<UUID>,
        queuedRetranscriptionRowIDs: Set<UUID>,
        isTranscriptionBusy: Bool,
        preflightMessage: String?,
        canPlayTranscriptChunks: Bool,
        onRecordTap: @escaping () -> Void,
        onTranscriptTap: @escaping (TranscriptRow) -> Void,
        onManualEditTranscript: @escaping (TranscriptRow, String) -> Void,
        onEditSpeakerName: @escaping (TranscriptRow, String) -> Void,
        onChangeSpeaker: @escaping (TranscriptRow, String) -> Void,
        onRetranscribeTranscript: @escaping (TranscriptRow, String?) -> Void,
        onExportTap: @escaping () -> Void,
        onRenameSessionTitle: @escaping (String) -> Void,
        showsTopToolbar: Bool = true
    ) {
        self.isRecording = isRecording
        self.recordingTimeText = recordingTimeText
        self.waveformBars = waveformBars
        self.activeSessionTitle = activeSessionTitle
        self.activeSessionDateText = activeSessionDateText
        self.liveChatItems = liveChatItems
        self.selectedFocusLanguageCodes = selectedFocusLanguageCodes
        self.transcribingRowIDs = transcribingRowIDs
        self.queuedRetranscriptionRowIDs = queuedRetranscriptionRowIDs
        self.isTranscriptionBusy = isTranscriptionBusy
        self.preflightMessage = preflightMessage
        self.canPlayTranscriptChunks = canPlayTranscriptChunks
        self.onRecordTap = onRecordTap
        self.onTranscriptTap = onTranscriptTap
        self.onManualEditTranscript = onManualEditTranscript
        self.onEditSpeakerName = onEditSpeakerName
        self.onChangeSpeaker = onChangeSpeaker
        self.onRetranscribeTranscript = onRetranscribeTranscript
        self.onExportTap = onExportTap
        self.onRenameSessionTitle = onRenameSessionTitle
        self.showsTopToolbar = showsTopToolbar
    }

    var body: some View {
        NavigationStack {
#if os(macOS)
            Group {
                if showsTopToolbar {
                    chatContent
                        .safeAreaInset(edge: .top, spacing: 0) {
                            topToolbar
                                .padding(.horizontal, 18)
                                .padding(.top, 6)
                                .padding(.bottom, 10)
                        }
                } else {
                    chatContent
                }
            }
#else
            chatContent
                .toolbar {
                    if showsTopToolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            sessionTitleControl
                                .fixedSize()
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(action: onExportTap) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
#endif
        }
        .onAppear {
            titleDraft = activeSessionTitle
        }
        .onChange(of: activeSessionTitle) { _, newTitle in
            if !isEditingTitle {
                titleDraft = newTitle
            }
        }
    }

    private var chatContent: some View {
#if os(macOS)
        chatContentBody
            .laycaHideNavigationBar()
#else
        chatContentBody
            .safeAreaInset(edge: .bottom, spacing: 0) {
                recorderTabBarAccessory
            }
#endif
    }

    private var chatContentBody: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    backgroundFill

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 18) {
#if os(macOS)
                            recorderCard
#endif
                            liveSegmentsCard
                            transcriptBottomMarker
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 10)
                        .padding(.bottom, 24)
                    }
                    .coordinateSpace(name: transcriptScrollSpace)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: ChatTranscriptViewportHeightPreferenceKey.self,
                                value: proxy.size.height
                            )
                        }
                    )
                }

                if hasPendingNewMessage && !isUserNearBottom {
                    newMessageButton {
                        scrollToTranscriptBottom(using: proxy, animated: true)
                        hasPendingNewMessage = false
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, floatingButtonBottomPadding)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.18), value: hasPendingNewMessage && !isUserNearBottom)
            .onAppear {
                DispatchQueue.main.async {
                    scrollToTranscriptBottom(using: proxy, animated: false)
                }
            }
            .onChange(of: transcriptUpdateSignature) { _, _ in
                handleTranscriptUpdate(using: proxy)
            }
            .onChange(of: isUserNearBottom) { _, nearBottom in
                if nearBottom {
                    hasPendingNewMessage = false
                }
            }
            .onPreferenceChange(ChatTranscriptViewportHeightPreferenceKey.self) { height in
                scrollViewportHeight = height
                refreshBottomTracking()
            }
            .onPreferenceChange(ChatTranscriptContentBottomPreferenceKey.self) { bottom in
                scrollContentBottom = bottom
                refreshBottomTracking()
            }
        }
    }

    @ViewBuilder
    private var backgroundFill: some View {
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
#else
        Color(uiColor: .systemBackground)
            .ignoresSafeArea()
#endif
    }

    private var topToolbar: some View {
        HStack {
            sessionTitleControl

            Spacer()

            Button(action: onExportTap) {
                Image(systemName: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(
                Circle()
                    .stroke(.primary.opacity(0.14), lineWidth: 0.9)
            )
            .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 6)
        }
    }

    private var sessionTitleControl: some View {
        Group {
            if isEditingTitle {
                HStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)

                    TextField("Chat name", text: $titleDraft)
                        .textFieldStyle(.plain)
                        .font(.subheadline.weight(.semibold))
                        .submitLabel(.done)
                        .focused($isTitleFieldFocused)
                        .onSubmit {
                            commitTitleRename()
                        }

                    Button(action: commitTitleRename) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green.opacity(0.9))
                    }
                    .buttonStyle(.plain)

                    Button(action: cancelTitleRename) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
#if os(macOS)
                .background(.thinMaterial, in: Capsule(style: .continuous))
#endif
            } else {
                Button(action: beginTitleRename) {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text(activeSessionTitle)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
#if os(macOS)
                    .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                    .contentShape(Capsule(style: .continuous))
#endif
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
        .font(.subheadline)
    }

    struct ScaleButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
                .opacity(configuration.isPressed ? 0.8 : 1.0)
        }
    }

#if !os(macOS)
    private var recorderTabBarAccessory: some View {
        VStack(spacing: 6) {
            if let preflightMessage {
                Text(preflightMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red.opacity(0.85))
                    .padding(.horizontal, 12)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(recordingTimeText)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.88)
                    Text(activeSessionDateText)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Button(action: onRecordTap) {
                    HStack(spacing: 6) {
                        Image(systemName: isRecording ? "stop.fill" : "record.circle.fill")
                            .font(.caption.weight(.semibold))
                        Text(isRecording ? "Stop" : "Record")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(isRecording ? Color.red.opacity(0.92) : Color.accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .glassEffect(.clear, in: Capsule(style: .continuous))
                    .background(
                        Capsule(style: .continuous)
                            .fill(.black.opacity(0.32))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(.white.opacity(0.14), lineWidth: 0.7)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .glassEffect(.clear, in: Capsule(style: .continuous))
            .background(
                Capsule(style: .continuous)
                    .fill(.black.opacity(0.28))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(.white.opacity(0.16), lineWidth: 0.7)
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }
#endif

    private var recorderCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                waveformPanel

                VStack(alignment: .leading, spacing: 10) {
                    Text(recordingTimeText)
                        .font(.system(size: 46, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    recorderActionControl

                    Text(activeSessionDateText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let preflightMessage {
                        Text(preflightMessage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red.opacity(0.85))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .allowsHitTesting(false)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.primary.opacity(0.12), lineWidth: 0.9)
                .allowsHitTesting(false)
        )
        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 6)
    }

    private var waveformPanel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.thinMaterial)

            HStack(alignment: .center, spacing: 3) {
                ForEach(Array(waveformBars.enumerated()), id: \.offset) { _, level in
                    Capsule(style: .continuous)
                        .fill(Color.red.opacity(0.78))
                        .frame(width: 2.4, height: max(CGFloat(level) * 34, 8))
                }
            }

            Rectangle()
                .fill(isRecording ? Color.red : Color.blue)
                .frame(width: 2)
                .overlay(
                    VStack {
                        Circle()
                            .fill(isRecording ? Color.red : Color.blue)
                            .frame(width: 8, height: 8)
                        Spacer()
                        Circle()
                            .fill(isRecording ? Color.red : Color.blue)
                            .frame(width: 8, height: 8)
                    }
                    .padding(.vertical, 8)
                )
        }
        .frame(width: 120, height: 126)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.primary.opacity(0.12), lineWidth: 0.7)
        )
    }

    private var recorderActionControl: some View {
#if os(macOS)
        Button {
            onRecordTap()
        } label: {
            Label(isRecording ? "Pause" : "Record", systemImage: isRecording ? "pause.fill" : "record.circle.fill")
                .font(.headline.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(isRecording ? Color.red.opacity(0.86) : Color.blue.opacity(0.80))
        .controlSize(.large)
#else
        Button {
            onRecordTap()
        } label: {
            HStack(spacing: 9) {
                Image(systemName: isRecording ? "pause.fill" : "record.circle.fill")
                    .font(.headline.weight(.semibold))
                Text(isRecording ? "Pause" : "Record")
                    .fontWeight(.semibold)
            }
            .foregroundStyle(isRecording ? Color.red.opacity(0.96) : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                Capsule(style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(.primary.opacity(0.12), lineWidth: 0.9)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Capsule(style: .continuous))
#endif
    }

    private var liveSegmentsCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            ForEach(liveChatItems) { item in
                HStack(alignment: .top, spacing: 10) {
                    avatarView(for: item)
                    TranscriptBubbleOptionButton(
                        item: item,
                        liveChatItems: liveChatItems,
                        selectedFocusLanguageCodes: selectedFocusLanguageCodes,
                        isRecording: isRecording,
                        isTranscriptionBusy: isTranscriptionBusy,
                        isItemTranscribing: transcribingRowIDs.contains(item.id),
                        isItemQueuedForRetranscription: queuedRetranscriptionRowIDs.contains(item.id),
                        isPlayable: isTranscriptBubblePlayable(item),
                        onTap: {
                            onTranscriptTap(item)
                        },
                        onManualEditTranscript: onManualEditTranscript,
                        onEditSpeakerName: onEditSpeakerName,
                        onChangeSpeaker: onChangeSpeaker,
                        onRetranscribeTranscript: onRetranscribeTranscript
                    ) {
                        messageBubble(for: item)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            if isRecording {
                recordingSpectrumRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var recordingSpectrumRow: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.84))

                Image(systemName: "waveform")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
            }
            .frame(width: 34, height: 34)
            .overlay(
                Circle()
                    .stroke(.white.opacity(0.55), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.12), radius: 7, x: 0, y: 4)

            RecordingSpectrumBubble(waveformBars: waveformBars)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func avatarView(for item: TranscriptRow) -> some View {
        ZStack {
            Circle()
                .fill(item.avatarPalette.first ?? .accentColor)

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

    private func messageBubble(for item: TranscriptRow) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                speakerMeta(for: item)
                Spacer(minLength: 8)
                timestampView(for: item)
            }

            if transcribingRowIDs.contains(item.id) {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.red.opacity(0.82))
                    Text("Transcribing message...")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red.opacity(0.82))
                        .multilineTextAlignment(.leading)
                }
                .transition(.opacity)
            } else if queuedRetranscriptionRowIDs.contains(item.id) {
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange.opacity(0.88))
                    Text("Queued for Transcribe Again...")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange.opacity(0.88))
                        .multilineTextAlignment(.leading)
                }
                .transition(.opacity)
            } else {
                Text(item.text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.primary.opacity(0.12), lineWidth: 0.8)
        )
        .animation(
            .easeInOut(duration: 0.2),
            value: transcribingRowIDs.contains(item.id) || queuedRetranscriptionRowIDs.contains(item.id)
        )
    }

    private func speakerMeta(for item: TranscriptRow) -> some View {
        HStack(spacing: 6) {
            Text(item.speaker)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(0)

            HStack(spacing: 3) {
                Image(systemName: "globe")
                    .font(.caption2.weight(.bold))
                Text(normalizedLanguageBadgeText(item.language))
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(1)
                    .allowsTightening(false)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(.thinMaterial)
            )
            .fixedSize(horizontal: true, vertical: true)
            .layoutPriority(1)
        }
    }

    private func normalizedLanguageBadgeText(_ language: String) -> String {
        let compact = language
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")

        return compact.isEmpty ? "??" : compact.uppercased()
    }

    private func timestampView(for item: TranscriptRow) -> some View {
        Text(item.time)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func isTranscriptBubblePlayable(_ item: TranscriptRow) -> Bool {
        guard canPlayTranscriptChunks,
              let startOffset = item.startOffset,
              let endOffset = item.endOffset
        else {
            return false
        }

        return endOffset > startOffset
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

    private var floatingButtonBottomPadding: CGFloat {
#if os(macOS)
        return 24
#else
        return 106
#endif
    }

    private var transcriptBottomMarker: some View {
        Color.clear
            .frame(height: 1)
            .id(transcriptBottomAnchorID)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ChatTranscriptContentBottomPreferenceKey.self,
                        value: proxy.frame(in: .named(transcriptScrollSpace)).maxY
                    )
                }
            )
    }

    private func newMessageButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label("New message", systemImage: "arrow.down.circle.fill")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
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
    }

    private func refreshBottomTracking() {
        guard scrollViewportHeight > 0 else {
            return
        }

        let nearBottom = scrollContentBottom <= (scrollViewportHeight + transcriptBottomTolerance)
        if nearBottom != isUserNearBottom {
            isUserNearBottom = nearBottom
        }
    }

    private func handleTranscriptUpdate(using proxy: ScrollViewProxy) {
        guard !liveChatItems.isEmpty else {
            hasPendingNewMessage = false
            return
        }

        if isUserNearBottom {
            scrollToTranscriptBottom(using: proxy, animated: true)
            hasPendingNewMessage = false
        } else {
            hasPendingNewMessage = true
        }
    }

    private func scrollToTranscriptBottom(using proxy: ScrollViewProxy, animated: Bool) {
        let scrollAction = {
            proxy.scrollTo(transcriptBottomAnchorID, anchor: .bottom)
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
        withAnimation(.spring(response: 0.25, dampingFraction: 0.86)) {
            isEditingTitle = true
        }
        DispatchQueue.main.async {
            isTitleFieldFocused = true
        }
    }

    private func commitTitleRename() {
        let trimmedTitle = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            onRenameSessionTitle(trimmedTitle)
            titleDraft = trimmedTitle
        } else {
            titleDraft = activeSessionTitle
        }

        withAnimation(.spring(response: 0.25, dampingFraction: 0.86)) {
            isEditingTitle = false
        }
        isTitleFieldFocused = false
    }

    private func cancelTitleRename() {
        titleDraft = activeSessionTitle
        withAnimation(.spring(response: 0.25, dampingFraction: 0.86)) {
            isEditingTitle = false
        }
        isTitleFieldFocused = false
    }
}

private struct ChatTranscriptViewportHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ChatTranscriptContentBottomPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
