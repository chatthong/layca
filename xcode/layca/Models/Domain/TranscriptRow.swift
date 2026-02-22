import Foundation
import SwiftUI

struct TranscriptRow: Identifiable {
    let id: UUID
    let speakerID: String
    let speaker: String
    var text: String
    let time: String
    let language: String
    let avatarSymbol: String
    let avatarPaletteIndex: Int
    let startOffset: Double?
    let endOffset: Double?
    /// Optional per-bubble audio file (Sprint 8+). Legacy sessions leave this nil.
    var chunkURL: URL?
    var updatedAt: Date

    var avatarColor: Color {
        Self.palettes[avatarPaletteIndex % Self.palettes.count].first ?? .accentColor
    }

    static let palettes: [[Color]] = [
        [Color(hex: "#F97316"), .white.opacity(0.72)],
        [Color(hex: "#0EA5E9"), .white.opacity(0.72)],
        [Color(hex: "#10B981"), .white.opacity(0.72)],
        [Color(hex: "#EF4444"), .white.opacity(0.72)],
        [Color(hex: "#6366F1"), .white.opacity(0.72)],
        [Color(hex: "#D97706"), .white.opacity(0.72)],
        [Color(hex: "#14B8A6"), .white.opacity(0.72)]
    ]

    nonisolated init(
        id: UUID = UUID(),
        speakerID: String,
        speaker: String,
        text: String,
        time: String,
        language: String,
        avatarSymbol: String,
        avatarPaletteIndex: Int,
        startOffset: Double?,
        endOffset: Double?,
        chunkURL: URL? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.speakerID = speakerID
        self.speaker = speaker
        self.text = text
        self.time = time
        self.language = language
        self.avatarSymbol = avatarSymbol
        self.avatarPaletteIndex = avatarPaletteIndex
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.chunkURL = chunkURL
        self.updatedAt = updatedAt
    }

    /// Persists chunk audio as a session-relative URL (e.g. `chunks/chunk-<uuid>.m4a`) when possible.
    /// Falls back to the original value to avoid data loss if the file is outside the session directory.
    func persistedChunkURL(relativeTo sessionDirectory: URL) -> URL? {
        Self.persistedChunkURL(chunkURL, relativeTo: sessionDirectory)
    }

    /// Resolves a stored relative chunk URL against `sessionDirectory` for runtime file access.
    /// Absolute URLs pass through unchanged for backward/forward compatibility during migration.
    func resolvedChunkURL(relativeTo sessionDirectory: URL) -> URL? {
        Self.resolvedChunkURL(chunkURL, relativeTo: sessionDirectory)
    }

    static func persistedChunkURL(_ url: URL?, relativeTo sessionDirectory: URL) -> URL? {
        guard let url else { return nil }

        // Already relative/non-file URL; persist as-is (JSON will store the relative string).
        guard url.isFileURL else { return url }

        // Preserve relative file URLs or URLs that already carry a base relationship.
        if url.baseURL != nil {
            let relative = url.relativeString.trimmingCharacters(in: .whitespacesAndNewlines)
            return relative.isEmpty ? nil : URL(string: relative)
        }

        let sessionPath = sessionDirectory.standardizedFileURL.path
        let urlPath = url.standardizedFileURL.path
        let sessionPrefix = sessionPath.hasSuffix("/") ? sessionPath : sessionPath + "/"

        guard urlPath.hasPrefix(sessionPrefix) else {
            return url
        }

        let relativePath = String(urlPath.dropFirst(sessionPrefix.count))
        return relativePath.isEmpty ? nil : URL(string: relativePath)
    }

    static func resolvedChunkURL(_ storedURL: URL?, relativeTo sessionDirectory: URL) -> URL? {
        guard let storedURL else { return nil }

        if storedURL.isFileURL, storedURL.baseURL == nil {
            return storedURL
        }

        if let scheme = storedURL.scheme, !scheme.isEmpty {
            return storedURL
        }

        let relative = storedURL.relativeString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !relative.isEmpty else { return nil }
        return sessionDirectory.appendingPathComponent(relative)
    }

    static func makeDemoRows(chatNumber: Int) -> [TranscriptRow] {
        struct BaseMessage {
            let speaker: String
            let text: String
            let time: String
            let language: String
        }

        let avatarSymbols = [
            "person.fill",
            "person.2.fill",
            "person.crop.circle.fill.badge.checkmark",
            "person.crop.circle.badge.clock",
            "person.crop.circle.badge.questionmark"
        ]

        let baseMessages: [BaseMessage] = [
            BaseMessage(
                speaker: "Speaker A",
                text: "Chat \(chatNumber): Let's lock the roadmap and keep settings focused.",
                time: "00:04:32",
                language: "EN"
            ),
            BaseMessage(
                speaker: "Speaker B",
                text: "Agreed. Then we can add VAD controls in the next pass.",
                time: "00:04:47",
                language: "TH"
            ),
            BaseMessage(
                speaker: "Speaker A",
                text: "I'll finalize the checklist and send a clean summary tonight.",
                time: "00:05:03",
                language: "EN"
            )
        ]

        var speakerAvatars: [String: (String, Int)] = [:]
        var nextIndex = 0

        func avatarForSpeaker(_ speaker: String) -> (String, Int) {
            if let existing = speakerAvatars[speaker] {
                return existing
            }
            let symbol = avatarSymbols.randomElement() ?? "person.fill"
            let paletteIndex = nextIndex % palettes.count
            nextIndex += 1
            let generated = (symbol, paletteIndex)
            speakerAvatars[speaker] = generated
            return generated
        }

        return baseMessages.map { message in
            let avatar = avatarForSpeaker(message.speaker)
            return TranscriptRow(
                speakerID: message.speaker,
                speaker: message.speaker,
                text: message.text,
                time: message.time,
                language: message.language,
                avatarSymbol: avatar.0,
                avatarPaletteIndex: avatar.1,
                startOffset: nil,
                endOffset: nil
            )
        }
    }
}
