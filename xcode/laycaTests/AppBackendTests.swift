import Foundation
import Testing
@testable import layca

struct AppBackendTests {
    @Test func preflightBuildsPromptFromLanguageFocus() async throws {
        let service = PreflightService()
        let config = try await service.prepare(
            languageCodes: ["th", "en"],
            focusKeywords: "",
            remainingCreditSeconds: 120
        )

        #expect(config.languageCodes == ["en", "th"])
        #expect(config.prompt.contains("English"))
        #expect(config.prompt.contains("Thai"))
    }

    @Test func preflightFailsWhenCreditsAreExhausted() async throws {
        let service = PreflightService()

        do {
            _ = try await service.prepare(
                languageCodes: ["en"],
                focusKeywords: "",
                remainingCreditSeconds: 0
            )
            #expect(Bool(false))
        } catch {
            #expect(error.localizedDescription.contains("Hours credit is empty"))
        }
    }

    @Test func speakerProfileIsStableAcrossChunksInSession() async throws {
        let fileManager = FileManager.default
        let tempSessionsURL = fileManager.temporaryDirectory
            .appendingPathComponent("layca-tests-sessions-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: tempSessionsURL) }

        let store = SessionStore(fileManager: fileManager, sessionsDirectory: tempSessionsURL)
        let sessionID = try await store.createSession(title: "Chat 1", languageHints: ["en"])

        let first = PipelineTranscriptEvent(
            id: UUID(),
            sessionID: sessionID,
            speakerID: "Speaker A",
            languageID: "EN",
            text: "First line",
            startOffset: 1,
            endOffset: 2,
            samples: [0.1, 0.2, 0.3],
            sampleRate: 16_000
        )
        let second = PipelineTranscriptEvent(
            id: UUID(),
            sessionID: sessionID,
            speakerID: "Speaker A",
            languageID: "EN",
            text: "Second line",
            startOffset: 3,
            endOffset: 4,
            samples: [0.1, 0.2, 0.3],
            sampleRate: 16_000
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
