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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notepadMinutes:
            return "Notepad Minutes"
        case .markdown:
            return "Markdown"
        case .plainText:
            return "Plain Text"
        }
    }

    var subtitle: String {
        switch self {
        case .notepadMinutes:
            return "Timestamp + speaker style"
        case .markdown:
            return "Structured headings format"
        case .plainText:
            return "Simple transcript output"
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
        }
    }

    var detail: String {
        switch self {
        case .notepadMinutes:
            return "Best for meeting notes with compact timestamp and speaker context."
        case .markdown:
            return "Best for docs, notes apps, and formatting-friendly destinations."
        case .plainText:
            return "Best for quick copy/share with no additional formatting."
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

    private var previewText: String {
        let lines = payload.components(separatedBy: .newlines)
        let previewLines = lines.prefix(14)
        let preview = previewLines.joined(separator: "\n")
        if lines.count > 14 {
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
                ShareLink(
                    item: payload,
                    subject: Text(sessionTitle),
                    message: Text("Shared from Layca")
                ) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }

                Button {
                    copyExportTextToPasteboard(payload)
                    didCopy = true
                } label: {
                    Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                }
            }
        }
        .navigationTitle(format.title)
        .applyExportStepTitleDisplayMode()
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
