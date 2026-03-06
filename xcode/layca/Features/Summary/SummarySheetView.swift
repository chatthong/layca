//
//  SummarySheetView.swift
//  layca
//

import SwiftUI

struct SummarySheetView: View {

    let snapshot: ExportSessionSnapshot
    let loadCachedSummary: ((UUID) async -> String?)?
    let saveCachedSummary: ((UUID, String) async -> Void)?

    @State private var phase: Phase = .loading
    @State private var hasLoadedInitialContent = false
    @State private var activeSummaryTask: Task<Void, Never>?
    @State private var activeSummaryRunID: UUID?
    @State private var downloadProgress: Double? = nil
    @Environment(\.dismiss) private var dismiss
    private let localSummaryCache = UserDefaults.standard

    private enum Phase {
        case loading
        case result(String)
        case failed(String)
    }

    init(
        snapshot: ExportSessionSnapshot,
        loadCachedSummary: ((UUID) async -> String?)? = nil,
        saveCachedSummary: ((UUID, String) async -> Void)? = nil
    ) {
        self.snapshot = snapshot
        self.loadCachedSummary = loadCachedSummary
        self.saveCachedSummary = saveCachedSummary
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Session Summary")
#if os(iOS) || os(visionOS)
                .navigationBarTitleDisplayMode(.inline)
#endif
                .toolbar { toolbarContent }
                .task { await loadInitialContentIfNeeded() }
                .onDisappear { cancelSummaryTask() }
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
            if let progress = downloadProgress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 220)
                    .accessibilityLabel("Downloading AI model")
                Text("Downloading AI model… \(Int(progress * 100))%")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .scaleEffect(1.4)
                    .accessibilityLabel("Generating summary")
                Text("thinking...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func resultView(_ markdown: String) -> some View {
        return ScrollView {
            Text(markdown)
                .textSelection(.enabled)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
    }

    private func errorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Summary Failed", systemImage: "exclamationmark.bubble")
        } description: {
            Text(message)
        } actions: {
            Button("Retry") {
                startSummary()
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Done") {
                cancelSummaryTask()
                dismiss()
            }
        }
        if case .result = phase {
            ToolbarItem(placement: .automatic) {
                Button {
                    regenerateSummary()
                } label: {
                    Label("Re-summary", systemImage: "arrow.clockwise")
                }
            }
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

    private func loadInitialContentIfNeeded() async {
        guard !hasLoadedInitialContent else {
            return
        }
        hasLoadedInitialContent = true

        if let cached = loadLocalSummaryCache() {
            phase = .result(cached)
            return
        }

        if let sessionID = snapshot.sessionID,
           let loadCachedSummary,
           let cached = await loadCachedSummary(sessionID) {
            let trimmed = cached.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                persistLocalSummaryCache(trimmed)
                phase = .result(trimmed)
                return
            }
        }

        guard !Task.isCancelled else {
            return
        }
        try? await Task.sleep(nanoseconds: 250_000_000)
        guard !Task.isCancelled else {
            return
        }
        startSummary()
    }

    private func regenerateSummary() {
        startSummary()
    }

    private func startSummary() {
        cancelSummaryTask()
        let runID = UUID()
        activeSummaryRunID = runID
        phase = .loading
        activeSummaryTask = Task { @MainActor in
            await runSummary(runID: runID)
        }
    }

    private func runSummary(runID: UUID) async {
        defer {
            downloadProgress = nil
            finishSummaryRun(runID)
        }

        let input = ExportService.build(format: .notepadMinutes, snapshot: snapshot)
        do {
            var accumulated = ""
            for try await chunk in QwenSummaryService.shared.summarize(
                notepadMinutesText: input,
                onDownloadProgress: { @MainActor fraction in
                    self.downloadProgress = fraction < 1.0 ? fraction : nil
                }
            ) {
                guard !Task.isCancelled, isCurrentSummaryRun(runID) else {
                    return
                }
                accumulated += chunk
                await persistSummaryIfPossible(accumulated)
                guard isCurrentSummaryRun(runID) else {
                    return
                }
                phase = .result(accumulated)
            }

            guard !Task.isCancelled, isCurrentSummaryRun(runID) else {
                return
            }
            if accumulated.isEmpty {
                phase = .failed("No summary was generated.")
                return
            }

            await persistSummaryIfPossible(accumulated)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, isCurrentSummaryRun(runID) else {
                return
            }
            phase = .failed(error.localizedDescription)
        }
    }

    private func persistSummaryIfPossible(_ summaryText: String) async {
        let trimmed = summaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        persistLocalSummaryCache(trimmed)

        guard let sessionID = snapshot.sessionID,
              let saveCachedSummary else {
            return
        }
        await saveCachedSummary(sessionID, trimmed)
    }

    private func summaryCacheKey() -> String {
        if let sessionID = snapshot.sessionID {
            return "layca.summary.\(sessionID.uuidString)"
        }
        let fallback = "\(snapshot.title)|\(snapshot.createdAtText)|\(snapshot.rows.count)"
        return "layca.summary.fallback.\(fallback)"
    }

    private func loadLocalSummaryCache() -> String? {
        let raw = localSummaryCache.string(forKey: summaryCacheKey()) ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func persistLocalSummaryCache(_ summaryText: String) {
        localSummaryCache.set(summaryText, forKey: summaryCacheKey())
    }

    private func cancelSummaryTask() {
        activeSummaryTask?.cancel()
        activeSummaryTask = nil
        activeSummaryRunID = nil
    }

    private func isCurrentSummaryRun(_ runID: UUID) -> Bool {
        activeSummaryRunID == runID
    }

    private func finishSummaryRun(_ runID: UUID) {
        guard activeSummaryRunID == runID else {
            return
        }
        activeSummaryTask = nil
        activeSummaryRunID = nil
    }

    private func copyToClipboard(_ text: String) {
#if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
#else
        UIPasteboard.general.string = text
#endif
    }

}
