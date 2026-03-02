//
//  QwenSummaryService.swift
//  layca
//
//  On-device summary using Qwen3-4B-4bit via MLX Swift.
//  Model auto-downloads from HuggingFace on first use and is cached locally.
//

import Foundation
import MLXLLM
import MLXLMCommon

// MARK: - Hard-coded summary prompt (not user-configurable)

private let kSummarySystemPrompt = """
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

// MARK: - Model configuration

private let kQwenModelID = "mlx-community/Qwen3-4B-4bit"

// MARK: - Service

/// Actor that owns the MLX Qwen3 model. Safe to call from any async context.
/// Model is loaded lazily on first summarise call — expect ~5–15s cold-start on first use.
actor QwenSummaryService {

    static let shared = QwenSummaryService()
    private init() {}

    private var modelContainer: ModelContainer?

    // MARK: - Public API

    /// Summarises a NotepadMinutes-format transcript.
    /// Yields the full response as a single chunk (non-streaming for simplicity).
    /// Upgrade to streaming via `modelContainer.perform` + `MLXLMCommon.generate` if needed.
    func summarize(notepadMinutesText: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let container = try await self.loadIfNeeded()
                    let session = ChatSession(container, systemPrompt: kSummarySystemPrompt)
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
        let config = ModelConfiguration(id: kQwenModelID)
        let container = try await MLXModelFactory.shared.loadContainer(
            configuration: config
        ) { _ in
            // Download/load progress — forward to UI if needed in future
        }
        modelContainer = container
        return container
    }
}
