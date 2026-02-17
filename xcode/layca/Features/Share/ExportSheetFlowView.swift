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
        }
    }

    var fileExtension: String {
        switch self {
        case .markdown:
            return "md"
        case .videoSubtitlesSRT:
            return "srt"
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
        }
    }
}

struct ExportSheetFlowView: View {
    let sessionTitle: String
    let createdAtText: String
    let buildPayload: (ExportFormat) -> String

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
                    payload: buildPayload(format)
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
    let payload: String

    @State private var didCopy = false
    @State private var shareFileURL: URL?

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
                Text(previewText)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(nil)
            }

            Section("Actions") {
#if os(macOS)
                HStack(spacing: 10) {
                    if let shareFileURL {
                        ShareLink(
                            item: shareFileURL,
                            subject: Text(sessionTitle),
                            message: Text("Shared from Layca")
                        ) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        ShareLink(
                            item: payload,
                            subject: Text(sessionTitle),
                            message: Text("Shared from Layca")
                        ) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }

                    Button {
                        copyExportTextToPasteboard(payload)
                        didCopy = true
                    } label: {
                        Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                    }

                    Spacer(minLength: 0)
                }
                .buttonStyle(.bordered)
#else
                if let shareFileURL {
                    ShareLink(
                        item: shareFileURL,
                        subject: Text(sessionTitle),
                        message: Text("Shared from Layca")
                    ) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                } else {
                    ShareLink(
                        item: payload,
                        subject: Text(sessionTitle),
                        message: Text("Shared from Layca")
                    ) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }

                Button {
                    copyExportTextToPasteboard(payload)
                    didCopy = true
                } label: {
                    Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
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
            shareFileURL = buildShareFileURL()
        }
    }

    private var shareTaskID: String {
        "\(format.rawValue)|\(sessionTitle)|\(payload)"
    }

    private func buildShareFileURL() -> URL? {
        let fileName = "\(sanitizedFileStem(sessionTitle))-\(format.fileNameSuffix).\(format.fileExtension)"
        let targetURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try payload.write(to: targetURL, atomically: true, encoding: .utf8)
            return targetURL
        } catch {
            return nil
        }
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
