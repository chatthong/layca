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
        #expect(config.prompt.contains("Do not censor"))
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

    @Test func renamingSpeakerUpdatesAllRowsForSameSpeakerID() async throws {
        let fileManager = FileManager.default
        let tempSessionsURL = fileManager.temporaryDirectory
            .appendingPathComponent("layca-tests-sessions-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: tempSessionsURL) }

        let store = SessionStore(fileManager: fileManager, sessionsDirectory: tempSessionsURL)
        let sessionID = try await store.createSession(title: "Chat 1", languageHints: ["en"])

        let first = PipelineTranscriptEvent(
            id: UUID(),
            sessionID: sessionID,
            speakerID: "speaker-a",
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
            speakerID: "speaker-a",
            languageID: "EN",
            text: "Second line",
            startOffset: 3,
            endOffset: 4,
            samples: [0.1, 0.2, 0.3],
            sampleRate: 16_000
        )
        let third = PipelineTranscriptEvent(
            id: UUID(),
            sessionID: sessionID,
            speakerID: "speaker-b",
            languageID: "TH",
            text: "Third line",
            startOffset: 5,
            endOffset: 6,
            samples: [0.1, 0.2, 0.3],
            sampleRate: 16_000
        )

        await store.appendTranscript(sessionID: sessionID, event: first)
        await store.appendTranscript(sessionID: sessionID, event: second)
        await store.appendTranscript(sessionID: sessionID, event: third)
        await store.updateSpeakerName(sessionID: sessionID, speakerID: "speaker-a", newName: "Alice")

        let rows = await store.transcriptRows(for: sessionID)

        #expect(rows.count == 3)
        #expect(rows[0].speakerID == "speaker-a")
        #expect(rows[1].speakerID == "speaker-a")
        #expect(rows[0].speaker == "Alice")
        #expect(rows[1].speaker == "Alice")
        #expect(rows[2].speaker == "speaker-b")
    }

    @Test func changingRowSpeakerReusesExistingSpeakerProfile() async throws {
        let fileManager = FileManager.default
        let tempSessionsURL = fileManager.temporaryDirectory
            .appendingPathComponent("layca-tests-sessions-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: tempSessionsURL) }

        let store = SessionStore(fileManager: fileManager, sessionsDirectory: tempSessionsURL)
        let sessionID = try await store.createSession(title: "Chat 1", languageHints: ["en"])

        let first = PipelineTranscriptEvent(
            id: UUID(),
            sessionID: sessionID,
            speakerID: "speaker-a",
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
            speakerID: "speaker-b",
            languageID: "TH",
            text: "Second line",
            startOffset: 3,
            endOffset: 4,
            samples: [0.1, 0.2, 0.3],
            sampleRate: 16_000
        )

        await store.appendTranscript(sessionID: sessionID, event: first)
        await store.appendTranscript(sessionID: sessionID, event: second)

        let originalRows = await store.transcriptRows(for: sessionID)
        let movingRow = try #require(originalRows.first)
        let targetRow = try #require(originalRows.last)

        await store.changeTranscriptRowSpeaker(
            sessionID: sessionID,
            rowID: movingRow.id,
            targetSpeakerID: "speaker-b"
        )

        let rows = await store.transcriptRows(for: sessionID)
        let updatedFirst = try #require(rows.first)

        #expect(updatedFirst.speakerID == "speaker-b")
        #expect(updatedFirst.speaker == targetRow.speaker)
        #expect(updatedFirst.avatarSymbol == targetRow.avatarSymbol)
    }

    @Test func sessionStoreReloadsPersistedSessionDataFromDisk() async throws {
        let fileManager = FileManager.default
        let tempSessionsURL = fileManager.temporaryDirectory
            .appendingPathComponent("layca-tests-sessions-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: tempSessionsURL) }

        let rowID = UUID()
        let createdSessionID: UUID

        do {
            let writerStore = SessionStore(fileManager: fileManager, sessionsDirectory: tempSessionsURL)
            createdSessionID = try await writerStore.createSession(title: "Chat 99", languageHints: ["en", "th"])

            let event = PipelineTranscriptEvent(
                id: rowID,
                sessionID: createdSessionID,
                speakerID: "speaker-main",
                languageID: "EN",
                text: "Persisted transcript line",
                startOffset: 12.5,
                endOffset: 14.0,
                samples: [0.1, 0.2],
                sampleRate: 16_000
            )
            await writerStore.appendTranscript(sessionID: createdSessionID, event: event)
            await writerStore.renameSession(sessionID: createdSessionID, title: "Weekly Sync")
        }

        let readerStore = SessionStore(fileManager: fileManager, sessionsDirectory: tempSessionsURL)
        let snapshots = await readerStore.snapshotSessions()
        let restored = try #require(snapshots.first(where: { $0.id == createdSessionID }))
        let rows = await readerStore.transcriptRows(for: createdSessionID)
        let firstRow = try #require(rows.first)

        #expect(restored.title == "Weekly Sync")
        #expect(rows.count == 1)
        #expect(firstRow.id == rowID)
        #expect(firstRow.text == "Persisted transcript line")
        #expect(firstRow.speaker == "speaker-main")
        #expect(firstRow.startOffset == 12.5)
        #expect(firstRow.endOffset == 14.0)
    }

    @Test func appSettingsStorePersistsRoundTrip() async throws {
        let suiteName = "layca-tests-settings-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = AppSettingsStore(userDefaults: defaults, storageKey: "layca.tests.settings")
        let expected = PersistedAppSettings(
            schemaVersion: 1,
            selectedLanguageCodes: ["en", "th"],
            languageSearchText: "thai",
            focusContextKeywords: "project atlas",
            totalHours: 40,
            usedHours: 7.5,
            isICloudSyncEnabled: true,
            activeSessionID: UUID(),
            chatCounter: 12
        )

        store.save(expected)
        let loaded = try #require(store.load())

        #expect(loaded == expected)
    }

    @Test func deletingTranscriptRowRemovesItFromStoreAndDiskSnapshot() async throws {
        let fileManager = FileManager.default
        let tempSessionsURL = fileManager.temporaryDirectory
            .appendingPathComponent("layca-tests-sessions-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: tempSessionsURL) }

        let store = SessionStore(fileManager: fileManager, sessionsDirectory: tempSessionsURL)
        let sessionID = try await store.createSession(title: "Chat Trim", languageHints: ["en"])
        let firstRowID = UUID()
        let secondRowID = UUID()

        let first = PipelineTranscriptEvent(
            id: firstRowID,
            sessionID: sessionID,
            speakerID: "speaker-a",
            languageID: "EN",
            text: "Maybe silence chunk",
            startOffset: 1.0,
            endOffset: 2.0,
            samples: [0.1, 0.2],
            sampleRate: 16_000
        )
        let second = PipelineTranscriptEvent(
            id: secondRowID,
            sessionID: sessionID,
            speakerID: "speaker-b",
            languageID: "EN",
            text: "Keep this line",
            startOffset: 4.0,
            endOffset: 6.0,
            samples: [0.1, 0.2],
            sampleRate: 16_000
        )

        await store.appendTranscript(sessionID: sessionID, event: first)
        await store.appendTranscript(sessionID: sessionID, event: second)
        await store.deleteTranscriptRow(sessionID: sessionID, rowID: firstRowID)

        let rows = await store.transcriptRows(for: sessionID)
        #expect(rows.count == 1)
        #expect(rows.first?.id == secondRowID)

        let reloadedStore = SessionStore(fileManager: fileManager, sessionsDirectory: tempSessionsURL)
        let reloadedRows = await reloadedStore.transcriptRows(for: sessionID)
        #expect(reloadedRows.count == 1)
        #expect(reloadedRows.first?.id == secondRowID)
    }

    @Test func sessionDurationTracksLatestTranscriptOffset() async throws {
        let fileManager = FileManager.default
        let tempSessionsURL = fileManager.temporaryDirectory
            .appendingPathComponent("layca-tests-sessions-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: tempSessionsURL) }

        let store = SessionStore(fileManager: fileManager, sessionsDirectory: tempSessionsURL)
        let sessionID = try await store.createSession(title: "Chat Duration", languageHints: ["en"])

        let first = PipelineTranscriptEvent(
            id: UUID(),
            sessionID: sessionID,
            speakerID: "speaker-a",
            languageID: "EN",
            text: "Line 1",
            startOffset: 1.0,
            endOffset: 2.5,
            samples: [0.1, 0.2],
            sampleRate: 16_000
        )
        let second = PipelineTranscriptEvent(
            id: UUID(),
            sessionID: sessionID,
            speakerID: "speaker-b",
            languageID: "EN",
            text: "Line 2",
            startOffset: 3.0,
            endOffset: 7.25,
            samples: [0.1, 0.2],
            sampleRate: 16_000
        )

        await store.appendTranscript(sessionID: sessionID, event: first)
        await store.appendTranscript(sessionID: sessionID, event: second)

        let duration = await store.sessionDurationSeconds(for: sessionID)
        #expect(duration == 7.25)
    }

    @Test func hasRecordedAudioOnlyWhenSessionFileContainsData() async throws {
        let fileManager = FileManager.default
        let tempSessionsURL = fileManager.temporaryDirectory
            .appendingPathComponent("layca-tests-sessions-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: tempSessionsURL) }

        let store = SessionStore(fileManager: fileManager, sessionsDirectory: tempSessionsURL)
        let sessionID = try await store.createSession(title: "Chat Audio Presence", languageHints: ["en"])

        let initiallyHasAudio = await store.hasRecordedAudio(for: sessionID)
        #expect(initiallyHasAudio == false)

        guard let audioURL = await store.audioFileURL(for: sessionID) else {
            Issue.record("Expected audio URL for created session.")
            return
        }

        try Data([0x1, 0x2, 0x3]).write(to: audioURL, options: .atomic)

        let hasAudioAfterWrite = await store.hasRecordedAudio(for: sessionID)
        #expect(hasAudioAfterWrite == true)
    }

    @Test func deletingSessionRemovesItFromStoreAndDisk() async throws {
        let fileManager = FileManager.default
        let tempSessionsURL = fileManager.temporaryDirectory
            .appendingPathComponent("layca-tests-sessions-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: tempSessionsURL) }

        let store = SessionStore(fileManager: fileManager, sessionsDirectory: tempSessionsURL)
        let sessionID = try await store.createSession(title: "Chat Delete", languageHints: ["en"])
        let sessionDirectory = tempSessionsURL.appendingPathComponent(sessionID.uuidString, isDirectory: true)

        #expect(fileManager.fileExists(atPath: sessionDirectory.path))

        await store.deleteSession(sessionID: sessionID)
        let snapshots = await store.snapshotSessions()

        #expect(snapshots.isEmpty)
        #expect(fileManager.fileExists(atPath: sessionDirectory.path) == false)
    }
}
