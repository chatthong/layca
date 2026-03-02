//
//  ExportSheetFlowView.swift
//  layca
//
//  Created by Codex on 2/17/26.
//

import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

enum ExportFormat: String, CaseIterable, Hashable, Identifiable {
    case notepadMinutes
    case markdown
    case plainText
    case videoSubtitlesSRT
    case audio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notepadMinutes:
            return "Notepad Minutes"
        case .markdown:
            return "Markdown"
        case .plainText:
            return "Plain Text"
        case .videoSubtitlesSRT:
            return "Video Subtitles (.srt)"
        case .audio:
            return "Audio (.m4a)"
        }
    }

    var subtitle: String {
        switch self {
        case .notepadMinutes:
            return "Timestamp + speaker + language"
        case .markdown:
            return "Structured headings format"
        case .plainText:
            return "Raw transcript text only"
        case .videoSubtitlesSRT:
            return "SubRip subtitles for video tools"
        case .audio:
            return "Merged single-track session audio"
        }
    }

    var symbol: String {
        switch self {
        case .notepadMinutes:
            return "note.text"
        case .markdown:
            return "number.square"
        case .plainText:
            return "text.alignleft"
        case .videoSubtitlesSRT:
            return "captions.bubble"
        case .audio:
            return "waveform"
        }
    }

    var detail: String {
        switch self {
        case .notepadMinutes:
            return "Best for meeting notes with compact timestamp and speaker context."
        case .markdown:
            return "Best for docs, notes apps, and formatting-friendly destinations."
        case .plainText:
            return "Best for quick paste workflows where you only need the spoken content."
        case .videoSubtitlesSRT:
            return "Best for video editors and players that support SubRip subtitle files."
        case .audio:
            return "Best for sharing one merged audio track built from all chat chunks in timeline order."
        }
    }

    var fileExtension: String {
        switch self {
        case .markdown:
            return "md"
        case .videoSubtitlesSRT:
            return "srt"
        case .audio:
            return "m4a"
        case .notepadMinutes, .plainText:
            return "txt"
        }
    }

    var fileNameSuffix: String {
        switch self {
        case .notepadMinutes:
            return "notepad-minutes"
        case .markdown:
            return "markdown"
        case .plainText:
            return "plain-text"
        case .videoSubtitlesSRT:
            return "video-subtitles"
        case .audio:
            return "audio"
        }
    }

    var isTextExport: Bool {
        switch self {
        case .audio:
            return false
        case .notepadMinutes, .markdown, .plainText, .videoSubtitlesSRT:
            return true
        }
    }
}

struct ExportSheetFlowView: View {
    let sessionTitle: String
    let createdAtText: String
    let buildPayload: (ExportFormat) -> String
    let buildAudioSourceURL: () async -> URL?

    @Environment(\.dismiss) private var dismiss
    @State private var path: [ExportFormat] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(sessionTitle)
                            .font(.body.weight(.semibold))
                        Text("Created: \(createdAtText)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Share Styles") {
                    ForEach(ExportFormat.allCases) { format in
                        NavigationLink(value: format) {
                            formatRow(format)
                        }
                    }
                }
            }
            .applyExportListStyle()
            .applyExportMacSheetFill()
            .navigationTitle("Share")
            .applyExportRootTitleDisplayMode()
            .navigationDestination(for: ExportFormat.self) { format in
                ExportSheetFormatStepView(
                    format: format,
                    sessionTitle: sessionTitle,
                    buildPayload: buildPayload,
                    buildAudioSourceURL: buildAudioSourceURL
                )
                .applyExportSubstepCloseControl {
                    dismiss()
                }
            }
#if os(iOS)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    exportSheetCloseButton {
                        dismiss()
                    }
                }
            }
