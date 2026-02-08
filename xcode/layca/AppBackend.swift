import Foundation
import SwiftUI
import Combine

enum BackendModel: String, CaseIterable, Identifiable {
    case normalAI = "normal-ai"
    case lightAI = "light-ai"
    case highDetailAI = "high-detail-ai"

    nonisolated var id: String { rawValue }

    nonisolated var displayName: String {
        switch self {
        case .normalAI:
            return "Normal AI"
        case .lightAI:
            return "Light AI"
        case .highDetailAI:
            return "High Detail AI"
        }
    }

    nonisolated var sizeLabel: String {
        switch self {
        case .normalAI:
            return "Q8"
        case .lightAI:
            return "Q5"
        case .highDetailAI:
            return "Full"
        }
    }

    nonisolated var remoteDownloadURL: String {
        switch self {
        case .normalAI:
            return "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q8_0.bin?download=true"
        case .lightAI:
            return "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin?download=true"
        case .highDetailAI:
            return "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin?download=true"
        }
    }

    nonisolated var binFileName: String {
        switch self {
        case .normalAI:
            return "ggml-large-v3-turbo-q8_0.bin"
        case .lightAI:
            return "ggml-large-v3-turbo-q5_0.bin"
        case .highDetailAI:
            return "ggml-large-v3-turbo.bin"
        }
    }

    nonisolated var priorityOrder: Int {
        switch self {
        case .normalAI:
            return 0
        case .lightAI:
            return 1
        case .highDetailAI:
            return 2
        }
    }
}

struct PreflightConfig {
    let resolvedModel: BackendModel
    let modelPath: URL
    let prompt: String
    let languageCodes: [String]
    let fallbackNote: String?
}

enum PreflightError: LocalizedError {
    case creditExhausted
    case unknownModel
    case modelUnavailable

    var errorDescription: String? {
        switch self {
        case .creditExhausted:
            return "Hours credit is empty. Please refill before recording."
        case .unknownModel:
            return "Selected model is invalid."
        case .modelUnavailable:
            return "No installed model available. Download one from Settings."
        }
    }
}

actor ModelManager {
    private let fileManager: FileManager
    private let modelsDirectory: URL
    private var loadedModel: BackendModel?

    init(fileManager: FileManager = .default, modelsDirectory: URL? = nil) {
        self.fileManager = fileManager

        if let modelsDirectory {
            self.modelsDirectory = modelsDirectory
        } else {
            let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.modelsDirectory = documents.appendingPathComponent("Models", isDirectory: true)
        }

        try? fileManager.createDirectory(at: self.modelsDirectory, withIntermediateDirectories: true)
    }

    func modelPath(for model: BackendModel) -> URL {
        modelsDirectory.appendingPathComponent(model.binFileName)
    }

    func installedModels() -> Set<BackendModel> {
        Set(BackendModel.allCases.filter { model in
            let path = modelPath(for: model)
            return fileManager.fileExists(atPath: path.path)
        })
    }

    func installedModelIDs() -> Set<String> {
        Set(installedModels().map(\.rawValue))
    }

    func isInstalled(_ model: BackendModel) -> Bool {
        installedModels().contains(model)
    }

    func installPlaceholderModel(_ model: BackendModel) throws {
        let path = modelPath(for: model)
        if fileManager.fileExists(atPath: path.path) {
            return
        }

        let placeholder = "layca-placeholder-model:\(model.rawValue)\n"
        let data = Data(placeholder.utf8)
        try data.write(to: path, options: .atomic)
    }

    func ensureLoaded(_ model: BackendModel) async throws -> URL {
        let path = modelPath(for: model)
        guard fileManager.fileExists(atPath: path.path) else {
            throw PreflightError.modelUnavailable
        }

        if loadedModel != model {
            try await Task.sleep(nanoseconds: 300_000_000)
            loadedModel = model
        }

        return path
    }
}

