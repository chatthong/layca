import SwiftUI

struct TranscriptRow: Identifiable {
    let id: UUID
    let speakerID: String
    let speaker: String
    let text: String
    let time: String
    let language: String
    let avatarSymbol: String
    let avatarPaletteIndex: Int
    let startOffset: Double?
    let endOffset: Double?

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
        endOffset: Double?
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
