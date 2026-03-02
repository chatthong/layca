//
//  SummarySheetView.swift
//  layca
//

import SwiftUI

struct SummarySheetView: View {

    let snapshot: ExportSessionSnapshot

    @State private var phase: Phase = .loading
    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case loading
        case result(String)
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Session Summary")
#if os(iOS) || os(visionOS)
                .navigationBarTitleDisplayMode(.inline)
#endif
                .toolbar { toolbarContent }
                .task { await runSummary() }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            loadingView
        case .result(let markdown):
            resultView(markdown)
        case .failed(let message):
            errorView(message)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.4)
                .accessibilityLabel("Generating summary")
            Text("Qwen is reading the transcript…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Running fully on-device · no data leaves your device")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func resultView(_ markdown: String) -> some View {
        ScrollView {
            Text(attributedMarkdown(markdown))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
    }

    private func errorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Summary Failed", systemImage: "exclamationmark.bubble")
        } description: {
            Text(message)
        } actions: {
            Button("Retry") {
                phase = .loading
                Task { await runSummary() }
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Done") { dismiss() }
        }
        if case .result(let text) = phase {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    copyToClipboard(text)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }
        }
    }

    // MARK: - Actions

    private func runSummary() async {
        let input = ExportService.build(format: .notepadMinutes, snapshot: snapshot)
        do {
            var accumulated = ""
            for try await chunk in QwenSummaryService.shared.summarize(notepadMinutesText: input) {
                accumulated += chunk
                phase = .result(accumulated)
            }
            if accumulated.isEmpty {
                phase = .failed("No summary was generated.")
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func copyToClipboard(_ text: String) {
#if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
#else
        UIPasteboard.general.string = text
#endif
    }

    private func attributedMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}
