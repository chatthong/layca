import Foundation
import Testing
@testable import layca

struct AppBackendTests {
    @Test func preflightBuildsPromptFromLanguageFocus() async throws {
        let fileManager = FileManager.default
        let tempModelsURL = fileManager.temporaryDirectory
            .appendingPathComponent("layca-tests-models-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: tempModelsURL) }

        let manager = ModelManager(fileManager: fileManager, modelsDirectory: tempModelsURL)
        try await manager.installPlaceholderModel(.normalAI)

        let service = PreflightService()
        let config = try await service.prepare(
            selectedModelID: BackendModel.normalAI.rawValue,
            languageCodes: ["th", "en"],
            remainingCreditSeconds: 120,
            modelManager: manager
        )

        #expect(config.resolvedModel == .normalAI)
        #expect(config.languageCodes == ["en", "th"])
        #expect(config.prompt.contains("English"))
        #expect(config.prompt.contains("Thai"))
    }

    @Test func preflightFallsBackToInstalledModelWhenSelectedMissing() async throws {
        let fileManager = FileManager.default
        let tempModelsURL = fileManager.temporaryDirectory
            .appendingPathComponent("layca-tests-fallback-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: tempModelsURL) }

        let manager = ModelManager(fileManager: fileManager, modelsDirectory: tempModelsURL)
        try await manager.installPlaceholderModel(.lightAI)

        let service = PreflightService()
        let config = try await service.prepare(
            selectedModelID: BackendModel.normalAI.rawValue,
            languageCodes: ["en"],
            remainingCreditSeconds: 120,
            modelManager: manager
        )

        #expect(config.resolvedModel == .lightAI)
        #expect(config.fallbackNote != nil)
    }

    @Test func speakerProfileIsStableAcrossChunksInSession() async throws {
        let fileManager = FileManager.default
        let tempSessionsURL = fileManager.temporaryDirectory
            .appendingPathComponent("layca-tests-sessions-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: tempSessionsURL) }

        let store = SessionStore(fileManager: fileManager, sessionsDirectory: tempSessionsURL)
        let sessionID = try await store.createSession(title: "Chat 1", languageHints: ["en"], modelID: BackendModel.lightAI.rawValue)

        let first = PipelineTranscriptEvent(
            id: UUID(),
            sessionID: sessionID,
            speakerID: "Speaker A",
            languageID: "EN",
            text: "First line",
            startOffset: 1,
            endOffset: 2
        )
        let second = PipelineTranscriptEvent(
            id: UUID(),
            sessionID: sessionID,
            speakerID: "Speaker A",
            languageID: "EN",
            text: "Second line",
            startOffset: 3,
            endOffset: 4
        )

        await store.appendTranscript(sessionID: sessionID, event: first)
        await store.appendTranscript(sessionID: sessionID, event: second)

        let rows = await store.transcriptRows(for: sessionID)

        #expect(rows.count == 2)
        #expect(rows[0].speaker == "Speaker A")
        #expect(rows[1].speaker == "Speaker A")
        #expect(rows[0].avatarSymbol == rows[1].avatarSymbol)
    }
}