struct PreflightService {
    func prepare(
        selectedModelID: String,
        languageCodes: Set<String>,
        remainingCreditSeconds: Double,
        modelManager: ModelManager
    ) async throws -> PreflightConfig {
        guard remainingCreditSeconds > 0 else {
            throw PreflightError.creditExhausted
        }

        guard let requestedModel = BackendModel(rawValue: selectedModelID) else {
            throw PreflightError.unknownModel
        }

        let installed = await modelManager.installedModels()

        let resolvedModel: BackendModel
        let fallbackNote: String?

        if installed.contains(requestedModel) {
            resolvedModel = requestedModel
            fallbackNote = nil
        } else if let fallback = installed.sorted(by: { $0.priorityOrder < $1.priorityOrder }).first {
            resolvedModel = fallback
            fallbackNote = "\(requestedModel.displayName) is not installed. Fallback to \(fallback.displayName)."
        } else {
            throw PreflightError.modelUnavailable
        }

        let modelPath = try await modelManager.ensureLoaded(resolvedModel)
        let normalizedLanguageCodes = languageCodes.map { $0.lowercased() }.sorted()
        let prompt = buildPrompt(languageCodes: normalizedLanguageCodes)

        return PreflightConfig(
            resolvedModel: resolvedModel,
            modelPath: modelPath,
            prompt: prompt,
            languageCodes: normalizedLanguageCodes,
            fallbackNote: fallbackNote
        )
    }

    private func buildPrompt(languageCodes: [String]) -> String {
        let locale = Locale(identifier: "en_US")
        let names = languageCodes.map { code in
            locale.localizedString(forLanguageCode: code) ?? code.uppercased()
        }

        if names.isEmpty {
            return "This is a meeting."
        }

        return "This is a meeting in \(names.joined(separator: ", "))."
    }
}

struct PipelineTranscriptEvent: Sendable {
    let id: UUID
    let sessionID: UUID
    let speakerID: String
    let languageID: String
    let text: String
    let startOffset: Double
    let endOffset: Double
}

enum PipelineEvent: Sendable {
    case waveform([Double])
    case timer(Double)
    case transcript(PipelineTranscriptEvent, chunkSeconds: Double)
    case stopped
}

struct LivePipelineConfig: Sendable {
    let sessionID: UUID
    let prompt: String
    let modelPath: URL
    let languageCodes: [String]
}

