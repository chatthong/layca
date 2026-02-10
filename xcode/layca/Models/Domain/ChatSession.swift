import Foundation

struct ChatSession: Identifiable {
    let id: UUID
    var title: String
    let createdAt: Date
    let rows: [TranscriptRow]

    var formattedDate: String {
        createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    static func makeDemoSession(chatNumber: Int) -> ChatSession {
        ChatSession(
            id: UUID(),
            title: "Chat \(chatNumber)",
            createdAt: Date(),
            rows: TranscriptRow.makeDemoRows(chatNumber: chatNumber)
        )
    }
}
