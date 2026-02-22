//
//  ExportService.swift
//  layca
//

import Foundation

/// A snapshot of session data captured at export time, decoupled from live AppBackend state.
struct ExportSessionSnapshot {
    let title: String
    let createdAtText: String
    let rows: [TranscriptRow]
}

/// Pure, stateless formatting service for all transcript export formats.
/// All methods are static and thread-safe — no UI or AppBackend coupling.
struct ExportService {
    static func build(format: ExportFormat, snapshot: ExportSessionSnapshot) -> String {
        switch format {
        case .notepadMinutes:
            return buildNotepadMinutesText(snapshot: snapshot)
        case .markdown:
            return buildMarkdownText(snapshot: snapshot)
        case .plainText:
            return buildPlainTranscriptText(snapshot: snapshot)
        case .videoSubtitlesSRT:
            return buildVideoSubtitlesSRTText(snapshot: snapshot)
        }
    }
}

// MARK: - Format builders

private extension ExportService {

    static func buildPlainTranscriptText(snapshot: ExportSessionSnapshot) -> String {
        let lines = snapshot.rows.compactMap { row -> String? in
            let trimmed = row.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        if lines.isEmpty {
            return "No messages in this chat yet."
        }

        return lines.joined(separator: "\n\n")
    }

    static func buildNotepadMinutesText(snapshot: ExportSessionSnapshot) -> String {
        let header = [
            snapshot.title,
            "Created: \(snapshot.createdAtText)",
            "",
            ""
        ]
        .joined(separator: "\n")

        guard !snapshot.rows.isEmpty else {
            return "\(header)No messages in this chat yet."
        }

        let lines = snapshot.rows.map { row in
            "[\(row.time)] \(row.speaker) (\(row.language))\n\(row.text)"
        }
        .joined(separator: "\n\n")

        return "\(header)\(lines)"
    }

    static func buildMarkdownText(snapshot: ExportSessionSnapshot) -> String {
        var lines: [String] = [
            "# \(snapshot.title)",
            "",
            "- Created: \(snapshot.createdAtText)",
            "- Export style: Markdown",
            "",
            "## Transcript",
            ""
        ]

        if snapshot.rows.isEmpty {
            lines.append("_No messages in this chat yet._")
        } else {
            for row in snapshot.rows {
                lines.append("### [\(row.time)] \(row.speaker) (\(row.language))")
                lines.append(row.text)
                lines.append("")
            }
        }

        return lines.joined(separator: "\n")
    }

    static func buildVideoSubtitlesSRTText(snapshot: ExportSessionSnapshot) -> String {
        guard !snapshot.rows.isEmpty else {
            return ""
        }

        let minimumCueDuration: Double = 0.8
        var cues: [String] = []
        cues.reserveCapacity(snapshot.rows.count)

        for (index, row) in snapshot.rows.enumerated() {
            let start = resolvedSRTStartSeconds(
                for: row,
                at: index,
                rows: snapshot.rows
            )
            let end = resolvedSRTEndSeconds(
                for: row,
                at: index,
                rows: snapshot.rows,
                start: start,
                minimumCueDuration: minimumCueDuration
            )
            let cueText = row.text
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !cueText.isEmpty else {
                continue
            }

            cues.append(
                [
                    "\(cues.count + 1)",
                    "\(formatSRTTimestamp(seconds: start)) --> \(formatSRTTimestamp(seconds: end))",
                    cueText
                ]
                .joined(separator: "\n")
            )
        }

        return cues.joined(separator: "\n\n")
    }
}

// MARK: - SRT helpers

private extension ExportService {

    static func resolvedSRTStartSeconds(
        for row: TranscriptRow,
        at index: Int,
        rows: [TranscriptRow]
    ) -> Double {
        if let startOffset = row.startOffset, startOffset >= 0 {
            return startOffset
        }

        if let parsed = parseHHMMSSTimestampToSeconds(row.time) {
            return parsed
        }

        guard index > 0 else {
            return 0
        }

        let previous = rows[index - 1]
        if let previousEnd = previous.endOffset, previousEnd >= 0 {
            return previousEnd
        }
        if let previousStart = previous.startOffset, previousStart >= 0 {
            return previousStart + 2
        }
        if let previousParsed = parseHHMMSSTimestampToSeconds(previous.time) {
            return previousParsed + 2
        }

        return Double(index) * 2
    }

    static func resolvedSRTEndSeconds(
        for row: TranscriptRow,
        at index: Int,
        rows: [TranscriptRow],
        start: Double,
        minimumCueDuration: Double
    ) -> Double {
        if let endOffset = row.endOffset, endOffset > start {
            return endOffset
        }

        if index + 1 < rows.count {
            let nextRow = rows[index + 1]
            let candidateNextStart = nextRow.startOffset ?? parseHHMMSSTimestampToSeconds(nextRow.time)
            if let candidateNextStart, candidateNextStart > start {
                return max(candidateNextStart, start + minimumCueDuration)
            }
        }

        return start + minimumCueDuration
    }

    static func parseHHMMSSTimestampToSeconds(_ value: String) -> Double? {
        let parts = value.split(separator: ":")
        guard parts.count == 3,
              let hours = Int(parts[0]),
              let minutes = Int(parts[1]),
              let seconds = Int(parts[2]) else {
            return nil
        }

        return Double((hours * 3600) + (minutes * 60) + seconds)
    }

    static func formatSRTTimestamp(seconds: Double) -> String {
        let clamped = max(0, seconds)
        let totalMilliseconds = Int((clamped * 1000).rounded())
        let hours = totalMilliseconds / 3_600_000
        let minutes = (totalMilliseconds % 3_600_000) / 60_000
        let secs = (totalMilliseconds % 60_000) / 1_000
        let milliseconds = totalMilliseconds % 1_000
        return String(
            format: "%02d:%02d:%02d,%03d",
            hours,
            minutes,
            secs,
            milliseconds
        )
    }
}
