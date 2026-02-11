import SwiftUI

struct TranscriptBubbleOptionButton<Content: View>: View {
    let item: TranscriptRow
    let liveChatItems: [TranscriptRow]
    let selectedFocusLanguageCodes: Set<String>
    let isRecording: Bool
    let isTranscriptionBusy: Bool
    let isItemTranscribing: Bool
    let isItemQueuedForRetranscription: Bool
    let isPlayable: Bool
    let onTap: () -> Void
    let onManualEditTranscript: (TranscriptRow, String) -> Void
    let onEditSpeakerName: (TranscriptRow, String) -> Void
    let onChangeSpeaker: (TranscriptRow, String) -> Void
    let onRetranscribeTranscript: (TranscriptRow, String?) -> Void
    @ViewBuilder let content: () -> Content

    @State private var editingTranscriptRow: TranscriptRow?
    @State private var editingSpeakerRow: TranscriptRow?
    @State private var transcriptEditDraft = ""
    @State private var speakerNameDraft = ""
    @FocusState private var isTranscriptEditorFocused: Bool
    @FocusState private var isSpeakerNameFieldFocused: Bool

    var body: some View {
        Group {
            if isContextMenuEnabled {
                bubbleButton
                    .contextMenu {
                        Button {
                            beginTranscriptEdit(item)
                        } label: {
                            Label("Edit Text", systemImage: "square.and.pencil")
                        }
                        .disabled(isItemTranscribing)

                        Button {
                            beginSpeakerNameEdit(item)
                        } label: {
                            Label("Edit Speaker Name", systemImage: "character.cursor.ibeam")
                        }
                        .disabled(isItemTranscribing)

                        Menu {
                            changeSpeakerMenu(for: item)
                        } label: {
                            Label("Change Speaker", systemImage: "person.2.circle")
                        }
                        .disabled(speakerOptions(excluding: item.speakerID).isEmpty || isItemTranscribing)

                        Divider()

                        Menu {
                            retranscribeMenu(for: item)
                        } label: {
                            Label("Transcribe Again", systemImage: "waveform.and.mic")
                        }
                        .disabled(!isPlayable || isItemTranscribing || isItemQueuedForRetranscription)
                    }
            } else {
                bubbleButton
            }
        }
        .sheet(item: $editingTranscriptRow) { row in
            transcriptEditorSheet(for: row)
        }
        .sheet(item: $editingSpeakerRow) { row in
            speakerEditorSheet(for: row)
        }
    }

    private var bubbleButton: some View {
        Button {
            if isPlayable {
                onTap()
            }
        } label: {
            content()
        }
        .buttonStyle(.plain)
    }

    private var isContextMenuEnabled: Bool {
        !isRecording
    }

    private func beginTranscriptEdit(_ row: TranscriptRow) {
        transcriptEditDraft = row.text
        editingTranscriptRow = row
    }

    private func beginSpeakerNameEdit(_ row: TranscriptRow) {
        speakerNameDraft = row.speaker
        editingSpeakerRow = row
    }

    private func saveTranscriptEdit() {
        guard let row = editingTranscriptRow else {
            return
        }

        let trimmed = transcriptEditDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        onManualEditTranscript(row, trimmed)
        editingTranscriptRow = nil
    }

    private func saveSpeakerNameEdit() {
        guard let row = editingSpeakerRow else {
            return
        }

        let trimmed = speakerNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        onEditSpeakerName(row, trimmed)
        editingSpeakerRow = nil
    }

    private func speakerOptions(excluding speakerID: String) -> [TranscriptSpeakerMenuOption] {
        var seenIDs: Set<String> = []
        var options: [TranscriptSpeakerMenuOption] = []

        for row in liveChatItems where row.speakerID != speakerID {
            guard seenIDs.insert(row.speakerID).inserted else {
                continue
            }

            options.append(
                TranscriptSpeakerMenuOption(
                    id: row.speakerID,
                    label: row.speaker,
                    avatarSymbol: row.avatarSymbol
                )
            )
        }

        return options.sorted {
            $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
        }
    }