#endif
        }
        .applyExportMacSheetFill()
        .onDisappear {
            path.removeAll()
        }
        .applyExportSheetCloseControl {
            dismiss()
        }
    }

    private func formatRow(_ format: ExportFormat) -> some View {
        HStack(spacing: 12) {
            Image(systemName: format.symbol)
                .font(.body.weight(.semibold))
                .frame(width: 20, height: 20)
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(format.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(format.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ExportSheetFormatStepView: View {
    let format: ExportFormat
    let sessionTitle: String
    let buildPayload: (ExportFormat) -> String
    let buildAudioSourceURL: () async -> URL?

    @State private var didCopy = false
    @State private var didSave = false
    @State private var isPreparingFile = false
    @State private var filePreparationError: String?
    @State private var fileSaveError: String?
    @State private var shareFileURL: URL?

    private var payload: String {
        format.isTextExport ? buildPayload(format) : ""
    }

    private var previewText: String {
        let previewLineLimit = 11
        let lines = payload.components(separatedBy: .newlines)
        let previewLines = lines.prefix(previewLineLimit)
        let preview = previewLines.joined(separator: "\n")
        if lines.count > previewLineLimit {
            return "\(preview)\n…"
        }
        return preview
    }

    var body: some View {
        Form {
            Section {
                Text(format.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Preview") {
                if format.isTextExport {
                    Text(previewText)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(nil)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Renders one merged audio file from all chat chunks.", systemImage: "waveform")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        if isPreparingFile {
                            ProgressView("Rendering audio...")
                        } else if let shareFileURL {
                            Label(shareFileURL.lastPathComponent, systemImage: "checkmark.circle")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else if let filePreparationError {
                            Text(filePreparationError)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Actions") {
#if os(macOS)
                HStack(spacing: 10) {
                    shareActionControl

                    if format.isTextExport {
                        Button {
                            copyExportTextToPasteboard(payload)
                            didCopy = true
                        } label: {
                            Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                        }
                    }

                    Button {
                        guard let shareFileURL else {
                            return
                        }
                        do {
                            let savedURL = try saveExportFileToDownloads(from: shareFileURL)
                            didSave = true
                            fileSaveError = nil
                            self.shareFileURL = savedURL
                        } catch {
                            didSave = false
                            fileSaveError = "Save failed: \(error.localizedDescription)"
                        }
                    } label: {
                        Label(didSave ? "Saved" : "Save", systemImage: didSave ? "checkmark" : "arrow.down.to.line")
                    }
                    .disabled(isPreparingFile || shareFileURL == nil)

                    Spacer(minLength: 0)
                }
                .buttonStyle(.bordered)
                if let fileSaveError {
                    Text(fileSaveError)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
#else
                shareActionControl

                if format.isTextExport {
                    Button {
                        copyExportTextToPasteboard(payload)
                        didCopy = true
                    } label: {
                        Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                    }
                }
#endif
            }
        }
#if os(macOS)
        .formStyle(.grouped)
#endif
        .applyExportMacSheetFill()
        .navigationTitle(format.title)
        .applyExportStepTitleDisplayMode()
        .task(id: shareTaskID) {
            await prepareShareFile()
        }
    }

    private var shareTaskID: String {
        switch format {
        case .audio:
            return "\(format.rawValue)|\(sessionTitle)"
        case .notepadMinutes, .markdown, .plainText, .videoSubtitlesSRT:
            return "\(format.rawValue)|\(sessionTitle)|\(payload)"
        }
    }

    @ViewBuilder
    private var shareActionControl: some View {
        if isPreparingFile {
            Label("Preparing…", systemImage: "hourglass")
        } else if let shareFileURL {
            ShareLink(
                item: shareFileURL,
                subject: Text(sessionTitle),
                message: Text("Shared from Layca")
            ) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        } else if format.isTextExport {
            ShareLink(
                item: payload,
                subject: Text(sessionTitle),
                message: Text("Shared from Layca")
            ) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        } else {
            Button {
                Task {
                    await prepareShareFile()
                }
            } label: {
                Label("Retry Render", systemImage: "arrow.clockwise")
            }
        }
    }

    @MainActor
    private func prepareShareFile() async {
        didCopy = false
        didSave = false
        filePreparationError = nil
        fileSaveError = nil
        isPreparingFile = true
        defer { isPreparingFile = false }

        if format.isTextExport {
            shareFileURL = buildTextShareFileURL(payload: payload)
            return
        }

        shareFileURL = await buildAudioShareFileURL()
        if shareFileURL == nil {
            filePreparationError = "Unable to render audio yet. Make sure this chat has recorded audio chunks."
        }
    }

    private func buildTextShareFileURL(payload: String) -> URL? {
        let fileName = "\(sanitizedFileStem(sessionTitle))-\(format.fileNameSuffix).\(format.fileExtension)"
        let targetURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            if FileManager.default.fileExists(atPath: targetURL.path) {
                try? FileManager.default.removeItem(at: targetURL)
            }
            try payload.write(to: targetURL, atomically: true, encoding: .utf8)
            return targetURL
        } catch {
            return nil
        }
    }

    private func buildAudioShareFileURL() async -> URL? {
        guard let sourceURL = await buildAudioSourceURL() else {
            return nil
        }

        let fileName = "\(sanitizedFileStem(sessionTitle))-\(format.fileNameSuffix).\(format.fileExtension)"
        let targetURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        guard sourceURL.standardizedFileURL != targetURL.standardizedFileURL else {
            return sourceURL
        }

        do {
            if FileManager.default.fileExists(atPath: targetURL.path) {
                try? FileManager.default.removeItem(at: targetURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: targetURL)
            return targetURL
        } catch {
            return FileManager.default.fileExists(atPath: sourceURL.path) ? sourceURL : nil
        }
    }

    private func saveExportFileToDownloads(from sourceURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let downloadsURL = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        try fileManager.createDirectory(at: downloadsURL, withIntermediateDirectories: true)

        let destinationURL = uniqueDestinationURL(
            in: downloadsURL,
            preferredFileName: sourceURL.lastPathComponent
        )
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    private func uniqueDestinationURL(in directory: URL, preferredFileName: String) -> URL {
        let fileManager = FileManager.default
        let baseName = (preferredFileName as NSString).deletingPathExtension
        let fileExtension = (preferredFileName as NSString).pathExtension

        var candidate = directory.appendingPathComponent(preferredFileName)
        var index = 1
        while fileManager.fileExists(atPath: candidate.path) {
            let suffix = "-\(index)"
            let nextName: String
            if fileExtension.isEmpty {
                nextName = "\(baseName)\(suffix)"
            } else {
                nextName = "\(baseName)\(suffix).\(fileExtension)"
            }
            candidate = directory.appendingPathComponent(nextName)
            index += 1
        }
        return candidate
    }

    private func sanitizedFileStem(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "layca-export"
        }

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        var output = ""
        var hasSeparator = false

        for scalar in trimmed.unicodeScalars {
            if allowed.contains(scalar) {
                output.append(Character(scalar))
                hasSeparator = false
            } else if !hasSeparator {
                output.append("-")
                hasSeparator = true
            }
        }

        let cleaned = output.trimmingCharacters(in: CharacterSet(charactersIn: "-_")).lowercased()
        return cleaned.isEmpty ? "layca-export" : cleaned
    }
}

private struct ExportSheetCloseControlModifier: ViewModifier {
    let onClose: () -> Void

    func body(content: Content) -> some View {
#if os(macOS)
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack {
                    Spacer()
                    Button("Close", action: onClose)
                        .keyboardShortcut(.cancelAction)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(.regularMaterial)
                .overlay(alignment: .top) {
                    Divider()
                }
            }
#else
        content
#endif
    }
}

private extension View {
    func applyExportSheetCloseControl(onClose: @escaping () -> Void) -> some View {
        modifier(ExportSheetCloseControlModifier(onClose: onClose))
    }

    @ViewBuilder
    func applyExportSubstepCloseControl(onClose: @escaping () -> Void) -> some View {
#if os(iOS)
        toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                exportSheetCloseButton(action: onClose)
            }
        }
#else
        self
#endif
    }

    @ViewBuilder
    func applyExportRootTitleDisplayMode() -> some View {
#if os(iOS)
        navigationBarTitleDisplayMode(.inline)
#else
        self
#endif
    }

    @ViewBuilder
    func applyExportStepTitleDisplayMode() -> some View {
#if os(iOS)
        navigationBarTitleDisplayMode(.inline)
#else
        self
#endif
    }

    @ViewBuilder
    func applyExportListStyle() -> some View {
#if os(macOS)
        listStyle(.inset)
#else
        listStyle(.insetGrouped)
#endif
    }

    @ViewBuilder
    func applyExportMacSheetFill() -> some View {
#if os(macOS)
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
#else
        self
#endif
    }
}

@ViewBuilder
private func exportSheetCloseButton(action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: "xmark")
    }
    .accessibilityLabel("Close")
}

private func copyExportTextToPasteboard(_ text: String) {
#if os(macOS)
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
#else
    UIPasteboard.general.string = text
#endif
}
