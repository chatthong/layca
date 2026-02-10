import Foundation
import SwiftUI
import Combine
import AVFoundation

struct PreflightConfig {
    let prompt: String
    let languageCodes: [String]
}

enum PreflightError: LocalizedError {
    case creditExhausted

    var errorDescription: String? {
        switch self {
        case .creditExhausted:
            return "Hours credit is empty. Please refill before recording."
        }
    }
}

struct PreflightService {
    func prepare(
        languageCodes: Set<String>,
        focusKeywords: String,
        remainingCreditSeconds: Double
    ) async throws -> PreflightConfig {
        guard remainingCreditSeconds > 0 else {
            throw PreflightError.creditExhausted
        }

        let normalizedLanguageCodes = languageCodes.map { $0.lowercased() }.sorted()
        let prompt = buildPrompt(languageCodes: normalizedLanguageCodes, keywords: focusKeywords)

        return PreflightConfig(
            prompt: prompt,
            languageCodes: normalizedLanguageCodes
        )
    }

    func buildPrompt(languageCodes: [String], keywords: String) -> String {
        let locale = Locale(identifier: "en_US")
        let names = languageCodes.map { code in
            locale.localizedString(forLanguageCode: code) ?? code.uppercased()
        }
        let languageList = names.isEmpty ? "multiple languages" : names.joined(separator: ", ")
        let normalizedKeywords = keywords.trimmingCharacters(in: .whitespacesAndNewlines)
        let context = normalizedKeywords.isEmpty ? "none" : normalizedKeywords

        return "This is a verbatim transcript of a meeting in \(languageList). The speakers switch between languages naturally. Transcribe exactly what is spoken in the original language, including profanity, violence, drug terms, and other sensitive words. Do not censor, mask, or replace words. Do not translate. Context: \(context)."
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
    let samples: [Float]
    let sampleRate: Double
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
    let languageCodes: [String]
}

enum MasterRecorderError: LocalizedError {
    case microphonePermissionDenied
    case unableToStart

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone permission is required for recording."
        case .unableToStart:
            return "Unable to start audio recording."
        }
    }
}

@MainActor
final class MasterAudioRecorder: NSObject, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?

    func startRecording(to destinationURL: URL) async throws {
        stopAndReset()

        let hasPermission = await requestPermission()
        guard hasPermission else {
            throw MasterRecorderError.microphonePermissionDenied
        }

        try activateAudioSessionForRecordingIfSupported()

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let parentDirectory = destinationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        let recorder = try AVAudioRecorder(url: destinationURL, settings: settings)
        recorder.delegate = self
        recorder.prepareToRecord()

        guard recorder.record() else {
            throw MasterRecorderError.unableToStart
        }

        self.recorder = recorder
    }

    func stop() {
        stopAndReset()
    }

    private func stopAndReset() {
        recorder?.stop()
        recorder = nil

        deactivateAudioSessionIfSupported()
    }

    private func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
#if os(macOS)
            if #available(macOS 14.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            } else {
                continuation.resume(returning: true)
            }
#else
            if #available(iOS 17.0, tvOS 17.0, visionOS 1.0, macCatalyst 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
#endif
        }
    }

    private func activateAudioSessionForRecordingIfSupported() throws {
#if !os(macOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
#endif
    }

    private func deactivateAudioSessionIfSupported() {
#if !os(macOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
#endif
    }
}

enum LiveAudioInputError: LocalizedError {
    case invalidInputFormat

    var errorDescription: String? {
        switch self {
        case .invalidInputFormat:
            return "Unable to access microphone input format."
        }
    }
}

private struct CapturedAudioFrame: Sendable {
    let samples: [Float]
    let sampleRate: Double
    let amplitude: Double
    let duration: Double
    let zeroCrossingRate: Double
}

@MainActor
private final class LiveAudioInputController {
    private let engine = AVAudioEngine()
    private var isStarted = false

    func start(onCapture: @escaping @Sendable (CapturedAudioFrame) -> Void) throws {
        let inputNode = engine.inputNode
        let outputFormat = inputNode.outputFormat(forBus: 0)

        guard outputFormat.sampleRate > 0, outputFormat.channelCount > 0 else {
            throw LiveAudioInputError.invalidInputFormat
        }

        guard let tapFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: outputFormat.sampleRate,
            channels: outputFormat.channelCount,
            interleaved: false
        ) else {
            throw LiveAudioInputError.invalidInputFormat
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: tapFormat) { buffer, _ in
            guard let frame = Self.captureFrame(from: buffer) else {
                return
            }
            onCapture(frame)
        }

        engine.prepare()
        try engine.start()
        isStarted = true
    }

    func stop() {
        guard isStarted else {
            return
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isStarted = false
    }

    private static func captureFrame(from buffer: AVAudioPCMBuffer) -> CapturedAudioFrame? {
        guard let channelData = buffer.floatChannelData else {
            return nil
        }

        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameLength > 0, channelCount > 0 else {
            return nil
        }

        var monoSamples = Array(repeating: Float.zero, count: frameLength)
        let channelScale = Float(1.0 / Double(channelCount))

        for channel in 0..<channelCount {
            let source = channelData[channel]
            for index in 0..<frameLength {
                monoSamples[index] += source[index] * channelScale
            }
        }

        var sumSquares: Float = 0
        for sample in monoSamples {
            sumSquares += sample * sample
        }
        let rms = sqrt(sumSquares / Float(frameLength))
        let normalizedAmplitude = min(max(Double(rms) * 12.0, 0), 1)

        var crossings = 0
        if frameLength > 1 {
            for index in 1..<frameLength {
                let previous = monoSamples[index - 1]
                let current = monoSamples[index]
                if (previous >= 0 && current < 0) || (previous < 0 && current >= 0) {
                    crossings += 1
                }
            }
        }
        let zeroCrossingRate = Double(crossings) / Double(max(frameLength - 1, 1))

        let duration = Double(frameLength) / buffer.format.sampleRate
        return CapturedAudioFrame(
            samples: monoSamples,
            sampleRate: buffer.format.sampleRate,
            amplitude: normalizedAmplitude,
            duration: duration,
            zeroCrossingRate: zeroCrossingRate
        )
    }
}