actor LiveSessionPipeline {
    private struct AudioFrame {
        let timestamp: Double
        let amplitude: Double
    }

    private struct WhisperResult {
        let languageID: String
        let text: String
    }

    private var continuation: AsyncStream<PipelineEvent>.Continuation?
    private var producerTask: Task<Void, Never>?
    private var isRunning = false
    private var speakerEmbeddings: [String: Double] = [:]

    func start(config: LivePipelineConfig) -> AsyncStream<PipelineEvent> {
        AsyncStream(bufferingPolicy: .bufferingNewest(500)) { continuation in
            Task {
                self.stop()
                self.startInternal(config: config, continuation: continuation)
            }
        }
    }

    func stop() {
        isRunning = false
        producerTask?.cancel()
        producerTask = nil

        continuation?.yield(.stopped)
        continuation?.finish()
        continuation = nil

        speakerEmbeddings.removeAll()
    }

    private func startInternal(config: LivePipelineConfig, continuation: AsyncStream<PipelineEvent>.Continuation) {
        self.continuation = continuation
        isRunning = true

        producerTask = Task {
            await runPipeline(config: config)
        }
    }

    private func runPipeline(config: LivePipelineConfig) async {
        let tickDuration: Double = 0.05

        var elapsed: Double = 0
        var waveform: [Double] = Array(repeating: 0.03, count: 18)
        var activeChunkFrames: [AudioFrame] = []
        var silenceSeconds: Double = 0

        while isRunning, !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 50_000_000)

            elapsed += tickDuration
            let amplitude = simulatedAmplitude(at: elapsed)

            waveform.removeFirst()
            waveform.append(amplitude)

            continuation?.yield(.waveform(waveform))
            continuation?.yield(.timer(elapsed))

            if amplitude >= 0.14 {
                activeChunkFrames.append(AudioFrame(timestamp: elapsed, amplitude: amplitude))
                silenceSeconds = 0
            } else if !activeChunkFrames.isEmpty {
                silenceSeconds += tickDuration
                if silenceSeconds >= 0.5 {
                    let chunk = activeChunkFrames
                    activeChunkFrames.removeAll(keepingCapacity: true)
                    silenceSeconds = 0
                    await processChunk(chunk, config: config)
                }
            }
        }

        if !activeChunkFrames.isEmpty {
            await processChunk(activeChunkFrames, config: config)
        }
    }

    private func processChunk(_ chunk: [AudioFrame], config: LivePipelineConfig) async {
        guard let first = chunk.first, let last = chunk.last else {
            return
        }

        let chunkSeconds = max(last.timestamp - first.timestamp + 0.05, 0.35)

        async let whisperResult = whisper(chunk: chunk, config: config)
        async let speakerID = identifySpeaker(chunk: chunk)

        let transcript = await whisperResult
        let speaker = await speakerID

        let event = PipelineTranscriptEvent(
            id: UUID(),
            sessionID: config.sessionID,
            speakerID: speaker,
            languageID: transcript.languageID,
            text: transcript.text,
            startOffset: first.timestamp,
            endOffset: first.timestamp + chunkSeconds
        )

        continuation?.yield(.transcript(event, chunkSeconds: chunkSeconds))
    }

    private func whisper(chunk: [AudioFrame], config: LivePipelineConfig) async -> WhisperResult {
        try? await Task.sleep(nanoseconds: 190_000_000)

        let languageCode = config.languageCodes.randomElement() ?? "en"

        let phraseBank: [String: [String]] = [
            "en": [
                "Let's finalize the rollout checklist before shipping.",
                "Please keep installation optional and explain storage impact.",
                "We should keep this release private until testing is complete."
            ],
            "th": [
                "สรุปแผนงานก่อนปล่อยเวอร์ชันจริงอีกครั้งครับ",
                "ขอให้ติดตั้งโมเดลเป็นตัวเลือกและบอกขนาดไฟล์ชัดเจน",
                "เดี๋ยวผมสรุปประเด็นทั้งหมดส่งในคืนนี้"
            ]
        ]

        let text = phraseBank[languageCode]?.randomElement()
            ?? phraseBank["en"]!.randomElement()!

        return WhisperResult(languageID: languageCode.uppercased(), text: text)
    }

    private func identifySpeaker(chunk: [AudioFrame]) async -> String {
        try? await Task.sleep(nanoseconds: 120_000_000)

        let embedding = chunk.map(\.amplitude).reduce(0, +) / Double(max(chunk.count, 1))

        if let existing = closestSpeaker(for: embedding, threshold: 0.055) {
            return existing
        }

        let nextIndex = speakerEmbeddings.count
        let scalar = UnicodeScalar(65 + min(nextIndex, 25)) ?? "Z".unicodeScalars.first!
        let label = "Speaker \(Character(scalar))"
        speakerEmbeddings[label] = embedding
        return label
    }

    private func closestSpeaker(for embedding: Double, threshold: Double) -> String? {
        var candidate: (label: String, distance: Double)?

        for (label, reference) in speakerEmbeddings {
            let distance = abs(reference - embedding)
            if distance <= threshold {
                if let current = candidate {
                    if distance < current.distance {
                        candidate = (label, distance)
                    }
                } else {
                    candidate = (label, distance)
                }
            }
        }

        return candidate?.label
    }

    private func simulatedAmplitude(at seconds: Double) -> Double {
        let baseline = Double.random(in: 0.01...0.06)
        let waveform = (sin(seconds * 2.1).magnitude + cos(seconds * 1.3).magnitude) * 0.22
        let speakingWindow = (Int(seconds * 10) % 32) < 22

        if speakingWindow {
            return min(1, baseline + waveform + Double.random(in: 0.08...0.18))
        }

        return min(0.12, baseline + Double.random(in: 0...0.03))
    }
}

