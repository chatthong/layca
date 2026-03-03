//
//  QwenSummaryService.swift
//  layca
//
//  On-device summary using Qwen3-4B-4bit via MLX Swift.
//  Prefers bundled model in Models/RuntimeAssets/Qwen3-4B-4bit/ when all required files
//  are present; otherwise auto-downloads from HuggingFace on first use.
//

import Foundation
import MLXLLM
import MLXLMCommon

// MARK: - Service

/// Actor that owns the MLX Qwen3 model. Safe to call from any async context.
/// Cold-start: ~5–15 s on first call (model load). Subsequent calls are instant.
actor QwenSummaryService {

    static let shared = QwenSummaryService()
    private init() {}

    private var modelContainer: ModelContainer?

    // MARK: - Configuration

    private static let summarySystemPrompt = """
    You are a precise meeting secretary. Read the transcript and respond ONLY with this structure:

    ## Topic
    [One crisp line: what this session was about]

    ## Summary
    [3–5 sentences: who spoke, what was decided or discussed, key outcomes]

    ## Action Items
    - [ ] [specific task — include owner/person if mentioned]

    Omit the Action Items section entirely if there are no action items.
    Be concise. Do not repeat the transcript verbatim. Do not add any preamble or sign-off.
    """

    private static let qwenModelID = "mlx-community/Qwen3-4B-4bit"

    /// Returns the local RuntimeAssets model directory if all required MLX files are present,
    /// otherwise returns nil so the service falls back to HuggingFace download.
    private static func localModelDirectoryIfReady() -> URL? {
        // #file resolves to this source file's compile-time path, e.g.:
        //   .../xcode/layca/Libraries/QwenSummaryService.swift
        // From there: up 1 = layca/, then Models/RuntimeAssets/Qwen3-4B-4bit
        let devModelDir = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()                        // Libraries/
            .deletingLastPathComponent()                        // layca/
            .appending(path: "Models/RuntimeAssets/Qwen3-4B-4bit")

        // Future: model copied into app bundle resources
        let bundledModelDir = Bundle.main.bundleURL
            .appending(path: "Qwen3-4B-4bit")

        let required = ["config.json", "tokenizer.json", "tokenizer_config.json"]
        let fm = FileManager.default

        for dir in [devModelDir, bundledModelDir] {
            let allPresent = required.allSatisfy { fm.fileExists(atPath: dir.appending(path: $0).path) }
            if allPresent { return dir }
        }
        return nil
    }

    // MARK: - Public API

    /// Summarises a NotepadMinutes-format transcript.
    /// Yields the full response as a single string chunk.
    nonisolated func summarize(notepadMinutesText: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let container = try await self.loadIfNeeded()
                    let session = MLXLMCommon.ChatSession(
                        container,
                        instructions: Self.summarySystemPrompt
                    )
                    let result = try await session.respond(to: notepadMinutesText)
                    continuation.yield(result)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private

    private func loadIfNeeded() async throws -> ModelContainer {
        if let container = modelContainer { return container }

        let config: ModelConfiguration
        if let localDir = Self.localModelDirectoryIfReady() {
            // All model files present locally — no network needed
            config = ModelConfiguration(directory: localDir)
        } else {
            // Fall back to HuggingFace download (cached after first run)
            config = ModelConfiguration(id: Self.qwenModelID)
        }

        let container = try await LLMModelFactory.shared.loadContainer(
            configuration: config
        ) { _ in }
        modelContainer = container
        return container
    }
}