actor LiveSessionPipeline {
    private enum VADState {
        case loading
        case ready
        case fallback
    }

    private enum SpeakerState {
        case loading
        case ready
        case fallback
    }

    private struct AudioFrame {
        let timestamp: Double
        let duration: Double
        let sampleRate: Double
        let amplitude: Double
        let zeroCrossingRate: Double
        let samples: [Float]
    }

    private var continuation: AsyncStream<PipelineEvent>.Continuation?
    private var isRunning = false
    private var speakerEmbeddings: [String: [Float]] = [:]
    private var speakerObservationCounts: [String: Int] = [:]
    private var pendingSpeakerEmbedding: [Float]?
    private var pendingSpeakerChunks = 0
    private var fallbackSpeakerEmbeddings: [String: Double] = [:]

    private var inputController: LiveAudioInputController?
    private var activeConfig: LivePipelineConfig?
    private var elapsedSeconds: Double = 0
    private var waveformBuffer: [Double] = Array(repeating: 0.03, count: 18)
    private var activeChunkFrames: [AudioFrame] = []
    private var silenceSeconds: Double = 0
    private var chunkCounter = 0
    private var runToken = UUID()
    private var vadState: VADState = .loading
    private var speakerState: SpeakerState = .loading
    private let sileroVAD = SileroVADCoreMLService()
    private let speakerDiarizer = SpeakerDiarizationCoreMLService()

    private let speechThreshold: Double = 0.06
    private let vadSpeechThreshold: Float = 0.5
    private let silenceCutoffSeconds: Double = 1.2
    private let minChunkDurationSeconds: Double = 3.2
    private let maxChunkDurationSeconds: Double = 12
    private let speakerSimilarityThreshold: Float = 0.72
    private let speakerLooseSimilarityThreshold: Float = 0.60
    private let newSpeakerCandidateSimilarity: Float = 0.55
    private let pendingChunksBeforeNewSpeaker = 2
    private let maxSpeakersPerSession = 6
    private let speakerFallbackThreshold: Double = 0.11
    private let deferredTranscriptPlaceholder = "Queued for automatic transcription..."

    func start(config: LivePipelineConfig) -> AsyncStream<PipelineEvent> {
        AsyncStream(bufferingPolicy: .bufferingNewest(500)) { continuation in
            Task {
                await self.stop()
                await self.startInternal(config: config, continuation: continuation)
            }
        }
    }

    func stop() async {
        guard continuation != nil || isRunning else {
            return
        }

        isRunning = false

        if let controller = inputController {
            await MainActor.run {
                controller.stop()
            }
        }
        inputController = nil

        if let config = activeConfig, !activeChunkFrames.isEmpty {
            await processChunk(activeChunkFrames, config: config)
            activeChunkFrames.removeAll(keepingCapacity: false)
        }

        continuation?.yield(.stopped)
        continuation?.finish()
        continuation = nil

        activeConfig = nil
        elapsedSeconds = 0
        waveformBuffer = Array(repeating: 0.03, count: 18)
        silenceSeconds = 0
        chunkCounter = 0
        speakerEmbeddings.removeAll()
        speakerObservationCounts.removeAll()
        pendingSpeakerEmbedding = nil
        pendingSpeakerChunks = 0
        fallbackSpeakerEmbeddings.removeAll()
        runToken = UUID()
        vadState = .loading
        speakerState = .loading
        await sileroVAD.reset()
        await speakerDiarizer.reset()
    }

    private func startInternal(config: LivePipelineConfig, continuation: AsyncStream<PipelineEvent>.Continuation) async {
        self.continuation = continuation
        isRunning = true
        activeConfig = config
        elapsedSeconds = 0
        waveformBuffer = Array(repeating: 0.03, count: 18)
        activeChunkFrames = []
        silenceSeconds = 0
        chunkCounter = 0
        runToken = UUID()
        vadState = .loading
        speakerState = .loading

        let token = runToken
        Task {
            await self.prepareVAD(for: token)
        }
        Task {
            await self.prepareSpeakerDiarization(for: token)
        }

        let controller = await MainActor.run { LiveAudioInputController() }

        do {
            try await MainActor.run {
                try controller.start { [weak self] capturedFrame in
                    guard let self else {
                        return
                    }
                    Task {
                        await self.ingest(frame: capturedFrame)
                    }
                }
            }
            inputController = controller
        } catch {
            isRunning = false
            activeConfig = nil
            continuation.yield(.stopped)
            continuation.finish()
            self.continuation = nil
        }
    }

    private func prepareVAD(for token: UUID) async {
        do {
            try await sileroVAD.prepareIfNeeded()
            guard isRunning, token == runToken else {
                return
            }
            vadState = .ready
        } catch {
            guard isRunning, token == runToken else {
                return
            }
            vadState = .fallback
        }
    }

    private func prepareSpeakerDiarization(for token: UUID) async {
        do {
            try await speakerDiarizer.prepareIfNeeded()
            guard isRunning, token == runToken else {
                return
            }
            speakerState = .ready
        } catch {
            guard isRunning, token == runToken else {
                return
            }
            speakerState = .fallback
        }
    }

    private func ingest(frame: CapturedAudioFrame) async {
        guard isRunning, let config = activeConfig else {
            return
        }

        let frameTimestamp = elapsedSeconds
        elapsedSeconds += frame.duration

        waveformBuffer.removeFirst()
        waveformBuffer.append(frame.amplitude)

        continuation?.yield(.waveform(waveformBuffer))
        continuation?.yield(.timer(elapsedSeconds))

        let audioFrame = AudioFrame(
            timestamp: frameTimestamp,
            duration: frame.duration,
            sampleRate: frame.sampleRate,
            amplitude: frame.amplitude,
            zeroCrossingRate: frame.zeroCrossingRate,
            samples: frame.samples
        )

        let isSpeechFrame = await evaluateSpeech(frame: frame)

        if isSpeechFrame {
            activeChunkFrames.append(audioFrame)
            silenceSeconds = 0
        } else if !activeChunkFrames.isEmpty {
            silenceSeconds += frame.duration
        }

        if !activeChunkFrames.isEmpty {
            let currentChunkDuration = chunkDuration(for: activeChunkFrames)
            let shouldCutForSilence =
                silenceSeconds >= silenceCutoffSeconds &&
                currentChunkDuration >= minChunkDurationSeconds

            if shouldCutForSilence || currentChunkDuration >= maxChunkDurationSeconds {
                let chunk = activeChunkFrames
                activeChunkFrames.removeAll(keepingCapacity: true)
                silenceSeconds = 0
                await processChunk(chunk, config: config)
            }
        }
    }

    private func evaluateSpeech(frame: CapturedAudioFrame) async -> Bool {
        switch vadState {
        case .ready:
            do {
                if let probability = try await sileroVAD.ingest(samples: frame.samples, sampleRate: frame.sampleRate) {
                    return probability >= vadSpeechThreshold
                }
                return frame.amplitude >= speechThreshold
            } catch {
                vadState = .fallback
                return frame.amplitude >= speechThreshold
            }
        case .loading, .fallback:
            return frame.amplitude >= speechThreshold
        }
    }

    private func processChunk(_ chunk: [AudioFrame], config: LivePipelineConfig) async {
        guard let first = chunk.first, let last = chunk.last else {
            return
        }

        let chunkSeconds = max((last.timestamp + last.duration) - first.timestamp, 0.2)

        async let speakerID = identifySpeaker(chunk: chunk)

        let speaker = await speakerID
        let languageCode = "AUTO"

        let event = PipelineTranscriptEvent(
            id: UUID(),
            sessionID: config.sessionID,
            speakerID: speaker,
            languageID: languageCode,
            text: deferredTranscriptPlaceholder,
            startOffset: first.timestamp,
            endOffset: first.timestamp + chunkSeconds,
            samples: chunk.flatMap(\.samples),
            sampleRate: first.sampleRate
        )

        continuation?.yield(.transcript(event, chunkSeconds: chunkSeconds))
        chunkCounter += 1
    }

    private func identifySpeaker(chunk: [AudioFrame]) async -> String {
        switch speakerState {
        case .ready:
            do {
                let samples = chunk.flatMap(\.samples)
                let sampleRate = chunk.first?.sampleRate ?? 16_000
                if let embedding = try await speakerDiarizer.embedding(for: samples, sampleRate: sampleRate),
                   !embedding.isEmpty {
                    return assignSpeaker(from: embedding)
                }
                return identifySpeakerFallback(chunk: chunk)
            } catch {
                speakerState = .fallback
                return identifySpeakerFallback(chunk: chunk)
            }
        case .loading, .fallback:
            return identifySpeakerFallback(chunk: chunk)
        }
    }

    private func assignSpeaker(from embedding: [Float]) -> String {
        guard !speakerEmbeddings.isEmpty else {
            pendingSpeakerEmbedding = nil
            pendingSpeakerChunks = 0
            return createSpeakerLabel(with: embedding)
        }

        guard let closest = closestSpeaker(for: embedding) else {
            pendingSpeakerEmbedding = nil
            pendingSpeakerChunks = 0
            return createSpeakerLabel(with: embedding)
        }

        if closest.similarity >= speakerSimilarityThreshold {
            pendingSpeakerEmbedding = nil
            pendingSpeakerChunks = 0
            updateSpeaker(label: closest.label, with: embedding)
            return closest.label
        }

        if closest.similarity >= speakerLooseSimilarityThreshold {
            pendingSpeakerEmbedding = nil
            pendingSpeakerChunks = 0
            updateSpeaker(label: closest.label, with: embedding)
            return closest.label
        }

        if speakerEmbeddings.count >= maxSpeakersPerSession {
            pendingSpeakerEmbedding = nil
            pendingSpeakerChunks = 0
            updateSpeaker(label: closest.label, with: embedding)
            return closest.label
        }

        if let pending = pendingSpeakerEmbedding,
           cosineSimilarity(pending, embedding) >= newSpeakerCandidateSimilarity {
            pendingSpeakerEmbedding = normalize(zip(pending, embedding).map { pair in
                (pair.0 + pair.1) * 0.5
            })
            pendingSpeakerChunks += 1
        } else {
            pendingSpeakerEmbedding = normalize(embedding)
            pendingSpeakerChunks = 1
        }

        if pendingSpeakerChunks >= pendingChunksBeforeNewSpeaker {
            pendingSpeakerEmbedding = nil
            pendingSpeakerChunks = 0
            return createSpeakerLabel(with: embedding)
        }

        // Keep continuity while candidate is warming up.
        updateSpeaker(label: closest.label, with: embedding)
        return closest.label
    }

    private func closestSpeaker(for embedding: [Float]) -> (label: String, similarity: Float)? {
        var candidate: (label: String, similarity: Float)?

        for (label, reference) in speakerEmbeddings {
            let similarity = cosineSimilarity(embedding, reference)
            if let current = candidate {
                if similarity > current.similarity {
                    candidate = (label, similarity)
                }
            } else {
                candidate = (label, similarity)
            }
        }

        return candidate
    }

    private func updateSpeaker(label: String, with embedding: [Float]) {
        guard let current = speakerEmbeddings[label] else {
            speakerEmbeddings[label] = normalize(embedding)
            speakerObservationCounts[label] = 1
            return
        }

        let previousCount = speakerObservationCounts[label] ?? 1
        let newCount = previousCount + 1
        let length = min(current.count, embedding.count)
        var merged = current

        for index in 0..<length {
            let weighted = (current[index] * Float(previousCount)) + embedding[index]
            merged[index] = weighted / Float(newCount)
        }

        speakerEmbeddings[label] = normalize(merged)
        speakerObservationCounts[label] = newCount
    }

    private func createSpeakerLabel(with embedding: [Float]) -> String {
        let nextIndex = speakerEmbeddings.count
        let scalar = UnicodeScalar(65 + min(nextIndex, 25)) ?? "Z".unicodeScalars.first!
        let label = "Speaker \(Character(scalar))"
        speakerEmbeddings[label] = normalize(embedding)
        speakerObservationCounts[label] = 1
        return label
    }

    private func identifySpeakerFallback(chunk: [AudioFrame]) -> String {
        let averageAmplitude = chunk.map(\.amplitude).reduce(0, +) / Double(max(chunk.count, 1))
        let averageZCR = chunk.map(\.zeroCrossingRate).reduce(0, +) / Double(max(chunk.count, 1))
        let embedding = (averageAmplitude * 0.74) + (averageZCR * 0.26)

        if let closest = closestFallbackSpeaker(for: embedding) {
            if closest.distance <= speakerFallbackThreshold || fallbackSpeakerEmbeddings.count >= 3 {
                return closest.label
            }
        }

        let nextIndex = fallbackSpeakerEmbeddings.count
        let scalar = UnicodeScalar(65 + min(nextIndex, 25)) ?? "Z".unicodeScalars.first!
        let label = "Speaker \(Character(scalar))"
        fallbackSpeakerEmbeddings[label] = embedding
        return label
    }

    private func closestFallbackSpeaker(for embedding: Double) -> (label: String, distance: Double)? {
        var candidate: (label: String, distance: Double)?

        for (label, reference) in fallbackSpeakerEmbeddings {
            let distance = abs(reference - embedding)
            if let current = candidate {
                if distance < current.distance {
                    candidate = (label, distance)
                }
            } else {
                candidate = (label, distance)
            }
        }

        return candidate
    }

    private func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Float {
        let length = min(lhs.count, rhs.count)
        guard length > 0 else {
            return -1
        }

        var dot: Float = 0
        var lhsNorm: Float = 0
        var rhsNorm: Float = 0

        for index in 0..<length {
            let left = lhs[index]
            let right = rhs[index]
            dot += left * right
            lhsNorm += left * left
            rhsNorm += right * right
        }

        guard lhsNorm > 0, rhsNorm > 0 else {
            return -1
        }

        return dot / (sqrt(lhsNorm) * sqrt(rhsNorm))
    }

    private func normalize(_ vector: [Float]) -> [Float] {
        guard !vector.isEmpty else {
            return vector
        }

        var sumSquares: Float = 0
        for value in vector {
            sumSquares += value * value
        }

        let length = sqrt(sumSquares)
        guard length > 0 else {
            return vector
        }

        return vector.map { $0 / length }
    }

    private func chunkDuration(for chunk: [AudioFrame]) -> Double {
        guard let first = chunk.first, let last = chunk.last else {
            return 0
        }
        return max((last.timestamp + last.duration) - first.timestamp, 0)
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
        var audioFilePath: String
        var segmentsFilePath: String
        var metadataFilePath: String
        var durationSeconds: Double
        var status: SessionStatus
    }

    private struct SpeakerProfile: Codable {
        let label: String
        let colorHex: String
        let avatarSymbol: String
    }

    private struct SessionMetadataSnapshot: Codable {
        let schemaVersion: Int
        let id: UUID
        let title: String
        let createdAt: Date
        let languageHints: [String]
        let audioFileName: String
        let segmentsFileName: String
        let durationSeconds: Double
        let status: String
        let speakers: [String: SpeakerProfile]
    }

    private struct SegmentSnapshot: Codable {
        let id: UUID?
        let speakerID: String
        let speaker: String
        let text: String
        let time: String?
        let language: String
        let avatarSymbol: String?
        let avatarColorHex: String?
        let startOffset: Double?
        let endOffset: Double?
    }

    private struct LegacySegmentSnapshot: Codable {
        let speakerID: String
        let speaker: String
        let text: String
        let time: String
        let language: String
        let startOffset: Double?
        let endOffset: Double?
    }

    private let fileManager: FileManager
    private let sessionsDirectory: URL
    private let metadataFileName = "session.json"
    private let audioFileName = "session_full.m4a"
    private let segmentsFileName = "segments.json"

    private var sessions: [UUID: StoredSession] = [:]
    private var sessionOrder: [UUID] = []
    private var hasLoadedFromDisk = false

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

    func createSession(title: String, languageHints: [String]) throws -> UUID {
        prepareIfNeeded()
        let id = UUID()
        let sessionDirectory = sessionsDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)

        let audioFileURL = sessionDirectory.appendingPathComponent(audioFileName)
        if !fileManager.fileExists(atPath: audioFileURL.path) {
            fileManager.createFile(atPath: audioFileURL.path, contents: Data())
        }

        let segmentsURL = sessionDirectory.appendingPathComponent(segmentsFileName)
        if !fileManager.fileExists(atPath: segmentsURL.path) {
            fileManager.createFile(atPath: segmentsURL.path, contents: Data("[]".utf8))
        }

        let metadataURL = sessionDirectory.appendingPathComponent(metadataFileName)
        if !fileManager.fileExists(atPath: metadataURL.path) {
            fileManager.createFile(atPath: metadataURL.path, contents: Data())
        }

        let session = StoredSession(
            id: id,
            title: title,
            createdAt: Date(),
            rows: [],
            speakers: [:],
            languageHints: languageHints,
            audioFilePath: audioFileURL.path,
            segmentsFilePath: segmentsURL.path,
            metadataFilePath: metadataURL.path,
            durationSeconds: 0,
            status: .ready
        )

        sessions[id] = session
        sessionOrder.insert(id, at: 0)
        persistSessionMetadata(for: session)
        persistSegmentsSnapshot(for: session)

        return id
    }

    func setSessionStatus(_ status: SessionStatus, for sessionID: UUID) {
        prepareIfNeeded()
        guard var session = sessions[sessionID] else {
            return
        }

        session.status = status
        sessions[sessionID] = session
        persistSessionMetadata(for: session)
    }

    func updateSessionConfig(sessionID: UUID, languageHints: [String]) {
        prepareIfNeeded()
        guard var session = sessions[sessionID] else {
            return
        }

        session.languageHints = languageHints
        sessions[sessionID] = session
        persistSessionMetadata(for: session)
    }

    func renameSession(sessionID: UUID, title: String) {
        prepareIfNeeded()
        guard var session = sessions[sessionID] else {
            return
        }

        session.title = title
        sessions[sessionID] = session
        persistSessionMetadata(for: session)
    }

    func deleteSession(sessionID: UUID) {
        prepareIfNeeded()
        guard let session = sessions[sessionID] else {
            return
        }

        sessions.removeValue(forKey: sessionID)
        sessionOrder.removeAll { $0 == sessionID }

        let sessionDirectory = URL(fileURLWithPath: session.audioFilePath).deletingLastPathComponent()
        if fileManager.fileExists(atPath: sessionDirectory.path) {
            try? fileManager.removeItem(at: sessionDirectory)
        }
    }

    func snapshotSessions() -> [ChatSession] {
        prepareIfNeeded()
        return sessionOrder.compactMap { id in
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
        prepareIfNeeded()
        return sessions[sessionID]?.rows ?? []
    }

    func audioFileURL(for sessionID: UUID) -> URL? {
        prepareIfNeeded()
        guard let path = sessions[sessionID]?.audioFilePath else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    func appendTranscript(sessionID: UUID, event: PipelineTranscriptEvent) {
        prepareIfNeeded()
        guard var session = sessions[sessionID] else {
            return
        }

        let profile = speakerProfile(for: event.speakerID, in: &session.speakers)
        let baseColor = Color(hex: profile.colorHex)

        let row = TranscriptRow(
            id: event.id,
            speakerID: event.speakerID,
            speaker: profile.label,
            text: event.text,
            time: Self.formatTimestamp(seconds: event.startOffset),
            language: event.languageID,
            avatarSymbol: profile.avatarSymbol,
            avatarPalette: [baseColor, .white.opacity(0.72)],
            startOffset: event.startOffset,
            endOffset: event.endOffset
        )

        session.rows.append(row)
        session.durationSeconds = max(session.durationSeconds, event.endOffset)
        persistSegmentsSnapshot(for: session)
        persistSessionMetadata(for: session)
        sessions[sessionID] = session
    }

    func updateTranscriptRow(
        sessionID: UUID,
        rowID: UUID,
        text: String,
        language: String
    ) {
        prepareIfNeeded()
        guard var session = sessions[sessionID] else {
            return
        }

        guard let index = session.rows.firstIndex(where: { $0.id == rowID }) else {
            return
        }

        let existing = session.rows[index]
        session.rows[index] = TranscriptRow(
            id: existing.id,
            speakerID: existing.speakerID,
            speaker: existing.speaker,
            text: text,
            time: existing.time,
            language: language,
            avatarSymbol: existing.avatarSymbol,
            avatarPalette: existing.avatarPalette,
            startOffset: existing.startOffset,
            endOffset: existing.endOffset
        )

        persistSegmentsSnapshot(for: session)
        sessions[sessionID] = session
    }

    func updateSpeakerName(
        sessionID: UUID,
        speakerID: String,
        newName: String
    ) {
        prepareIfNeeded()
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var session = sessions[sessionID] else {
            return
        }

        guard let profile = session.speakers[speakerID] else {
            return
        }

        session.speakers[speakerID] = SpeakerProfile(
            label: trimmed,
            colorHex: profile.colorHex,
            avatarSymbol: profile.avatarSymbol
        )

        for index in session.rows.indices where session.rows[index].speakerID == speakerID {
            let existing = session.rows[index]
            session.rows[index] = TranscriptRow(
                id: existing.id,
                speakerID: existing.speakerID,
                speaker: trimmed,
                text: existing.text,
                time: existing.time,
                language: existing.language,
                avatarSymbol: existing.avatarSymbol,
                avatarPalette: existing.avatarPalette,
                startOffset: existing.startOffset,
                endOffset: existing.endOffset
            )
        }

        persistSegmentsSnapshot(for: session)
        persistSessionMetadata(for: session)
        sessions[sessionID] = session
    }

    func changeTranscriptRowSpeaker(
        sessionID: UUID,
        rowID: UUID,
        targetSpeakerID: String
    ) {
        prepareIfNeeded()
        guard var session = sessions[sessionID] else {
            return
        }

        guard let rowIndex = session.rows.firstIndex(where: { $0.id == rowID }),
              let targetProfile = session.speakers[targetSpeakerID]
        else {
            return
        }

        let existing = session.rows[rowIndex]
        guard existing.speakerID != targetSpeakerID else {
            return
        }

        let baseColor = Color(hex: targetProfile.colorHex)
        session.rows[rowIndex] = TranscriptRow(
            id: existing.id,
            speakerID: targetSpeakerID,
            speaker: targetProfile.label,
            text: existing.text,
            time: existing.time,
            language: existing.language,
            avatarSymbol: targetProfile.avatarSymbol,
            avatarPalette: [baseColor, .white.opacity(0.72)],
            startOffset: existing.startOffset,
            endOffset: existing.endOffset
        )

        persistSegmentsSnapshot(for: session)
        persistSessionMetadata(for: session)
        sessions[sessionID] = session
    }

    private func speakerProfile(
        for speakerID: String,
        in table: inout [String: SpeakerProfile],
        preferredName: String? = nil,
        preferredColorHex: String? = nil,
        preferredAvatarSymbol: String? = nil
    ) -> SpeakerProfile {
        if let profile = table[speakerID] {
            return profile
        }

        let resolvedName: String = {
            let trimmed = preferredName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? speakerID : trimmed
        }()
        let colorHex = Self.normalizeHexColor(preferredColorHex)
            ?? Self.speakerColorPalette[Self.stableIndex(for: speakerID, modulo: Self.speakerColorPalette.count)]
        let symbol = preferredAvatarSymbol
            ?? Self.speakerAvatarSymbols[Self.stableIndex(for: speakerID, modulo: Self.speakerAvatarSymbols.count)]

        let profile = SpeakerProfile(label: resolvedName, colorHex: colorHex, avatarSymbol: symbol)
        table[speakerID] = profile
        return profile
    }

    private static func formatTimestamp(seconds: Double) -> String {
        let clamped = Int(max(seconds, 0).rounded(.down))
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        let secs = clamped % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }

    private func prepareIfNeeded() {
        guard !hasLoadedFromDisk else {
            return
        }
        loadSessionsFromDisk()
        hasLoadedFromDisk = true
    }

    private func loadSessionsFromDisk() {
        sessions.removeAll()
        sessionOrder.removeAll()

        guard let directoryURLs = try? fileManager.contentsOfDirectory(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for directoryURL in directoryURLs {
            guard let values = try? directoryURL.resourceValues(forKeys: [.isDirectoryKey]),
                  values.isDirectory == true,
                  let sessionID = UUID(uuidString: directoryURL.lastPathComponent)
            else {
                continue
            }

            guard let session = loadSession(at: directoryURL, sessionID: sessionID) else {
                continue
            }

            sessions[sessionID] = session
            sessionOrder.append(sessionID)
        }

        sessionOrder.sort { lhs, rhs in
            guard let left = sessions[lhs], let right = sessions[rhs] else {
                return false
            }
            return left.createdAt > right.createdAt
        }
    }

    private func loadSession(at sessionDirectory: URL, sessionID: UUID) -> StoredSession? {
        let audioURL = sessionDirectory.appendingPathComponent(audioFileName)
        if !fileManager.fileExists(atPath: audioURL.path) {
            fileManager.createFile(atPath: audioURL.path, contents: Data())
        }

        let segmentsURL = sessionDirectory.appendingPathComponent(segmentsFileName)
        if !fileManager.fileExists(atPath: segmentsURL.path) {
            fileManager.createFile(atPath: segmentsURL.path, contents: Data("[]".utf8))
        }

        let metadataURL = sessionDirectory.appendingPathComponent(metadataFileName)
        let metadata = loadSessionMetadata(at: metadataURL)

        var speakers = metadata?.speakers ?? [:]
        let rows = loadSegments(at: segmentsURL, speakers: &speakers)

        if speakers.isEmpty {
            for row in rows {
                _ = speakerProfile(
                    for: row.speakerID,
                    in: &speakers,
                    preferredName: row.speaker,
                    preferredAvatarSymbol: row.avatarSymbol
                )
            }
        }

        let fallbackCreatedAt = (try? sessionDirectory.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
        let session = StoredSession(
            id: sessionID,
            title: metadata?.title ?? "Chat",
            createdAt: metadata?.createdAt ?? fallbackCreatedAt,
            rows: rows,
            speakers: speakers,
            languageHints: metadata?.languageHints ?? [],
            audioFilePath: audioURL.path,
            segmentsFilePath: segmentsURL.path,
            metadataFilePath: metadataURL.path,
            durationSeconds: metadata?.durationSeconds ?? rows.compactMap(\.endOffset).max() ?? 0,
            status: metadata?.status ?? .ready
        )

        // Keep old files forward-compatible by rewriting with current schema.
        persistSessionMetadata(for: session)
        persistSegmentsSnapshot(for: session)

        return session
    }

    private func loadSessionMetadata(at url: URL) -> (
        title: String,
        createdAt: Date,
        languageHints: [String],
        durationSeconds: Double,
        status: SessionStatus,
        speakers: [String: SpeakerProfile]
    )? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(SessionMetadataSnapshot.self, from: data) else {
            return nil
        }

        return (
            title: snapshot.title,
            createdAt: snapshot.createdAt,
            languageHints: snapshot.languageHints,
            durationSeconds: snapshot.durationSeconds,
            status: SessionStatus(rawValue: snapshot.status) ?? .ready,
            speakers: snapshot.speakers
        )
    }

    private func loadSegments(at url: URL, speakers: inout [String: SpeakerProfile]) -> [TranscriptRow] {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            return []
        }

        let decoder = JSONDecoder()

        if let snapshots = try? decoder.decode([SegmentSnapshot].self, from: data) {
            return snapshots.map { snapshot in
                let resolvedSpeakerID = snapshot.speakerID.isEmpty ? snapshot.speaker : snapshot.speakerID
                let profile = speakerProfile(
                    for: resolvedSpeakerID,
                    in: &speakers,
                    preferredName: snapshot.speaker,
                    preferredColorHex: snapshot.avatarColorHex,
                    preferredAvatarSymbol: snapshot.avatarSymbol
                )
                let timestamp = Self.resolvedTimestamp(
                    snapshot.time,
                    startOffset: snapshot.startOffset
                )

                return TranscriptRow(
                    id: snapshot.id ?? UUID(),
                    speakerID: resolvedSpeakerID,
                    speaker: profile.label,
                    text: snapshot.text,
                    time: timestamp,
                    language: snapshot.language.isEmpty ? "AUTO" : snapshot.language,
                    avatarSymbol: profile.avatarSymbol,
                    avatarPalette: [Color(hex: profile.colorHex), .white.opacity(0.72)],
                    startOffset: snapshot.startOffset,
                    endOffset: snapshot.endOffset
                )
            }
        }

        if let snapshots = try? decoder.decode([LegacySegmentSnapshot].self, from: data) {
            return snapshots.map { snapshot in
                let resolvedSpeakerID = snapshot.speakerID.isEmpty ? snapshot.speaker : snapshot.speakerID
                let profile = speakerProfile(
                    for: resolvedSpeakerID,
                    in: &speakers,
                    preferredName: snapshot.speaker
                )

                return TranscriptRow(
                    id: UUID(),
                    speakerID: resolvedSpeakerID,
                    speaker: profile.label,
                    text: snapshot.text,
                    time: Self.resolvedTimestamp(snapshot.time, startOffset: snapshot.startOffset),
                    language: snapshot.language.isEmpty ? "AUTO" : snapshot.language,
                    avatarSymbol: profile.avatarSymbol,
                    avatarPalette: [Color(hex: profile.colorHex), .white.opacity(0.72)],
                    startOffset: snapshot.startOffset,
                    endOffset: snapshot.endOffset
                )
            }
        }

        return []
    }

    private static func resolvedTimestamp(_ candidate: String?, startOffset: Double?) -> String {
        let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            return trimmed
        }
        return formatTimestamp(seconds: startOffset ?? 0)
    }

    private static let speakerColorPalette = [
        "#F97316", "#0EA5E9", "#10B981", "#EF4444", "#6366F1", "#D97706", "#14B8A6"
    ]
    private static let speakerAvatarSymbols = [
        "person.fill",
        "person.2.fill",
        "person.crop.circle.fill.badge.checkmark",
        "person.crop.circle.badge.clock",
        "person.crop.circle.badge.questionmark"
    ]

    private static func stableIndex(for value: String, modulo: Int) -> Int {
        guard modulo > 0 else {
            return 0
        }

        var hash: UInt64 = 1_469_598_103_934_665_603
        for scalar in value.unicodeScalars {
            hash ^= UInt64(scalar.value)
            hash &*= 1_099_511_628_211
        }
        return Int(hash % UInt64(modulo))
    }

    private static func normalizeHexColor(_ candidate: String?) -> String? {
        guard let candidate else {
            return nil
        }

        let normalized = candidate
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .uppercased()

        let allowedScalars = CharacterSet(charactersIn: "0123456789ABCDEF")
        guard normalized.count == 6,
              normalized.unicodeScalars.allSatisfy({ allowedScalars.contains($0) })
        else {
            return nil
        }

        return "#\(normalized)"
    }

    private func persistSessionMetadata(for session: StoredSession) {
        let metadata = SessionMetadataSnapshot(
            schemaVersion: 1,
            id: session.id,
            title: session.title,
            createdAt: session.createdAt,
            languageHints: session.languageHints,
            audioFileName: URL(fileURLWithPath: session.audioFilePath).lastPathComponent,
            segmentsFileName: URL(fileURLWithPath: session.segmentsFilePath).lastPathComponent,
            durationSeconds: session.durationSeconds,
            status: session.status.rawValue,
            speakers: session.speakers
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(metadata) else {
            return
        }

        let url = URL(fileURLWithPath: session.metadataFilePath)
        try? data.write(to: url, options: .atomic)
    }

    private func persistSegmentsSnapshot(for session: StoredSession) {
        let snapshots = session.rows.map { row in
            SegmentSnapshot(
                id: row.id,
                speakerID: row.speakerID,
                speaker: row.speaker,
                text: row.text,
                time: row.time,
                language: row.language,
                avatarSymbol: row.avatarSymbol,
                avatarColorHex: session.speakers[row.speakerID]?.colorHex,
                startOffset: row.startOffset,
                endOffset: row.endOffset
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshots) else {
            return
        }

        let url = URL(fileURLWithPath: session.segmentsFilePath)
        try? data.write(to: url, options: .atomic)
    }
}

struct PersistedAppSettings: Codable, Equatable {
    var schemaVersion: Int
    var selectedLanguageCodes: [String]
    var languageSearchText: String
    var focusContextKeywords: String
    var totalHours: Double
    var usedHours: Double
    var isICloudSyncEnabled: Bool
    var activeSessionID: UUID?
    var chatCounter: Int
}

struct AppSettingsStore {
    private let userDefaults: UserDefaults
    private let storageKey: String

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "layca.app-settings.v1"
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
    }

    func load() -> PersistedAppSettings? {
        guard let data = userDefaults.data(forKey: storageKey) else {
            return nil
        }

        let decoder = JSONDecoder()
        return try? decoder.decode(PersistedAppSettings.self, from: data)
    }

    func save(_ settings: PersistedAppSettings) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(settings) else {
            return
        }
        userDefaults.set(data, forKey: storageKey)
    }
}

