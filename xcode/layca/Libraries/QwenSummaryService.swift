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
    private static let maxPreparedTranscriptCharacters = 26_000

    // MARK: - Configuration

    private static let summarySystemPrompt = """
    You are a professional meeting secretary. Analyze the transcript and do two things:

    1. Silently fix speech-to-text errors (garbled words, mishearing, misspellings).
    2. Write polished meeting minutes. Output ONLY this JSON — no markdown, no extra text:

    {
      "topic": "concise noun-phrase title",
      "summary_paragraphs": [
        "Paragraph covering main topics discussed and key context.",
        "Paragraph covering key figures, numbers, decisions, and comparisons made.",
        "Paragraph covering direction, strategy, or conclusions reached."
      ],
      "checklist": ["Specific actionable next step 1", "Specific actionable next step 2"]
    }

    Style rules:
    - Formal prose. Third-person. Past tense. Not a speaker-by-speaker replay.
    - Always mention specific numbers, percentages, and amounts from the meeting.
    - Write in the same language as the transcript.
    - checklist: 2 to 5 specific, actionable items. Infer next steps if not stated explicitly.
    - topic: short, no filler prefixes.
    """

    private static let qwenModelID = "mlx-community/Qwen3-4B-4bit"

    /// Returns the bundled model directory if all required MLX files are present,
    /// otherwise returns nil so the service falls back to HuggingFace download.
    private static func localModelDirectoryIfReady() -> URL? {
        // The build script copies Models/RuntimeAssets/ into the app bundle's Resources folder.
        // Bundle.main.resourceURL already points to Contents/Resources/ (macOS) or the bundle
        // root (iOS/tvOS/visionOS), so appending the subpath works on all platforms.
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let bundledModelDir = resourceURL
            .appending(path: "Models/RuntimeAssets/Qwen3-4B-4bit")

        let required = ["config.json", "tokenizer.json", "tokenizer_config.json"]
        let fm = FileManager.default
        let allPresent = required.allSatisfy { fm.fileExists(atPath: bundledModelDir.appending(path: $0).path) }
        return allPresent ? bundledModelDir : nil
    }

    // MARK: - Public API

    /// Summarises a NotepadMinutes-format transcript.
    /// Yields the full response as a single string chunk.
    /// `onDownloadProgress` is called with 0…1 while the model downloads on first use.
    nonisolated func summarize(
        notepadMinutesText: String,
        onDownloadProgress: @escaping @Sendable (Double) -> Void = { _ in }
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let work = Task {
                do {
                    try Task.checkCancellation()
                    let container = try await self.loadIfNeeded(onDownloadProgress: onDownloadProgress)
                    let session = MLXLMCommon.ChatSession(
                        container,
                        instructions: Self.summarySystemPrompt,
                        generateParameters: .init(
                            maxTokens: 1500,
                            temperature: 0,
                            topP: 1.0
                        )
                    )
                    let preparedTranscript = Self.preparedTranscript(from: notepadMinutesText)
                    let firstPrompt = Self.makeTranscriptPrompt(preparedTranscript)
                    try Task.checkCancellation()
                    let rawResult = try await session.respond(to: firstPrompt)
                    var cleanedResult = Self.summaryFromRawOutput(
                        rawResult,
                        fallbackTranscript: preparedTranscript
                    )

                    // Retry once with a hard JSON repair instruction when output is weak or malformed.
                    if !Self.hasMeaningfulSummary(cleanedResult) {
                        try Task.checkCancellation()
                        let retryPrompt = Self.makeTranscriptPrompt(
                            """
                            Fix any transcription errors, then rewrite as strict JSON only — no extra text:
                            {"topic":"...","summary_paragraphs":["...","..."],"checklist":["...","..."]}

                            Rules:
                            - topic: short noun phrase.
                            - summary_paragraphs: 2 to 4 natural prose paragraphs.
                            - checklist: 2 to 5 concrete action items. Never empty.
                            - Write in the same language(s) as the transcript.
                            - No meta commentary.

                            Transcript:
                            \(preparedTranscript)
                            """
                        )
                        let retryRaw = try await session.respond(to: retryPrompt)
                        try Task.checkCancellation()
                        let retryCleaned = Self.summaryFromRawOutput(
                            retryRaw,
                            fallbackTranscript: preparedTranscript
                        )
                        if Self.hasMeaningfulSummary(retryCleaned) {
                            cleanedResult = retryCleaned
                        }
                    }

                    if !Self.hasMeaningfulSummary(cleanedResult) {
                        cleanedResult = Self.heuristicSummary(from: preparedTranscript)
                    }

                    try Task.checkCancellation()
                    continuation.yield(cleanedResult)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                work.cancel()
            }
        }
    }

    // MARK: - Private

    private func loadIfNeeded(
        onDownloadProgress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> ModelContainer {
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
        ) { progress in
            onDownloadProgress(progress.fractionCompleted)
        }
        modelContainer = container
        return container
    }

    /// Strips reasoning artifacts and normalizes output to the app's expected markdown shape.
    private static func cleanSummaryOutput(_ raw: String) -> String {
        let text = raw
            .replacingOccurrences(of: #"\r\n?"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<think>.*?</think>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<thinking>.*?</thinking>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<think>.*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<thinking>.*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)</?think[^>]*>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)</?thinking[^>]*>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?im)^\s*```(?:md|markdown)?\s*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?im)^\s*```\s*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?im)^\s*##\s*Topic\s*$"#, with: "Topic:", options: .regularExpression)
            .replacingOccurrences(of: #"(?im)^\s*##\s*Summary\s*$"#, with: "Summary:", options: .regularExpression)
            .replacingOccurrences(of: #"(?im)^\s*##\s*Action\s*Items\s*$"#, with: "Action Items:", options: .regularExpression)
            .replacingOccurrences(of: #"(?im)^\s*##\s*Checklist\s*$"#, with: "Checklist:", options: .regularExpression)
            .replacingOccurrences(of: #"(?im)^\s*#\s*Topic\s*$"#, with: "Topic:", options: .regularExpression)
            .replacingOccurrences(of: #"(?im)^\s*#\s*Summary\s*$"#, with: "Summary:", options: .regularExpression)
            .replacingOccurrences(of: #"(?im)^\s*#\s*Action\s*Items\s*$"#, with: "Action Items:", options: .regularExpression)
            .replacingOccurrences(of: #"(?im)^\s*#\s*Checklist\s*$"#, with: "Checklist:", options: .regularExpression)
            .replacingOccurrences(of: #"(?im)^\s*Topic:\s*"#, with: "Topic: ", options: .regularExpression)
            .replacingOccurrences(of: #"(?im)^\s*Summary:\s*"#, with: "Summary: ", options: .regularExpression)
            .replacingOccurrences(of: #"(?im)^\s*Action\s*Items:\s*"#, with: "Action Items: ", options: .regularExpression)
            .replacingOccurrences(of: #"(?im)^\s*Checklist:\s*"#, with: "Checklist: ", options: .regularExpression)
            .replacingOccurrences(
                of: #"(?is)(Topic:\s*[^\n]+?)\s*(Summary:)"#,
                with: "$1\n\n$2",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return canonicalMarkdownSummary(from: text)
    }

    private enum SummarySection {
        case none
        case topic
        case summary
        case actionItems
    }

    private static func canonicalMarkdownSummary(from text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        var topic: String?
        var summaryLines: [String] = []
        var actionItems: [String] = []
        var fallbackSummaryLines: [String] = []
        var section: SummarySection = .none
        var expectsTopicValue = false

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                continue
            }
            if isMetaLine(line) {
                continue
            }

            if let topicValue = value(afterPrefix: "Topic:", in: line) {
                topic = topicValue
                section = .none
                expectsTopicValue = false
                continue
            }

            if line.range(of: #"(?i)^#{1,6}\s*topic\s*:?\s*$"#, options: .regularExpression) != nil
                || line.caseInsensitiveCompare("Topic:") == .orderedSame
            {
                section = .topic
                expectsTopicValue = true
                continue
            }
            if line.range(of: #"(?i)^#{1,6}\s*summary\s*:?\s*$"#, options: .regularExpression) != nil
                || line.caseInsensitiveCompare("Summary:") == .orderedSame
            {
                section = .summary
                expectsTopicValue = false
                continue
            }
            if line.range(of: #"(?i)^#{1,6}\s*action\s*items\s*:?\s*$"#, options: .regularExpression) != nil
                || line.range(of: #"(?i)^#{1,6}\s*checklist\s*:?\s*$"#, options: .regularExpression) != nil
                || line.caseInsensitiveCompare("Action Items:") == .orderedSame
                || line.caseInsensitiveCompare("Checklist:") == .orderedSame
            {
                section = .actionItems
                expectsTopicValue = false
                continue
            }

            if expectsTopicValue, topic == nil {
                topic = line
                expectsTopicValue = false
                section = .none
                continue
            }

            if let checklistItem = normalizedChecklist(line), !isMetaLine(checklistItem) {
                if section == .actionItems {
                    actionItems.append(checklistItem)
                } else {
                    summaryLines.append(checklistItem)
                }
                continue
            }

            switch section {
            case .summary:
                summaryLines.append(line)
            case .actionItems:
                actionItems.append("- [ ] \(line.replacingOccurrences(of: "^-\\s*", with: "", options: .regularExpression))")
            case .topic:
                if topic == nil {
                    topic = line
                } else {
                    fallbackSummaryLines.append(line)
                }
            case .none:
                if topic == nil {
                    topic = line
                } else {
                    fallbackSummaryLines.append(line)
                }
            }
        }

        summaryLines = summaryLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !isMetaLine($0) }

        fallbackSummaryLines = fallbackSummaryLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !isMetaLine($0) }

        if summaryLines.isEmpty {
            summaryLines = fallbackSummaryLines
        }
        if summaryLines.isEmpty {
            summaryLines = ["- Discussion captured from transcript."]
        }
        if summaryLines.count > 6 {
            summaryLines = Array(summaryLines.prefix(6))
        }

        let resolvedTopic: String
        if let topic, !topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            resolvedTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            if let firstSummary = summaryLines.first {
                resolvedTopic = shortTopic(from: firstSummary)
            } else {
                resolvedTopic = "Session Summary"
            }
        }

        var output: [String] = [
            "Topic: \(resolvedTopic)",
            "",
            "Summary:"
        ]
        output.append(contentsOf: summaryLines)

        if !actionItems.isEmpty {
            output.append("")
            output.append("Checklist:")
            output.append(contentsOf: actionItems.filter { !isMetaLine($0) })
        }

        return output
            .joined(separator: "\n")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func value(afterPrefix prefix: String, in line: String) -> String? {
        guard line.lowercased().hasPrefix(prefix.lowercased()) else {
            return nil
        }
        let value = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : String(value)
    }

    private static func normalizedChecklist(_ line: String) -> String? {
        guard let matchRange = line.range(
            of: #"^-\s*\[(?:\s|x|X)\]\s*(.+)$"#,
            options: .regularExpression
        ) else {
            return nil
        }

        let matched = String(line[matchRange])
        let task = matched.replacingOccurrences(
            of: #"^-\s*\[(?:\s|x|X)\]\s*"#,
            with: "",
            options: .regularExpression
        )
        let cleaned = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return nil
        }
        return "- [ ] \(cleaned)"
    }

    private static func makeTranscriptPrompt(_ transcript: String) -> String {
        // Send transcript directly — Qwen3 thinking mode ON for better
        // ASR correction quality. <think> blocks are stripped from output.
        """
        Transcript:
        \(transcript)
        """
    }

    private static func summaryFromRawOutput(_ raw: String, fallbackTranscript: String) -> String {
        if let payload = extractSummaryPayload(from: raw) {
            let rendered = renderSummary(payload)
            if hasMeaningfulSummary(rendered) {
                return normalizedSummaryDisplay(from: rendered)
            }
        }

        let cleaned = cleanSummaryOutput(raw)
        if hasMeaningfulSummary(cleaned) {
            return normalizedSummaryDisplay(from: cleaned)
        }

        return normalizedSummaryDisplay(from: heuristicSummary(from: fallbackTranscript))
    }

    private static func hasMeaningfulSummary(_ markdown: String) -> Bool {
        let normalized = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return false
        }

        guard normalized.localizedCaseInsensitiveContains("Topic:"),
              normalized.localizedCaseInsensitiveContains("Summary:")
        else {
            return false
        }

        let parsed = parseTopicAndSummaryParagraphs(from: normalized)
        guard let topic = parsed.topic else {
            return false
        }

        guard !topic.isEmpty, topic.count <= 90 else {
            return false
        }
        let summaryParagraphs = parsed.paragraphs.filter { !$0.isEmpty }
        guard summaryParagraphs.count >= 2 else {
            return false
        }
        if summaryParagraphs.allSatisfy({ $0.caseInsensitiveCompare("Discussion captured from transcript.") == .orderedSame }) {
            return false
        }
        if isLowQualitySummary(topic: topic, paragraphs: summaryParagraphs) {
            return false
        }

        return true
    }

    private static func shortTopic(from line: String) -> String {
        let stripped = line
            .replacingOccurrences(of: #"^-\s*\[\s*\]\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^-\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if stripped.count <= 64 {
            return stripped
        }
        let index = stripped.index(stripped.startIndex, offsetBy: 64)
        return String(stripped[..<index]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isMetaLine(_ line: String) -> Bool {
        let normalized = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.isEmpty {
            return true
        }
        if normalized == "---" {
            return true
        }
        if normalized.hasPrefix("speaker ") || normalized.hasPrefix("**speaker ") {
            return true
        }
        let blockedPhrases = [
            "it seems like",
            "possible interpretation",
            "if this is",
            "let me know",
            "it might be helpful",
            "you might want to",
            "could consider",
            "mix of thai and english",
            "here's a possible interpretation"
        ]
        return blockedPhrases.contains { normalized.contains($0) }
    }

    private struct SummaryPayload {
        let topic: String
        let summary: [String]
        let actionItems: [String]
    }

    private static func preparedTranscript(from text: String) -> String {
        let normalized = text.replacingOccurrences(of: #"\r\n?"#, with: "\n", options: .regularExpression)
        let cleanedLines = normalized
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { line in
                if line.range(of: #"^chat\s+\d+\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil {
                    return false
                }
                if line.range(of: #"^created:"#, options: [.regularExpression, .caseInsensitive]) != nil {
                    return false
                }
                if line.range(of: #"^\[\d{2}:\d{2}:\d{2}\]\s*speaker\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
                    return false
                }
                if line.range(of: #"^speaker\s+[A-Z0-9]+\s*\([A-Za-z]+\)\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil {
                    return false
                }
                // Strip filler/noise lines: repeated single words or very short utterances.
                // e.g. "อ่ะ อ่ะ อ่ะ อ่ะ", "Right.", "I don't know."
                let words = line.split(separator: " ").map(String.init)
                if words.count >= 3 && Set(words).count == 1 { return false }
                if line.count < 10 { return false }
                return true
            }
        let joined = cleanedLines.joined(separator: "\n")
        guard joined.count > maxPreparedTranscriptCharacters else {
            return joined
        }

        let headCount = Int(Double(maxPreparedTranscriptCharacters) * 0.7)
        let tailCount = maxPreparedTranscriptCharacters - headCount
        let headEnd = joined.index(joined.startIndex, offsetBy: headCount)
        let tailStart = joined.index(joined.endIndex, offsetBy: -tailCount)
        let head = String(joined[..<headEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        let tail = String(joined[tailStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(head)\n\n[...]\n\n\(tail)"
    }

    private static func extractSummaryPayload(from text: String) -> SummaryPayload? {
        let sanitized = text
            .replacingOccurrences(of: #"(?is)<think>.*?</think>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<thinking>.*?</thinking>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?im)^\s*```(?:json|md|markdown)?\s*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?im)^\s*```\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard
            let start = sanitized.firstIndex(of: "{"),
            let end = sanitized.lastIndex(of: "}"),
            start < end
        else {
            return nil
        }

        let jsonText = String(sanitized[start...end])
        guard let data = jsonText.data(using: .utf8) else {
            return nil
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let rawTopic = firstString(in: object, keys: ["topic", "title"]) ?? ""
        var summary = firstStringArray(in: object, keys: ["summary_paragraphs", "summary", "summary_bullets", "bullets"])
        var actionItems = firstStringArray(in: object, keys: ["checklist", "action_items", "actionItems", "tasks"])

        summary = normalizeParagraphLines(summary)
        actionItems = normalizeActionItems(actionItems)

        let topic = cleanOneLine(rawTopic)
        guard !topic.isEmpty else {
            return nil
        }
        guard summary.count >= 2 else {
            return nil
        }

        return SummaryPayload(topic: topic, summary: summary, actionItems: actionItems)
    }

    private static func renderSummary(_ payload: SummaryPayload) -> String {
        var output: [String] = [
            "Topic: \(payload.topic)",
            "",
            "Summary:"
        ]
        for (index, paragraph) in payload.summary.enumerated() {
            output.append(paragraph)
            if index < payload.summary.count - 1 {
                output.append("")
            }
        }

        if !payload.actionItems.isEmpty {
            output.append("")
            output.append("Checklist:")
            output.append(contentsOf: payload.actionItems.map { "- [ ] \($0)" })
        }

        return output.joined(separator: "\n")
    }

    private static func firstString(in object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String {
                let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty {
                    return cleaned
                }
            }
        }
        return nil
    }

    private static func firstStringArray(in object: [String: Any], keys: [String]) -> [String] {
        for key in keys {
            if let array = object[key] as? [String] {
                return array
            }
            if let value = object[key] as? String {
                let pieces = value
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                if !pieces.isEmpty {
                    return pieces
                }
            }
        }
        return []
    }

    private static func normalizeParagraphLines(_ lines: [String]) -> [String] {
        var normalized: [String] = []
        for raw in lines {
            let line = cleanOneLine(
                raw
                    .replacingOccurrences(of: #"^[-*•]\s*"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"^\d+\.\s*"#, with: "", options: .regularExpression)
            )
            guard !line.isEmpty else { continue }
            normalized.append(line)
        }
        return dedupePreservingOrder(normalized).prefix(4).map { $0 }
    }

    private static func normalizeActionItems(_ lines: [String]) -> [String] {
        var normalized: [String] = []
        for raw in lines {
            let line = cleanOneLine(
                raw
                    .replacingOccurrences(of: #"^-\s*\[(?:\s|x|X)\]\s*"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"^[-*•]\s*"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"^\d+\.\s*"#, with: "", options: .regularExpression)
            )
            guard !line.isEmpty else { continue }
            normalized.append(line)
        }
        return dedupePreservingOrder(normalized).prefix(6).map { $0 }
    }

    private static func dedupePreservingOrder(_ lines: [String]) -> [String] {
        var seen: Set<String> = []
        var output: [String] = []
        for line in lines {
            let key = line.lowercased()
            if seen.insert(key).inserted {
                output.append(line)
            }
        }
        return output
    }

    private static func cleanOneLine(_ text: String) -> String {
        let whitespaceNormalized = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let commaCollapsed = collapseRepeatedCommaPhrases(in: whitespaceNormalized)
        return commaCollapsed.trimmingCharacters(in: CharacterSet(charactersIn: " ,.;"))
    }

    private static func collapseRepeatedCommaPhrases(in text: String) -> String {
        let parts = text
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count >= 8 else {
            return text
        }

        var output: [String] = []
        var previous = ""
        var run = 0
        for part in parts {
            let normalized = part.lowercased()
            if normalized == previous {
                run += 1
            } else {
                previous = normalized
                run = 1
            }
            if run <= 2 {
                output.append(part)
            }
            if output.count >= 14 {
                break
            }
        }

        if output.count >= 3 && output.count < parts.count {
            return output.joined(separator: ", ")
        }
        return text
    }

    /// Last-resort fallback when the LLM fails twice. Samples evenly-spread lines
    /// from the transcript as paragraph material — language and topic agnostic.
    private static func heuristicSummary(from transcript: String) -> String {
        let lines = transcript
            .components(separatedBy: .newlines)
            .map { cleanOneLine($0) }
            .filter { !$0.isEmpty }
            .filter { isInformativeTranscriptLine($0) }

        // Sample up to 6 evenly-spread lines to represent the full transcript.
        let sampled: [String]
        if lines.count <= 6 {
            sampled = lines
        } else {
            let step = max(lines.count / 6, 1)
            sampled = stride(from: 0, to: lines.count, by: step).prefix(6).map { lines[$0] }
        }

        let paragraphs: [String]
        if sampled.isEmpty {
            paragraphs = ["Discussion captured from transcript."]
        } else {
            let half = max(sampled.count / 2, 1)
            let p1 = sampled.prefix(half).joined(separator: " ")
            let p2 = sampled.dropFirst(half).joined(separator: " ")
            paragraphs = [p1, p2].filter { !$0.isEmpty }
        }

        var output: [String] = ["Topic: Meeting Summary", "", "Summary:"]
        for (index, paragraph) in paragraphs.enumerated() {
            output.append(paragraph)
            if index < paragraphs.count - 1 {
                output.append("")
            }
        }
        return output.joined(separator: "\n")
    }
    private static func isInformativeTranscriptLine(_ line: String) -> Bool {
        guard line.count >= 8 else {
            return false
        }
        let letters = line.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        let numbers = line.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }.count
        return (letters + numbers) >= 6
    }

    private static func shorten(_ line: String, maxLength: Int) -> String {
        guard line.count > maxLength else {
            return line
        }
        let end = line.index(line.startIndex, offsetBy: maxLength)
        return String(line[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseTopicAndSummaryParagraphs(from markdown: String) -> (topic: String?, paragraphs: [String]) {
        let lines = markdown.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let topicLine = lines.first(where: { $0.lowercased().hasPrefix("topic:") })
        let topic = topicLine?
            .replacingOccurrences(of: #"(?i)^topic:\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var inSummary = false
        var paragraphs: [String] = []
        for line in lines {
            if line.caseInsensitiveCompare("Summary:") == .orderedSame {
                inSummary = true
                continue
            }
            if line.caseInsensitiveCompare("Action Items:") == .orderedSame {
                break
            }
            if line.caseInsensitiveCompare("Checklist:") == .orderedSame {
                break
            }
            guard inSummary else { continue }
            let value = line
                .replacingOccurrences(of: #"^-\s*"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                paragraphs.append(value)
            }
        }
        return (topic, paragraphs)
    }

    private static func isLowQualitySummary(topic: String, paragraphs: [String]) -> Bool {
        // Spoken-language particles that shouldn't appear in formal meeting minutes.
        // A properly written summary avoids them; heavy presence means the model
        // copy-pasted transcript verbatim instead of paraphrasing.
        let spokenMarkers = ["ครับ", "ค่ะ", "คะ", "หรอ", "เหรอ", "เออ", "อ่า", "แล้วก็", "ใช่ไหม"]
        let topicLower = topic.lowercased()

        let metaTopicPhrases = ["it seems", "possible interpretation", "let me know", "if this is",
                               "from the transcript", "discussion captured"]
        if metaTopicPhrases.contains(where: { topicLower.contains($0) }) {
            return true
        }

        // Topic containing multiple spoken markers is almost certainly raw transcript.
        let topicMarkerCount = spokenMarkers.filter { topic.contains($0) }.count
        if topicMarkerCount >= 2 {
            return true
        }

        // A paragraph is noisy only when it has heavy spoken-language density:
        // 3+ markers, or 2+ markers in a very long paragraph, or comma-spam.
        let noisyParagraphs = paragraphs.filter { paragraph in
            let markerCount = spokenMarkers.filter { paragraph.contains($0) }.count
            let hasManyCommas = paragraph.filter { $0 == "," }.count >= 6
            return markerCount >= 3 || (markerCount >= 2 && paragraph.count > 120) || hasManyCommas
        }

        // Reject only when the majority of paragraphs are noisy.
        return noisyParagraphs.count >= max(paragraphs.count, 2)
    }

    private static func normalizedSummaryDisplay(from text: String) -> String {
        let parsed = parseTopicAndSummaryParagraphs(from: text)
        let topic = (parsed.topic ?? "Session Summary").trimmingCharacters(in: .whitespacesAndNewlines)
        let paragraphs = parsed.paragraphs
            .map { cleanOneLine($0) }
            .filter { !$0.isEmpty }
            .prefix(4)

        var output: [String] = ["Topic: \(topic)", "", "Summary:"]
        let summaryParagraphs = Array(paragraphs)
        if summaryParagraphs.isEmpty {
            output.append("Discussion points captured from this session.")
        } else {
            for (index, paragraph) in summaryParagraphs.enumerated() {
                output.append(paragraph)
                if index < summaryParagraphs.count - 1 {
                    output.append("")
                }
            }
        }

        // Preserve optional action items if present.
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let actionIndex = lines.firstIndex(where: {
            $0.caseInsensitiveCompare("Action Items:") == .orderedSame
            || $0.caseInsensitiveCompare("Checklist:") == .orderedSame
        }) {
            let actionItems = lines.dropFirst(actionIndex + 1)
                .map {
                    $0.replacingOccurrences(of: #"^-\s*\[(?:\s|x|X)\]\s*"#, with: "", options: .regularExpression)
                        .replacingOccurrences(of: #"^-\s*"#, with: "", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
                .filter { !$0.isEmpty }
            if !actionItems.isEmpty {
                output.append("")
                output.append("Checklist:")
                output.append(contentsOf: actionItems.prefix(6).map { "- [ ] \($0)" })
            }
        }

        return output.joined(separator: "\n")
    }

}
