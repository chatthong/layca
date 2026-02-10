import SwiftUI

struct TranscriptBubbleOptionButton<Content: View>: View {
    let item: TranscriptRow
    let liveChatItems: [TranscriptRow]
    let isRecording: Bool
    let isTranscriptionBusy: Bool
    let isItemTranscribing: Bool
    let isPlayable: Bool
    let onTap: () -> Void
    let onManualEditTranscript: (TranscriptRow, String) -> Void
    let onEditSpeakerName: (TranscriptRow, String) -> Void
    let onChangeSpeaker: (TranscriptRow, String) -> Void
    let onRetranscribeTranscript: (TranscriptRow) -> Void
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

                        Button {
                            onRetranscribeTranscript(item)
                        } label: {
                            Label("Transcribe Again", systemImage: "waveform.and.mic")
                        }
                        .disabled(!isPlayable || isItemTranscribing)
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
        !isRecording && !isTranscriptionBusy
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

    private func transcriptEditorSheet(for row: TranscriptRow) -> some View {
        NavigationStack {
            ZStack {
                sheetBackground
                LiquidBackdrop()
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Manual edit for this chunk transcript.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.80))

                    TextEditor(text: $transcriptEditDraft)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.96))
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(red: 0.08, green: 0.11, blue: 0.17).opacity(0.86))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.cyan.opacity(0.32), lineWidth: 1)
                        )
                        .frame(minHeight: 220)
                        .focused($isTranscriptEditorFocused)

                    Spacer(minLength: 0)
                }
                .padding(16)
            }
            .navigationTitle("Edit Transcript")
            .laycaApplyNavigationBarChrome(
                backgroundColor: Color(red: 0.08, green: 0.11, blue: 0.17)
            )
            .tint(.white)
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
                LiquidBackdrop()
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Rename this speaker for every matching bubble in this chat.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.80))

                    TextField("Speaker name", text: $speakerNameDraft)
                        .textFieldStyle(.plain)
                        .font(.headline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .foregroundStyle(.white.opacity(0.96))
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(red: 0.08, green: 0.11, blue: 0.17).opacity(0.86))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.cyan.opacity(0.32), lineWidth: 1)
                        )
                        .focused($isSpeakerNameFieldFocused)

                    Spacer(minLength: 0)
                }
                .padding(16)
            }
            .navigationTitle("Edit Speaker Name")
            .laycaApplyNavigationBarChrome(
                backgroundColor: Color(red: 0.08, green: 0.11, blue: 0.17)
            )
            .tint(.white)
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

    private var sheetBackground: some View {
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
    }
}

private struct TranscriptSpeakerMenuOption: Identifiable {
    let id: String
    let label: String
    let avatarSymbol: String
}