actor SessionStore {
    enum SessionStatus: String {
        case recording
        case processing
        case ready
        case failed
    }

    private struct StoredSession {
        let id: UUID
        var title: String
        let createdAt: Date
        var rows: [TranscriptRow]
        var speakers: [String: SpeakerProfile]
        var languageHints: [String]
        var modelID: String
        var audioFilePath: String
        var segmentsFilePath: String
        var durationSeconds: Double
        var status: SessionStatus
    }

    private struct SpeakerProfile {
        let label: String
        let colorHex: String
        let avatarSymbol: String
    }

    private let fileManager: FileManager
    private let sessionsDirectory: URL

    private var sessions: [UUID: StoredSession] = [:]
    private var sessionOrder: [UUID] = []

    init(fileManager: FileManager = .default, sessionsDirectory: URL? = nil) {
        self.fileManager = fileManager

        if let sessionsDirectory {
            self.sessionsDirectory = sessionsDirectory
        } else {
            let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.sessionsDirectory = documents.appendingPathComponent("Sessions", isDirectory: true)
        }
        try? fileManager.createDirectory(at: self.sessionsDirectory, withIntermediateDirectories: true)
    }

    func createSession(title: String, languageHints: [String], modelID: String) throws -> UUID {
        let id = UUID()
        let sessionDirectory = sessionsDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)

        let audioFileURL = sessionDirectory.appendingPathComponent("session_full.m4a")
        if !fileManager.fileExists(atPath: audioFileURL.path) {
            fileManager.createFile(atPath: audioFileURL.path, contents: Data())
        }

        let segmentsURL = sessionDirectory.appendingPathComponent("segments.json")
        if !fileManager.fileExists(atPath: segmentsURL.path) {
            fileManager.createFile(atPath: segmentsURL.path, contents: Data("[]".utf8))
        }

        let session = StoredSession(
            id: id,
            title: title,
            createdAt: Date(),
            rows: [],
            speakers: [:],
            languageHints: languageHints,
            modelID: modelID,
            audioFilePath: audioFileURL.path,
            segmentsFilePath: segmentsURL.path,
            durationSeconds: 0,
            status: .ready
        )

        sessions[id] = session
        sessionOrder.insert(id, at: 0)

        return id
    }

    func setSessionStatus(_ status: SessionStatus, for sessionID: UUID) {
        guard var session = sessions[sessionID] else {
            return
        }

        session.status = status
        sessions[sessionID] = session
    }

    func updateSessionConfig(sessionID: UUID, languageHints: [String], modelID: String) {
        guard var session = sessions[sessionID] else {
            return
        }

        session.languageHints = languageHints
        session.modelID = modelID
        sessions[sessionID] = session
    }

    func renameSession(sessionID: UUID, title: String) {
        guard var session = sessions[sessionID] else {
            return
        }

        session.title = title
        sessions[sessionID] = session
    }

    func snapshotSessions() -> [ChatSession] {
        sessionOrder.compactMap { id in
            guard let session = sessions[id] else {
                return nil
            }

            return ChatSession(
                id: session.id,
                title: session.title,
                createdAt: session.createdAt,
                rows: session.rows
            )
        }
    }

    func transcriptRows(for sessionID: UUID) -> [TranscriptRow] {
        sessions[sessionID]?.rows ?? []
    }

    func appendTranscript(sessionID: UUID, event: PipelineTranscriptEvent) {
        guard var session = sessions[sessionID] else {
            return
        }

        let profile = speakerProfile(for: event.speakerID, in: &session.speakers)
        let baseColor = Color(hex: profile.colorHex)

        let row = TranscriptRow(
            speaker: profile.label,
            text: event.text,
            time: Self.formatTimestamp(seconds: event.startOffset),
            language: event.languageID,
            avatarSymbol: profile.avatarSymbol,
            avatarPalette: [baseColor, .white.opacity(0.72)]
        )

        session.rows.append(row)
        session.durationSeconds = max(session.durationSeconds, event.endOffset)
        persistSegmentsSnapshot(for: session)
        sessions[sessionID] = session
    }

    private func speakerProfile(for label: String, in table: inout [String: SpeakerProfile]) -> SpeakerProfile {
        if let profile = table[label] {
            return profile
        }

        let colors = ["#F97316", "#0EA5E9", "#10B981", "#EF4444", "#6366F1", "#D97706", "#14B8A6"]
        let symbols = [
            "person.fill",
            "person.2.fill",
            "person.crop.circle.fill.badge.checkmark",
            "person.crop.circle.badge.clock",
            "person.crop.circle.badge.questionmark"
        ]

        let colorHex = colors.randomElement() ?? "#0EA5E9"
        let symbol = symbols.randomElement() ?? "person.fill"

        let profile = SpeakerProfile(label: label, colorHex: colorHex, avatarSymbol: symbol)
        table[label] = profile
        return profile
    }

    private static func formatTimestamp(seconds: Double) -> String {
        let clamped = Int(max(seconds, 0).rounded(.down))
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        let secs = clamped % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }

    private func persistSegmentsSnapshot(for session: StoredSession) {
        struct SegmentSnapshot: Codable {
            let speaker: String
            let text: String
            let time: String
            let language: String
        }

        let snapshots = session.rows.map { row in
            SegmentSnapshot(
                speaker: row.speaker,
                text: row.text,
                time: row.time,
                language: row.language
            )
        }

        guard let data = try? JSONEncoder().encode(snapshots) else {
            return
        }

        let url = URL(fileURLWithPath: session.segmentsFilePath)
        try? data.write(to: url, options: .atomic)
    }
}

@MainActor
final class AppBackend: ObservableObject {
    @Published var isRecording = false
    @Published var recordingSeconds: Double = 0
    @Published var waveformBars: [Double] = Array(repeating: 0.03, count: 9)