    @ViewBuilder
    private func changeSpeakerMenu(for item: TranscriptRow) -> some View {
        let options = speakerOptions(excluding: item.speakerID)
        if options.isEmpty {
            Button {
            } label: {
                Label("No other speaker", systemImage: "person.fill.xmark")
            }
            .disabled(true)
        } else {
            ForEach(options) { option in
                Button {
                    onChangeSpeaker(item, option.id)
                } label: {
                    Label(option.label, systemImage: option.avatarSymbol)
                }
            }
        }
    }

    @ViewBuilder
    private func retranscribeMenu(for item: TranscriptRow) -> some View {
        Button {
            onRetranscribeTranscript(item, nil)
        } label: {
            Label("Transcribe Auto", systemImage: "wand.and.stars")
        }

        if !focusLanguageOptions.isEmpty {
            Divider()
            ForEach(focusLanguageOptions) { option in
                Button {
                    onRetranscribeTranscript(item, option.code)
                } label: {
                    Label("Transcribe in \(option.displayName)", systemImage: "globe")
                }
            }
        }
    }

    private var focusLanguageOptions: [TranscriptRetranscribeLanguageOption] {
        let normalizedCodes = Set(
            selectedFocusLanguageCodes
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty && $0 != "auto" }
        )

        return normalizedCodes
            .map { code in
                let displayName = Locale.current.localizedString(forLanguageCode: code) ?? code.uppercased()
                return TranscriptRetranscribeLanguageOption(
                    code: code,
                    displayName: displayName
                )
            }
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }

    private func transcriptEditorSheet(for row: TranscriptRow) -> some View {
        NavigationStack {
            ZStack {
                sheetBackground

                VStack(alignment: .leading, spacing: 12) {
                    Text("Manual edit for this message transcript.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $transcriptEditDraft)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(.regularMaterial)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(.primary.opacity(0.12), lineWidth: 1)
                        )
                        .frame(minHeight: 220)
                        .focused($isTranscriptEditorFocused)

                    Spacer(minLength: 0)
                }
                .padding(16)
            }
            .navigationTitle("Edit Transcript")
            .laycaApplyNavigationBarChrome(
                backgroundColor: sheetNavigationBarColor
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        editingTranscriptRow = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveTranscriptEdit()
                    }
                    .disabled(transcriptEditDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                transcriptEditDraft = row.text
                DispatchQueue.main.async {
                    isTranscriptEditorFocused = true
                }
            }
        }
    }

    private func speakerEditorSheet(for row: TranscriptRow) -> some View {
        NavigationStack {
            ZStack {
                sheetBackground

                VStack(alignment: .leading, spacing: 12) {
                    Text("Rename this speaker for every matching bubble in this chat.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextField("Speaker name", text: $speakerNameDraft)
                        .textFieldStyle(.plain)
                        .font(.headline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .foregroundStyle(.primary)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.regularMaterial)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(.primary.opacity(0.12), lineWidth: 1)
                        )
                        .focused($isSpeakerNameFieldFocused)

                    Spacer(minLength: 0)
                }
                .padding(16)
            }
            .navigationTitle("Edit Speaker Name")
            .laycaApplyNavigationBarChrome(
                backgroundColor: sheetNavigationBarColor
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        editingSpeakerRow = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveSpeakerNameEdit()
                    }
                    .disabled(speakerNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                speakerNameDraft = row.speaker
                DispatchQueue.main.async {
                    isSpeakerNameFieldFocused = true
                }
            }
        }
    }

    @ViewBuilder
    private var sheetBackground: some View {
#if os(macOS)
        LinearGradient(
            colors: [
                Color(red: 0.10, green: 0.15, blue: 0.23),
                Color(red: 0.09, green: 0.13, blue: 0.19),
                Color(red: 0.08, green: 0.14, blue: 0.17)
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

    private var sheetNavigationBarColor: Color {
#if os(macOS)
        Color.clear
#else
        Color(uiColor: .systemBackground)
#endif
    }
}

private struct TranscriptSpeakerMenuOption: Identifiable {
    let id: String
    let label: String
    let avatarSymbol: String
}

private struct TranscriptRetranscribeLanguageOption: Identifiable {
    let code: String
    let displayName: String

    var id: String { code }
}