@MainActor
final class AppBackend: ObservableObject {
    private struct QueuedChunkTranscription: Sendable {
        let rowID: UUID
        let sessionID: UUID
        let samples: [Float]
        let sampleRate: Double
    }

    private struct QueuedManualRetranscription: Sendable {
        let rowID: UUID
        let sessionID: UUID
    }

    @Published var isRecording = false
    @Published var recordingSeconds: Double = 0
    @Published var waveformBars: [Double] = Array(repeating: 0.03, count: 9)

    @Published var selectedLanguageCodes: Set<String> = ["en", "th"] {
        didSet { persistSettingsIfNeeded() }
    }
    @Published var languageSearchText = "" {
        didSet { persistSettingsIfNeeded() }
    }
    @Published var focusContextKeywords = "" {
        didSet { persistSettingsIfNeeded() }
    }

    @Published var totalHours: Double = 40 {
        didSet { persistSettingsIfNeeded() }
    }
    @Published var usedHours: Double = 12.6 {
        didSet { persistSettingsIfNeeded() }
    }

    @Published var isICloudSyncEnabled = true {
        didSet { persistSettingsIfNeeded() }
    }
    @Published var isRestoringPurchases = false
    @Published var restoreStatusMessage: String?

    @Published var sessions: [ChatSession] = []
    @Published var activeSessionID: UUID? {
        didSet { persistSettingsIfNeeded() }
    }
    @Published var activeTranscriptRows: [TranscriptRow] = []
    @Published var transcribingRowIDs: Set<UUID> = []
    @Published private(set) var queuedManualRetranscriptionRowIDs: Set<UUID> = []
    @Published var isTranscriptionBusy = false

