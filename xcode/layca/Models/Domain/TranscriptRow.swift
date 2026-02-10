import SwiftUI

struct TranscriptRow: Identifiable {
    let id: UUID
    let speakerID: String
    let speaker: String
    let text: String
    let time: String
    let language: String
    let avatarSymbol: String
    let avatarPalette: [Color]
    let startOffset: Double?
    let endOffset: Double?

    nonisolated init(
        id: UUID = UUID(),
        speakerID: String,
        speaker: String,
        text: String,
        time: String,
        language: String,
        avatarSymbol: String,
        avatarPalette: [Color],
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
        self.avatarPalette = avatarPalette
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
        let avatarPalettes: [[Color]] = [
            [.blue, .cyan],
            [.teal, .mint],
            [.indigo, .blue],
            [.orange, .pink],
            [.purple, .indigo]
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

        var speakerAvatars: [String: (String, [Color])] = [:]

        func avatarForSpeaker(_ speaker: String) -> (String, [Color]) {
            if let existing = speakerAvatars[speaker] {
                return existing
            }
            let symbol = avatarSymbols.randomElement() ?? "person.fill"
            let palette = avatarPalettes.randomElement() ?? [.blue, .cyan]
            let generated = (symbol, palette)
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
                avatarPalette: avatar.1,
                startOffset: nil,
                endOffset: nil
            )
        }
    }
}