    @Published var selectedLanguageCodes: Set<String> = ["en", "th"]
    @Published var languageSearchText = ""

    @Published var selectedModelID = BackendModel.normalAI.rawValue
    @Published var downloadedModelIDs: Set<String> = []
    @Published var downloadingModelID: String?
    @Published var modelDownloadProgress: Double = 0

    @Published var totalHours: Double = 40
    @Published var usedHours: Double = 12.6

    @Published var isICloudSyncEnabled = true
    @Published var isRestoringPurchases = false
    @Published var restoreStatusMessage: String?

    @Published var sessions: [ChatSession] = []
    @Published var activeSessionID: UUID?
    @Published var activeTranscriptRows: [TranscriptRow] = []

    @Published var preflightStatusMessage: String?

    private let modelManager = ModelManager()
    private let preflightService = PreflightService()
    private let pipeline = LiveSessionPipeline()
    private let sessionStore = SessionStore()

    private var streamTask: Task<Void, Never>?
    private var chatCounter = 0

    init() {
        Task {
            await bootstrap()
        }
    }

    var modelCatalog: [ModelOption] {
        BackendModel.allCases.map { model in
            ModelOption(
                id: model.rawValue,
                name: model.displayName,
                sizeLabel: model.sizeLabel,
                remoteDownloadURL: model.remoteDownloadURL
            )
        }
    }

    var activeSessionTitle: String {
        sessions.first(where: { $0.id == activeSessionID })?.title ?? "Chat"
    }

    var activeSessionDateText: String {
        sessions.first(where: { $0.id == activeSessionID })?.formattedDate ?? "No active chat"
    }

    var recordingTimeText: String {
        let clamped = Int(max(recordingSeconds, 0).rounded(.down))
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        let seconds = clamped % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    func bootstrap() async {
        await refreshInstalledModels()
        await createNewSessionIfNeeded()
    }

    func toggleLanguageFocus(_ code: String) {
        let normalized = code.lowercased()
        if selectedLanguageCodes.contains(normalized) {
            selectedLanguageCodes.remove(normalized)
        } else {
            selectedLanguageCodes.insert(normalized)
        }
    }

    func selectModel(_ option: ModelOption) {
        guard downloadingModelID == nil else {
            return
        }

        guard let model = BackendModel(rawValue: option.id) else {
            return
        }

        if downloadedModelIDs.contains(model.rawValue) {
            selectedModelID = model.rawValue
            return
        }

        downloadingModelID = model.rawValue
        modelDownloadProgress = 0

        Task {
            for step in 1...14 {
                try? await Task.sleep(nanoseconds: 180_000_000)
                await MainActor.run {
                    modelDownloadProgress = Double(step) / 14.0
                }
            }

            try? await modelManager.installPlaceholderModel(model)
            let installed = await modelManager.installedModelIDs()

            await MainActor.run {
                downloadedModelIDs = installed
                selectedModelID = model.rawValue
                downloadingModelID = nil
                modelDownloadProgress = 0
                preflightStatusMessage = nil
            }
        }
    }

    func restorePurchases() {
        guard !isRestoringPurchases else {
            return
        }

        isRestoringPurchases = true
        restoreStatusMessage = nil

        Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            await MainActor.run {
                isRestoringPurchases = false
                restoreStatusMessage = "Restore complete. iCloud and purchases are synced."
            }
        }
    }

    func startNewChat() {
        Task {
            await createSessionAndActivate()
        }
    }

    func activateSession(_ session: ChatSession) {
        activeSessionID = session.id
        activeTranscriptRows = session.rows
    }

    func renameActiveSessionTitle(_ newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let activeSessionID else {
            return
        }

        Task {
            await sessionStore.renameSession(sessionID: activeSessionID, title: trimmed)
            await refreshSessionsFromStore()
        }
    }

    func toggleRecording() {
        if isRecording {
            Task {
                await stopRecording()
            }
        } else {
            Task {
                await startRecording()
            }
        }
    }