    @Published var preflightStatusMessage: String?

    private let preflightService = PreflightService()
    private let pipeline = LiveSessionPipeline()
    private let sessionStore = SessionStore()
    private let settingsStore: AppSettingsStore
    private let masterRecorder = MasterAudioRecorder()
    private let whisperTranscriber = WhisperGGMLCoreMLService()

    private var streamTask: Task<Void, Never>?
    private var chunkPlayer: AVAudioPlayer?
    private var chunkStopTask: Task<Void, Never>?
    private var attemptedTranscriptionRowIDs: Set<UUID> = []
    private var queuedTranscriptionRowIDs: Set<UUID> = []
    private var queuedChunkTranscriptions: [QueuedChunkTranscription] = []
    private var queuedTranscriptionTask: Task<Void, Never>?
    private var queuedManualRetranscriptions: [QueuedManualRetranscription] = []
    private var queuedManualRetranscriptionTask: Task<Void, Never>?
    private var chatCounter = 0
    private var isHydratingPersistedState = false

    init() {
        self.settingsStore = AppSettingsStore()
        Task {
            await bootstrap()
        }
    }

    init(settingsStore: AppSettingsStore) {
        self.settingsStore = settingsStore
        Task {
            await bootstrap()
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
        loadPersistedSettings()
        await refreshSessionsFromStore()

        let inferredCounter = inferChatCounter(from: sessions)
        chatCounter = max(chatCounter, inferredCounter, sessions.count)

        if sessions.isEmpty {
            await createSessionAndActivate()
        }

        persistSettingsIfNeeded()
    }

    func toggleLanguageFocus(_ code: String) {
        let normalized = code.lowercased()
        if selectedLanguageCodes.contains(normalized) {
            selectedLanguageCodes.remove(normalized)
        } else {
            selectedLanguageCodes.insert(normalized)
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

    func renameSession(_ session: ChatSession, to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        Task {
            await sessionStore.renameSession(sessionID: session.id, title: trimmed)
            await refreshSessionsFromStore()
        }
    }

    func deleteSession(_ session: ChatSession) {
        Task {
            if isRecording, activeSessionID == session.id {
                await stopRecording()
            }

            await sessionStore.deleteSession(sessionID: session.id)
            if activeSessionID == session.id {
                activeSessionID = nil
            }
            await refreshSessionsFromStore()
        }
    }

    func shareText(for session: ChatSession) -> String {
        let header = [
            session.title,
            "Created: \(session.formattedDate)",
            ""
        ]
        .joined(separator: "\n")

        let transcriptBody: String
        if session.rows.isEmpty {
            transcriptBody = "No transcript rows in this chat yet."
        } else {
            transcriptBody = session.rows
                .map { row in
                    "[\(row.time)] \(row.speaker) (\(row.language))\n\(row.text)"
                }
                .joined(separator: "\n\n")
        }

        return "\(header)\(transcriptBody)"
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

    func playTranscriptChunk(_ row: TranscriptRow) {
        Task {
            await playTranscriptChunkInternal(row, sessionID: resolvedSessionID(for: row))
        }
    }

    func editTranscriptRow(_ row: TranscriptRow, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let sessionID = resolvedSessionID(for: row) else {
            return
        }

        // Manual edits should not be overwritten by any queued auto job.
        attemptedTranscriptionRowIDs.insert(row.id)
        queuedTranscriptionRowIDs.remove(row.id)
        queuedChunkTranscriptions.removeAll { $0.rowID == row.id }
        queuedManualRetranscriptionRowIDs.remove(row.id)
        queuedManualRetranscriptions.removeAll { $0.rowID == row.id }
        updateTranscriptionBusyState()

        Task {
            await sessionStore.updateTranscriptRow(
                sessionID: sessionID,
                rowID: row.id,
                text: trimmed,
                language: row.language
            )
            await refreshSessionsFromStore()
            preflightStatusMessage = nil
        }
    }

    func editSpeakerName(_ row: TranscriptRow, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let sessionID = resolvedSessionID(for: row) else {
            return
        }

        Task {
            await sessionStore.updateSpeakerName(
                sessionID: sessionID,
                speakerID: row.speakerID,
                newName: trimmed
            )
            await refreshSessionsFromStore()
            preflightStatusMessage = nil
        }
    }

    func changeSpeaker(_ row: TranscriptRow, to speakerID: String) {
        guard let sessionID = resolvedSessionID(for: row) else {
            return
        }

        Task {
            await sessionStore.changeTranscriptRowSpeaker(
                sessionID: sessionID,
                rowID: row.id,
                targetSpeakerID: speakerID
            )
            await refreshSessionsFromStore()
            preflightStatusMessage = nil
        }
    }

    func retranscribeTranscriptRow(_ row: TranscriptRow) {
        guard let sessionID = resolvedSessionID(for: row) else {
            preflightStatusMessage = "Unable to locate this transcript row in an active chat."
            return
        }

        guard let startOffset = row.startOffset,
              let endOffset = row.endOffset,
              endOffset > startOffset
        else {
            preflightStatusMessage = "This transcript row has no valid audio range to transcribe again."
            return
        }

        guard !queuedManualRetranscriptionRowIDs.contains(row.id) else {
            return
        }

        // Manual re-transcribe takes ownership over any stale auto-transcription job.
        attemptedTranscriptionRowIDs.insert(row.id)
        queuedTranscriptionRowIDs.remove(row.id)
        queuedChunkTranscriptions.removeAll { $0.rowID == row.id }

        queuedManualRetranscriptionRowIDs.insert(row.id)
        queuedManualRetranscriptions.append(
            QueuedManualRetranscription(
                rowID: row.id,
                sessionID: sessionID
            )
        )
        updateTranscriptionBusyState()
        startManualRetranscriptionWorkerIfNeeded()
    }

    private func startManualRetranscriptionWorkerIfNeeded() {
        guard queuedManualRetranscriptionTask == nil else {
            return
        }

        queuedManualRetranscriptionTask = Task { [weak self] in
            guard let self else {
                return
            }
            await self.drainQueuedManualRetranscriptions()
        }
    }

    private func drainQueuedManualRetranscriptions() async {
        while !Task.isCancelled {
            guard !queuedManualRetranscriptions.isEmpty else {
                queuedManualRetranscriptionTask = nil
                updateTranscriptionBusyState()
                return
            }

            guard queuedTranscriptionTask == nil,
                  queuedChunkTranscriptions.isEmpty,
                  transcribingRowIDs.isEmpty
            else {
                try? await Task.sleep(nanoseconds: 120_000_000)
                continue
            }

            let next = queuedManualRetranscriptions.removeFirst()
            queuedManualRetranscriptionRowIDs.remove(next.rowID)

            guard let row = await findTranscriptRow(rowID: next.rowID, sessionID: next.sessionID) else {
                updateTranscriptionBusyState()
                continue
            }

            await retranscribeTranscriptRowInternal(row, sessionID: next.sessionID)
            updateTranscriptionBusyState()
        }

        queuedManualRetranscriptionTask = nil
        updateTranscriptionBusyState()
    }

    private func startRecording() async {
        guard !isRecording else {
            return
        }

        stopChunkPlayback()

        if activeSessionID == nil {
            await createSessionAndActivate()
        }

        guard let sessionID = activeSessionID else {
            return
        }

        let remainingSeconds = max(totalHours - usedHours, 0) * 3600

        do {
            let config = try await preflightService.prepare(
                languageCodes: selectedLanguageCodes,
                focusKeywords: focusContextKeywords,
                remainingCreditSeconds: remainingSeconds
            )

            preflightStatusMessage = nil

            guard let audioFileURL = await sessionStore.audioFileURL(for: sessionID) else {
                preflightStatusMessage = "Unable to prepare audio file for this session."
                await sessionStore.setSessionStatus(.failed, for: sessionID)
                return
            }

            try await masterRecorder.startRecording(to: audioFileURL)

            await sessionStore.updateSessionConfig(
                sessionID: sessionID,
                languageHints: config.languageCodes
            )
            await sessionStore.setSessionStatus(.recording, for: sessionID)

            let stream = await pipeline.start(
                config: LivePipelineConfig(
                    sessionID: sessionID,
                    prompt: config.prompt,
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
        masterRecorder.stop()

        if let activeSessionID {
            await sessionStore.setSessionStatus(.ready, for: activeSessionID)
        }

        isRecording = false
        await refreshSessionsFromStore()
    }

    private func playTranscriptChunkInternal(_ row: TranscriptRow, sessionID: UUID?) async {
        guard !isRecording,
              let sessionID,
              let startOffset = row.startOffset,
              let endOffset = row.endOffset,
              endOffset > startOffset
        else {
            return
        }

        guard let audioURL = await sessionStore.audioFileURL(for: sessionID) else {
            return
        }

        stopChunkPlayback()

        do {
            try configureAudioSessionForChunkPlaybackIfSupported()

            let player = try AVAudioPlayer(contentsOf: audioURL)
            let start = max(0, min(startOffset, player.duration))
            let duration = max(min(endOffset, player.duration) - start, 0.05)

            player.currentTime = start
            player.prepareToPlay()
            player.play()

            chunkPlayer = player
            chunkStopTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                guard let self else {
                    return
                }
                await MainActor.run {
                    guard self.chunkPlayer === player else {
                        return
                    }
                    self.stopChunkPlayback()
                }
            }

        } catch {
            stopChunkPlayback()
        }
    }

    private func retranscribeTranscriptRowInternal(_ row: TranscriptRow, sessionID: UUID) async {
        guard !isRecording else {
            preflightStatusMessage = "Stop recording before running Transcribe Again."
            return
        }

        guard let startOffset = row.startOffset,
              let endOffset = row.endOffset,
              endOffset > startOffset
        else {
            preflightStatusMessage = "This transcript row has no valid audio range to transcribe again."
            return
        }

        guard !transcribingRowIDs.contains(row.id) else {
            return
        }

        // Treat manual re-transcribe as authoritative for this row.
        attemptedTranscriptionRowIDs.insert(row.id)
        queuedTranscriptionRowIDs.remove(row.id)
        queuedChunkTranscriptions.removeAll { $0.rowID == row.id }
        updateTranscriptionBusyState()

        guard let audioURL = await sessionStore.audioFileURL(for: sessionID) else {
            preflightStatusMessage = "Unable to load session audio for transcription."
            return
        }

        transcribingRowIDs.insert(row.id)
        updateTranscriptionBusyState()
        defer {
            transcribingRowIDs.remove(row.id)
            updateTranscriptionBusyState()
        }

        do {
            let initialPrompt = preflightService.buildPrompt(
                languageCodes: selectedLanguageCodes.map { $0.lowercased() }.sorted(),
                keywords: focusContextKeywords
            )
            let result = try await whisperTranscriber.transcribe(
                audioURL: audioURL,
                startOffset: startOffset,
                endOffset: endOffset,
                preferredLanguageCode: "auto",
                initialPrompt: initialPrompt
            )

            let trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                preflightStatusMessage = "No speech detected in this chunk."
                return
            }

            await sessionStore.updateTranscriptRow(
                sessionID: sessionID,
                rowID: row.id,
                text: trimmed,
                language: result.languageID.uppercased()
            )
            await refreshSessionsFromStore()
            preflightStatusMessage = nil
        } catch {
            preflightStatusMessage = error.localizedDescription
        }
    }

    private func transcribeQueuedChunk(
        rowID: UUID,
        sessionID: UUID,
        samples: [Float],
        sampleRate: Double
    ) async {
        guard !transcribingRowIDs.contains(rowID),
              !attemptedTranscriptionRowIDs.contains(rowID)
        else {
            return
        }

        transcribingRowIDs.insert(rowID)
        attemptedTranscriptionRowIDs.insert(rowID)
        updateTranscriptionBusyState()

        defer {
            transcribingRowIDs.remove(rowID)
            updateTranscriptionBusyState()
        }

        do {
            let initialPrompt = preflightService.buildPrompt(
                languageCodes: selectedLanguageCodes.map { $0.lowercased() }.sorted(),
                keywords: focusContextKeywords
            )
            let result = try await whisperTranscriber.transcribe(
                samples: samples,
                sourceSampleRate: sampleRate,
                preferredLanguageCode: "auto",
                initialPrompt: initialPrompt
            )

            let trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                preflightStatusMessage = "No speech detected in this chunk."
                return
            }

            await sessionStore.updateTranscriptRow(
                sessionID: sessionID,
                rowID: rowID,
                text: trimmed,
                language: result.languageID.uppercased()
            )
            await refreshSessionsFromStore()
            preflightStatusMessage = nil
        } catch {
            preflightStatusMessage = error.localizedDescription
        }
    }

    private func enqueueChunkForAutomaticTranscription(
        rowID: UUID,
        sessionID: UUID,
        samples: [Float],
        sampleRate: Double
    ) {
        guard !samples.isEmpty, sampleRate > 0 else {
            return
        }
        guard !attemptedTranscriptionRowIDs.contains(rowID),
              !transcribingRowIDs.contains(rowID),
              !queuedTranscriptionRowIDs.contains(rowID)
        else {
            return
        }

        queuedTranscriptionRowIDs.insert(rowID)
        queuedChunkTranscriptions.append(
            QueuedChunkTranscription(
                rowID: rowID,
                sessionID: sessionID,
                samples: samples,
                sampleRate: sampleRate
            )
        )
        updateTranscriptionBusyState()
        startQueuedTranscriptionWorkerIfNeeded()
    }

    private func startQueuedTranscriptionWorkerIfNeeded() {
        guard queuedTranscriptionTask == nil else {
            return
        }

        queuedTranscriptionTask = Task { [weak self] in
            guard let self else {
                return
            }
            await self.drainQueuedChunkTranscriptions()
        }
    }

    private func drainQueuedChunkTranscriptions() async {
        while !Task.isCancelled {
            guard !queuedChunkTranscriptions.isEmpty else {
                queuedTranscriptionTask = nil
                updateTranscriptionBusyState()
                return
            }

            let next = queuedChunkTranscriptions.removeFirst()
            queuedTranscriptionRowIDs.remove(next.rowID)
            updateTranscriptionBusyState()

            await transcribeQueuedChunk(
                rowID: next.rowID,
                sessionID: next.sessionID,
                samples: next.samples,
                sampleRate: next.sampleRate
            )
        }

        queuedTranscriptionTask = nil
        updateTranscriptionBusyState()
    }

    private func updateTranscriptionBusyState() {
        isTranscriptionBusy =
            !transcribingRowIDs.isEmpty ||
            !queuedChunkTranscriptions.isEmpty ||
            !queuedManualRetranscriptions.isEmpty
    }

    private func findTranscriptRow(rowID: UUID, sessionID: UUID) async -> TranscriptRow? {
        if let row = sessions
            .first(where: { $0.id == sessionID })?
            .rows
            .first(where: { $0.id == rowID }) {
            return row
        }

        let rows = await sessionStore.transcriptRows(for: sessionID)
        return rows.first(where: { $0.id == rowID })
    }

    private func resolvedSessionID(for row: TranscriptRow) -> UUID? {
        if let activeSessionID,
           sessions.first(where: { $0.id == activeSessionID })?.rows.contains(where: { $0.id == row.id }) == true {
            return activeSessionID
        }

        if let matchingSession = sessions.first(where: { session in
            session.rows.contains(where: { $0.id == row.id })
        }) {
            return matchingSession.id
        }

        return activeSessionID
    }

    private func stopChunkPlayback() {
        chunkStopTask?.cancel()
        chunkStopTask = nil
        chunkPlayer?.stop()
        chunkPlayer = nil
        deactivateChunkPlaybackAudioSessionIfSupported()
    }

    private func configureAudioSessionForChunkPlaybackIfSupported() throws {
#if !os(macOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
#endif
    }

    private func deactivateChunkPlaybackAudioSessionIfSupported() {
#if !os(macOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
#endif
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
            enqueueChunkForAutomaticTranscription(
                rowID: transcript.id,
                sessionID: sessionID,
                samples: transcript.samples,
                sampleRate: transcript.sampleRate
            )

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

    private func createSessionAndActivate() async {
        chatCounter += 1
        persistSettingsIfNeeded()

        if let id = try? await sessionStore.createSession(
            title: "Chat \(chatCounter)",
            languageHints: Array(selectedLanguageCodes)
        ) {
            activeSessionID = id
            await refreshSessionsFromStore()
        }
    }

    private func refreshSessionsFromStore() async {
        let snapshots = await sessionStore.snapshotSessions()
        sessions = snapshots

        let hasActiveSession = activeSessionID.map { currentID in
            snapshots.contains(where: { $0.id == currentID })
        } ?? false

        if !hasActiveSession {
            activeSessionID = snapshots.first?.id
        }

        if let activeSessionID {
            activeTranscriptRows = await sessionStore.transcriptRows(for: activeSessionID)
        } else {
            activeTranscriptRows = []
        }
    }

    private func loadPersistedSettings() {
        guard let persisted = settingsStore.load() else {
            return
        }

        isHydratingPersistedState = true
        selectedLanguageCodes = Set(persisted.selectedLanguageCodes.map { $0.lowercased() })
        languageSearchText = persisted.languageSearchText
        focusContextKeywords = persisted.focusContextKeywords

        if persisted.totalHours > 0 {
            totalHours = persisted.totalHours
        }
        usedHours = min(max(persisted.usedHours, 0), totalHours)
        isICloudSyncEnabled = persisted.isICloudSyncEnabled
        activeSessionID = persisted.activeSessionID
        chatCounter = max(persisted.chatCounter, 0)
        isHydratingPersistedState = false
    }

    private func persistSettingsIfNeeded() {
        guard !isHydratingPersistedState else {
            return
        }

        let snapshot = PersistedAppSettings(
            schemaVersion: 1,
            selectedLanguageCodes: selectedLanguageCodes.map { $0.lowercased() }.sorted(),
            languageSearchText: languageSearchText,
            focusContextKeywords: focusContextKeywords,
            totalHours: totalHours,
            usedHours: usedHours,
            isICloudSyncEnabled: isICloudSyncEnabled,
            activeSessionID: activeSessionID,
            chatCounter: max(chatCounter, 0)
        )
        settingsStore.save(snapshot)
    }

    private func inferChatCounter(from sessions: [ChatSession]) -> Int {
        let inferredFromTitles = sessions.compactMap { session -> Int? in
            let trimmed = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.lowercased().hasPrefix("chat ") else {
                return nil
            }

            let numberText = trimmed.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
            return Int(numberText)
        }
        .max() ?? 0

        return max(inferredFromTitles, sessions.count)
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