    private func startRecording() async {
        guard !isRecording else {
            return
        }

        if activeSessionID == nil {
            await createSessionAndActivate()
        }

        guard let sessionID = activeSessionID else {
            return
        }

        let remainingSeconds = max(totalHours - usedHours, 0) * 3600

        do {
            let config = try await preflightService.prepare(
                selectedModelID: selectedModelID,
                languageCodes: selectedLanguageCodes,
                remainingCreditSeconds: remainingSeconds,
                modelManager: modelManager
            )

            selectedModelID = config.resolvedModel.rawValue
            preflightStatusMessage = config.fallbackNote

            await sessionStore.updateSessionConfig(
                sessionID: sessionID,
                languageHints: config.languageCodes,
                modelID: config.resolvedModel.rawValue
            )
            await sessionStore.setSessionStatus(.recording, for: sessionID)

            let stream = await pipeline.start(
                config: LivePipelineConfig(
                    sessionID: sessionID,
                    prompt: config.prompt,
                    modelPath: config.modelPath,
                    languageCodes: config.languageCodes
                )
            )

            isRecording = true
            recordingSeconds = 0
            streamTask?.cancel()
            streamTask = consume(stream: stream, sessionID: sessionID)
        } catch {
            preflightStatusMessage = error.localizedDescription
        }
    }

    private func stopRecording() async {
        await pipeline.stop()
        streamTask?.cancel()
        streamTask = nil

        if let activeSessionID {
            await sessionStore.setSessionStatus(.ready, for: activeSessionID)
        }

        isRecording = false
        await refreshSessionsFromStore()
    }

    private func consume(stream: AsyncStream<PipelineEvent>, sessionID: UUID) -> Task<Void, Never> {
        Task { [weak self] in
            guard let self else {
                return
            }

            for await event in stream {
                if Task.isCancelled {
                    return
                }
                await self.handle(event: event, sessionID: sessionID)
            }
        }
    }

    private func handle(event: PipelineEvent, sessionID: UUID) async {
        switch event {
        case .waveform(let values):
            waveformBars = Self.compactWaveform(from: values, bars: 9)

        case .timer(let seconds):
            recordingSeconds = seconds

        case .transcript(let transcript, let chunkSeconds):
            await sessionStore.appendTranscript(sessionID: sessionID, event: transcript)
            await refreshSessionsFromStore()

            usedHours = min(totalHours, usedHours + (chunkSeconds / 3600))
            if usedHours >= totalHours {
                preflightStatusMessage = "Hours credit exhausted. Recording stopped."
                await stopRecording()
                return
            }

            if isICloudSyncEnabled {
                Task.detached {
                    try? await Task.sleep(nanoseconds: 120_000_000)
                }
            }

        case .stopped:
            isRecording = false
        }
    }

    private func refreshInstalledModels() async {
        downloadedModelIDs = await modelManager.installedModelIDs()
    }

    private func createNewSessionIfNeeded() async {
        if sessions.isEmpty {
            await createSessionAndActivate()
        }
    }

    private func createSessionAndActivate() async {
        chatCounter += 1

        let defaultModel = BackendModel(rawValue: selectedModelID)?.rawValue ?? BackendModel.normalAI.rawValue

        if let id = try? await sessionStore.createSession(
            title: "Chat \(chatCounter)",
            languageHints: Array(selectedLanguageCodes),
            modelID: defaultModel
        ) {
            activeSessionID = id
            await refreshSessionsFromStore()
        }
    }

    private func refreshSessionsFromStore() async {
        let snapshots = await sessionStore.snapshotSessions()
        sessions = snapshots

        if activeSessionID == nil {
            activeSessionID = snapshots.first?.id
        }

        if let activeSessionID {
            activeTranscriptRows = await sessionStore.transcriptRows(for: activeSessionID)
        } else {
            activeTranscriptRows = []
        }
    }

    private static func compactWaveform(from source: [Double], bars: Int) -> [Double] {
        guard bars > 0 else {
            return []
        }
        guard !source.isEmpty else {
            return Array(repeating: 0.03, count: bars)
        }

        let window = max(source.count / bars, 1)
        var result: [Double] = []
        result.reserveCapacity(bars)

        var index = 0
        while index < source.count, result.count < bars {
            let upper = min(index + window, source.count)
            let slice = source[index..<upper]
            let average = slice.reduce(0, +) / Double(slice.count)
            result.append(min(max(average, 0.02), 1))
            index = upper
        }

        while result.count < bars {
            result.append(result.last ?? 0.03)
        }

        return result
    }
}

private extension Color {
    nonisolated init(hex: String) {
        let normalized = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")

        var value: UInt64 = 0
        Scanner(string: normalized).scanHexInt64(&value)

        let red = Double((value & 0xFF0000) >> 16) / 255
        let green = Double((value & 0x00FF00) >> 8) / 255
        let blue = Double(value & 0x0000FF) / 255

        self.init(red: red, green: green, blue: blue)
    }
}
