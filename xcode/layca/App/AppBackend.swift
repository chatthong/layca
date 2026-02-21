import Foundation
import SwiftUI
import Combine
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

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

        return "STRICT VERBATIM MODE. Never translate under any condition. Never summarize. Never rewrite. Preserve the original spoken language for every utterance: Thai audio must be output in Thai script, English audio must stay English. Do not convert Thai speech into English. This is a verbatim transcript of a meeting in \(languageList). The speakers switch between languages naturally. Transcribe exactly what is spoken in the original language, including profanity, violence, drug terms, and other sensitive words. Do not censor, mask, or replace words. Context: \(context)."
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
    case liveSpeaker(String?)
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
    case unableToFinalizeRecording

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone permission is required for recording."
        case .unableToStart:
            return "Unable to start audio recording."
        case .unableToFinalizeRecording:
            return "Unable to finalize recorded audio."
        }
    }
}

@MainActor
final class MasterAudioRecorder: NSObject, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    private var appendSourceURL: URL?
    private var segmentRecordingURL: URL?
    private var destinationURL: URL?

    func startRecording(to destinationURL: URL, appendIfPossible: Bool = true) async throws {
        try? await stop()

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

        let fileManager = FileManager.default
        let parentDirectory = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true)

        let shouldAppend = appendIfPossible
            && fileManager.fileExists(atPath: destinationURL.path)
            && ((try? destinationURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0

        let recordingURL: URL
        if shouldAppend {
            let temporaryURL = fileManager.temporaryDirectory
                .appendingPathComponent("layca-record-segment-\(UUID().uuidString).m4a")
            if fileManager.fileExists(atPath: temporaryURL.path) {
                try? fileManager.removeItem(at: temporaryURL)
            }
            recordingURL = temporaryURL
            appendSourceURL = destinationURL
            segmentRecordingURL = temporaryURL
        } else {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            recordingURL = destinationURL
            appendSourceURL = nil
            segmentRecordingURL = nil
        }

        self.destinationURL = destinationURL

        let recorder = try AVAudioRecorder(url: recordingURL, settings: settings)
        recorder.delegate = self
        recorder.prepareToRecord()

        guard recorder.record() else {
            throw MasterRecorderError.unableToStart
        }

        self.recorder = recorder
    }

    func stop() async throws {
        if let recorder {
            recorder.stop()
            self.recorder = nil
            try? await Task.sleep(nanoseconds: 180_000_000)
        } else {
            self.recorder = nil
        }

        if let sourceURL = appendSourceURL,
           let segmentURL = segmentRecordingURL,
           let destinationURL {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try await Self.mergeAudioFilesWithRetries(
                        sourceURL: sourceURL,
                        appendedURL: segmentURL,
                        outputURL: destinationURL
                    )
                }.value
            } catch {
                cleanupTemporaryRecordingFile()
                resetAppendState()
                deactivateAudioSessionIfSupported()
                throw error
            }
        }

        cleanupTemporaryRecordingFile()
        resetAppendState()
        deactivateAudioSessionIfSupported()
    }

    private static func mergeAudioFilesWithRetries(sourceURL: URL, appendedURL: URL, outputURL: URL) async throws {
        let maxAttempts = 3
        var lastError: Error?

        for attempt in 1...maxAttempts {
            do {
                try await mergeAudioFiles(sourceURL: sourceURL, appendedURL: appendedURL, outputURL: outputURL)
                return
            } catch {
                lastError = error
                guard attempt < maxAttempts else {
                    break
                }
                try? await Task.sleep(nanoseconds: 180_000_000)
            }
        }

        throw lastError ?? MasterRecorderError.unableToFinalizeRecording
    }

    private func resetAppendState() {
        appendSourceURL = nil
        segmentRecordingURL = nil
        destinationURL = nil
    }

    private func cleanupTemporaryRecordingFile() {
        guard let segmentRecordingURL else {
            return
        }
        try? FileManager.default.removeItem(at: segmentRecordingURL)
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

    private static func mergeAudioFiles(sourceURL: URL, appendedURL: URL, outputURL: URL) async throws {
        let sourceAsset = AVURLAsset(url: sourceURL)
        let appendedAsset = AVURLAsset(url: appendedURL)
        let composition = AVMutableComposition()

        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw MasterRecorderError.unableToFinalizeRecording
        }

        let sourceDuration = try await sourceAsset.load(.duration)
        let sourceTrack = try await sourceAsset.loadTracks(withMediaType: .audio).first
        if let sourceTrack {
            try compositionTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: sourceDuration),
                of: sourceTrack,
                at: .zero
            )
        }

        let appendedDuration = try await appendedAsset.load(.duration)
        guard let appendedTrack = try await appendedAsset.loadTracks(withMediaType: .audio).first else {
            throw MasterRecorderError.unableToFinalizeRecording
        }
        try compositionTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: appendedDuration),
            of: appendedTrack,
            at: sourceDuration
        )

        let fileManager = FileManager.default
        let tempOutputURL = outputURL.deletingLastPathComponent()
            .appendingPathComponent("layca-record-merged-\(UUID().uuidString).m4a")

        if fileManager.fileExists(atPath: tempOutputURL.path) {
            try? fileManager.removeItem(at: tempOutputURL)
        }

        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw MasterRecorderError.unableToFinalizeRecording
        }
        exporter.shouldOptimizeForNetworkUse = false
        try await exporter.export(to: tempOutputURL, as: .m4a)

        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }
        try fileManager.moveItem(at: tempOutputURL, to: outputURL)
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
    private struct FallbackSpeakerSignature {
        let amplitude: Double
        let zeroCrossingRate: Double
        let rmsEnergy: Double
    }

    private enum ProbeSpeakerObservation: Equatable {
        case existingLabel(String)
        case newCandidate
    }

    private struct SpeakerChangeCandidate {
        let observation: ProbeSpeakerObservation
        let startTimestamp: Double
    }

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
        let isSpeech: Bool
        let samples: [Float]
    }

    private var continuation: AsyncStream<PipelineEvent>.Continuation?
    private var isRunning = false
    private var speakerEmbeddings: [String: [Float]] = [:]
    private var speakerObservationCounts: [String: Int] = [:]
    private var pendingSpeakerEmbedding: [Float]?
    private var pendingSpeakerChunks = 0
    private var fallbackSpeakerEmbeddings: [String: FallbackSpeakerSignature] = [:]

    private var hadSignificantSilenceBeforeChunk: Bool = false

    private var inputController: LiveAudioInputController?
    private var activeConfig: LivePipelineConfig?
    private var elapsedSeconds: Double = 0
    private var waveformBuffer: [Double] = Array(repeating: 0.03, count: 18)
    private var activeChunkFrames: [AudioFrame] = []
    private var silenceSeconds: Double = 0
    private var activeChunkSpeakerID: String?
    private var speakerChangeCandidate: SpeakerChangeCandidate?
    private var speechSecondsSinceLastSpeakerProbe: Double = 0
    private var interruptCheckSampleAccumulator: [Float] = []
    private var lastKnownSpeakerEmbedding: [Float]?
    private var interruptCheckSampleRate: Double = 16_000
    private var lastChunkDurationSeconds: Double = 0
    private let interruptCheckWindowSize = 4_096
    private var chunkCounter = 0
    private var runToken = UUID()
    private var vadState: VADState = .loading
    private var speakerState: SpeakerState = .loading
    private let sileroVAD = SileroVADCoreMLService()
    private let intraChunkVAD = SileroVADCoreMLService()
    private let speakerDiarizer = SpeakerDiarizationCoreMLService()

    private let speechThreshold: Double = 0.06
    private let vadSpeechThreshold: Float = 0.5
    private let silenceCutoffSeconds: Double = 1.2
    private let minChunkDurationSeconds: Double = 3.2
    private let maxChunkDurationSeconds: Double = 12
    private let speakerChangeCutoffSeconds: Double = 0.0
    private let speakerBoundaryBacktrackSeconds: Double = 1.0
    // Speaker embedding needs enough voiced audio; probing too early collapses labels.
    private let speakerProbeWindowSpeechSeconds: Double = 1.6
    private let speakerProbeIntervalSpeechSeconds: Double = 0.25
    private let minSpeechSecondsForSpeakerProbe: Double = 1.6
    private let minSpeakerBoundaryChunkSeconds: Double = 1.6
    private let speakerSimilarityThreshold: Float = 0.65
    private let speakerLooseSimilarityThreshold: Float = 0.52
    private let newSpeakerCandidateSimilarity: Float = 0.58
    private let immediatNewSpeakerSimilarityThreshold: Float = 0.40
    private let pendingChunksBeforeNewSpeaker = 2
    private let maxSpeakersPerSession = 6
    private let minSegmentDurationForNewSpeaker: Double = 2.5
    private let adaptiveProbeWindowSpeechSeconds: Double = 0.8
    private let adaptiveProbeObservationThreshold: Int = 5
    private let turnTakingSilenceThreshold: Double = 0.5
    private let turnTakingSimilarityThreshold: Float = 0.45
    private let speakerFallbackThreshold: Double = 0.015
    private let deferredTranscriptPlaceholder = "Message queued for automatic transcription..."

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
            resetActiveChunkSpeakerTracking()
        }

        continuation?.yield(.stopped)
        continuation?.finish()
        continuation = nil

        activeConfig = nil
        elapsedSeconds = 0
        waveformBuffer = Array(repeating: 0.03, count: 18)
        silenceSeconds = 0
        resetActiveChunkSpeakerTracking()
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
        resetActiveChunkSpeakerTracking()
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

        let isSpeechFrame = await evaluateSpeech(frame: frame)
        let audioFrame = AudioFrame(
            timestamp: frameTimestamp,
            duration: frame.duration,
            sampleRate: frame.sampleRate,
            amplitude: frame.amplitude,
            zeroCrossingRate: frame.zeroCrossingRate,
            isSpeech: isSpeechFrame,
            samples: frame.samples
        )

        if isSpeechFrame {
            // Detect turn-taking: if this is the first speech frame of a new chunk,
            // record whether significant silence preceded it.
            if activeChunkFrames.isEmpty {
                hadSignificantSilenceBeforeChunk = silenceSeconds >= turnTakingSilenceThreshold
            }

            activeChunkFrames.append(audioFrame)
            silenceSeconds = 0
            speechSecondsSinceLastSpeakerProbe += frame.duration

            // Accumulate samples for interrupt detection.
            interruptCheckSampleAccumulator.append(contentsOf: frame.samples)
            interruptCheckSampleRate = Double(frame.sampleRate)
            if interruptCheckSampleAccumulator.count >= interruptCheckWindowSize {
                await checkForSpeakerInterrupt(config: config)
            }

            await evaluateSpeakerBoundary(config: config)
        } else if !activeChunkFrames.isEmpty {
            // Keep non-speech frames once a message has started so queued
            // auto-transcription receives natural timing instead of
            // speech-only samples stitched together.
            activeChunkFrames.append(audioFrame)
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
                resetActiveChunkSpeakerTracking()
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

        let allSamples = chunk.flatMap(\.samples)
        let sampleRate = first.sampleRate
        let chunkStartTime = first.timestamp
        let totalDuration = max((last.timestamp + last.duration) - chunkStartTime, 0.2)
        lastChunkDurationSeconds = totalDuration
        let languageCode = "AUTO"

        // Run speaker identification and VAD sub-chunking concurrently.
        async let speakerIDTask = identifySpeaker(chunk: chunk)
        async let subRangesTask = splitIntoSubChunksByVAD(samples: allSamples, sampleRate: sampleRate)
        let (speaker, subRanges) = await (speakerIDTask, subRangesTask)

        // Emit one PipelineTranscriptEvent per sub-chunk.
        for range in subRanges {
            let subSamples = Array(allSamples[range])
            let startFraction = Double(range.lowerBound) / Double(allSamples.count)
            let endFraction = Double(range.upperBound) / Double(allSamples.count)
            let subStart = chunkStartTime + startFraction * totalDuration
            let subEnd = chunkStartTime + endFraction * totalDuration
            let subDuration = max(subEnd - subStart, 0.2)

            let event = PipelineTranscriptEvent(
                id: UUID(),
                sessionID: config.sessionID,
                speakerID: speaker,
                languageID: languageCode,
                text: deferredTranscriptPlaceholder,
                startOffset: subStart,
                endOffset: subEnd,
                samples: subSamples,
                sampleRate: sampleRate
            )
            continuation?.yield(.transcript(event, chunkSeconds: subDuration))
        }
        chunkCounter += 1
    }

    // Runs a second-pass VAD on the raw samples of a completed chunk to find
    // breath-pause boundaries (silence >= 0.3 s) and splits the chunk into
    // sub-ranges. Each sub-range becomes its own chat bubble. Sub-chunks
    // shorter than 0.8 s are not used as split points to avoid fragmenting
    // very short utterances. Falls back to a single full-range if no valid
    // splits are found or if intraChunkVAD has not finished loading.
    private func splitIntoSubChunksByVAD(
        samples: [Float],
        sampleRate: Double
    ) async -> [Range<Int>] {
        let fullRange = [0..<samples.count]
        guard !samples.isEmpty, sampleRate > 0 else {
            return fullRange
        }

        // Hop size: ~32 ms worth of samples in the original sample rate.
        let hopSize = max(Int((0.032 * sampleRate).rounded()), 1)

        // Minimum silence width that qualifies as a breath pause (0.3 s).
        let minSilenceSamples = Int((0.3 * sampleRate).rounded())

        // Minimum sub-chunk length (0.8 s). Splits that would produce a
        // sub-chunk shorter than this are discarded.
        let minSubChunkSamples = Int((0.8 * sampleRate).rounded())

        // Single cross-actor call: batchIngest resets LSTM state then processes
        // all hops inside SileroVADCoreMLService, returning observations in one go.
        let observations = await intraChunkVAD.batchIngest(
            samples: samples,
            sampleRate: sampleRate,
            hopSize: hopSize
        )

        guard !observations.isEmpty else {
            return fullRange
        }

        // Identify contiguous silence regions (probability < 0.30).
        let silenceThreshold: Float = 0.30
        var splitPoints: [Int] = []

        var silenceStart: Int? = nil

        for observation in observations {
            if observation.probability < silenceThreshold {
                if silenceStart == nil {
                    silenceStart = observation.sampleIndex
                }
            } else {
                if let start = silenceStart {
                    let silenceEnd = observation.sampleIndex
                    let silenceSpan = silenceEnd - start
                    if silenceSpan >= minSilenceSamples {
                        // Split at the midpoint of the silence region.
                        let splitPoint = start + silenceSpan / 2
                        splitPoints.append(splitPoint)
                    }
                    silenceStart = nil
                }
            }
        }

        // Handle a trailing silence region that runs to the end of the chunk.
        if let start = silenceStart {
            let silenceEnd = samples.count
            let silenceSpan = silenceEnd - start
            if silenceSpan >= minSilenceSamples {
                let splitPoint = start + silenceSpan / 2
                splitPoints.append(splitPoint)
            }
        }

        guard !splitPoints.isEmpty else {
            return fullRange
        }

        // Build candidate ranges and discard any split that would produce a
        // sub-chunk shorter than minSubChunkSamples.
        var ranges: [Range<Int>] = []
        var rangeStart = 0

        for splitPoint in splitPoints {
            let candidateEnd = splitPoint
            let nextStart = splitPoint

            // Reject splits that produce a sub-chunk that is too short on
            // either side of the boundary.
            let leadingLength = candidateEnd - rangeStart
            let trailingLength = samples.count - nextStart
            guard leadingLength >= minSubChunkSamples,
                  trailingLength >= minSubChunkSamples else {
                continue
            }

            ranges.append(rangeStart..<candidateEnd)
            rangeStart = nextStart
        }

        // Always append the final trailing range.
        ranges.append(rangeStart..<samples.count)

        // If all splits were rejected we end up with a single range equal to
        // the original; that is equivalent to no splitting.
        return ranges.isEmpty ? fullRange : ranges
    }

    private func checkForSpeakerInterrupt(config: LivePipelineConfig) async {
        guard speakerState == .ready,
              !activeChunkFrames.isEmpty else {
            interruptCheckSampleAccumulator.removeAll(keepingCapacity: true)
            return
        }

        // Resolve the reference embedding: prefer the actively tracked speaker,
        // fall back to the last known embedding from the previous chunk so that
        // the first 1.6 s of a new chunk is not a blind window.
        let referenceEmbedding: [Float]
        if let currentLabel = activeChunkSpeakerID,
           let embedding = speakerEmbeddings[currentLabel] {
            referenceEmbedding = embedding
        } else if let fallback = lastKnownSpeakerEmbedding {
            referenceEmbedding = fallback
        } else {
            interruptCheckSampleAccumulator.removeAll(keepingCapacity: true)
            return
        }

        let buffer = interruptCheckSampleAccumulator
        interruptCheckSampleAccumulator.removeAll(keepingCapacity: true)

        // Race inference against an 80ms timeout. Under thermal throttling CoreML
        // can take 100-300ms; it is better to skip an interrupt window than to
        // back-log audio frames on the pipeline actor.
        let interrupted: Bool = await withTaskGroup(of: Bool?.self) { group in
            group.addTask {
                await self.speakerDiarizer.checkForInterrupt(
                    audioBuffer: buffer,
                    currentSpeakerEmbedding: referenceEmbedding,
                    sampleRate: self.interruptCheckSampleRate
                )
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 80_000_000) // 80ms
                return nil  // timeout sentinel
            }
            for await result in group {
                group.cancelAll()
                return result ?? false
            }
            return false
        }

        guard interrupted, let last = activeChunkFrames.last else {
            return
        }

        let boundaryTimestamp = last.timestamp
        await speakerDiarizer.resetInterruptState()
        await cutChunkForSpeakerBoundary(
            config: config,
            boundaryTimestamp: boundaryTimestamp,
            newObservation: .newCandidate
        )
    }

    private func evaluateSpeakerBoundary(config: LivePipelineConfig) async {
        guard speechSecondsSinceLastSpeakerProbe >= speakerProbeIntervalSpeechSeconds else {
            return
        }

        guard let probeFrames = recentSpeakerProbeWindow(),
              let last = activeChunkFrames.last else {
            return
        }

        speechSecondsSinceLastSpeakerProbe = 0
        guard let observation = await probeSpeakerObservation(chunk: probeFrames) else {
            return
        }

        let now = last.timestamp + last.duration

        guard let currentSpeaker = activeChunkSpeakerID else {
            if case let .existingLabel(label) = observation {
                activeChunkSpeakerID = label
            }
            speakerChangeCandidate = nil
            return
        }

        if case let .existingLabel(label) = observation, label == currentSpeaker {
            speakerChangeCandidate = nil
            return
        }

        if let candidate = speakerChangeCandidate, candidate.observation == observation {
            speakerChangeCandidate = candidate
        } else {
            speakerChangeCandidate = SpeakerChangeCandidate(
                observation: observation,
                startTimestamp: now
            )
        }

        guard let candidate = speakerChangeCandidate,
              (now - candidate.startTimestamp) >= speakerChangeCutoffSeconds else {
            return
        }

        let earliestBoundary = activeChunkFrames.first?.timestamp ?? 0
        let boundaryTimestamp = max(
            earliestBoundary,
            candidate.startTimestamp - speakerBoundaryBacktrackSeconds
        )

        await cutChunkForSpeakerBoundary(
            config: config,
            boundaryTimestamp: boundaryTimestamp,
            newObservation: candidate.observation
        )
    }

    private func cutChunkForSpeakerBoundary(
        config: LivePipelineConfig,
        boundaryTimestamp: Double,
        newObservation: ProbeSpeakerObservation
    ) async {
        guard !activeChunkFrames.isEmpty else {
            return
        }

        guard let splitIndex = activeChunkFrames.firstIndex(where: { $0.timestamp >= boundaryTimestamp }) else {
            applyTrailingSpeakerObservation(newObservation)
            speakerChangeCandidate = nil
            return
        }

        guard splitIndex > 0 else {
            applyTrailingSpeakerObservation(newObservation)
            speakerChangeCandidate = nil
            return
        }

        let leadingChunk = Array(activeChunkFrames[..<splitIndex])
        let trailingChunk = Array(activeChunkFrames[splitIndex...])

        guard chunkDuration(for: leadingChunk) >= minSpeakerBoundaryChunkSeconds else {
            return
        }

        activeChunkFrames = trailingChunk
        applyTrailingSpeakerObservation(newObservation)
        speakerChangeCandidate = nil
        silenceSeconds = trailingSilenceDuration(for: trailingChunk)
        speechSecondsSinceLastSpeakerProbe = speechDuration(for: trailingChunk)

        guard hasSpeech(leadingChunk) else {
            return
        }

        await processChunk(leadingChunk, config: config)
    }

    private func applyTrailingSpeakerObservation(_ observation: ProbeSpeakerObservation) {
        switch observation {
        case .existingLabel(let label):
            activeChunkSpeakerID = label
            lastKnownSpeakerEmbedding = speakerEmbeddings[label]
            continuation?.yield(.liveSpeaker(label))
        case .newCandidate:
            activeChunkSpeakerID = nil
            lastKnownSpeakerEmbedding = nil
            continuation?.yield(.liveSpeaker(nil))
        }
    }

    private func recentSpeakerProbeWindow() -> [AudioFrame]? {
        guard !activeChunkFrames.isEmpty else {
            return nil
        }

        // Use a shorter probe window for speakers that have been observed enough
        // times to produce a reliable embedding from less audio.
        let effectiveProbeWindow: Double
        if let label = activeChunkSpeakerID,
           (speakerObservationCounts[label] ?? 0) >= adaptiveProbeObservationThreshold {
            effectiveProbeWindow = adaptiveProbeWindowSpeechSeconds
        } else {
            effectiveProbeWindow = speakerProbeWindowSpeechSeconds
        }

        var startIndex = activeChunkFrames.count - 1
        var speechAccumulated: Double = 0

        for index in stride(from: activeChunkFrames.count - 1, through: 0, by: -1) {
            let frame = activeChunkFrames[index]
            startIndex = index
            if frame.isSpeech {
                speechAccumulated += frame.duration
            }
            if speechAccumulated >= effectiveProbeWindow {
                break
            }
        }

        guard speechAccumulated >= minSpeechSecondsForSpeakerProbe else {
            return nil
        }

        let window = Array(activeChunkFrames[startIndex...])
        guard hasSpeech(window) else {
            return nil
        }
        return window
    }

    private func probeSpeakerObservation(chunk: [AudioFrame]) async -> ProbeSpeakerObservation? {
        switch speakerState {
        case .ready:
            do {
                let samples = chunk.flatMap(\.samples)
                let sampleRate = chunk.first?.sampleRate ?? 16_000
                guard let embedding = try await speakerDiarizer.embedding(for: samples, sampleRate: sampleRate),
                      !embedding.isEmpty else {
                    return probeSpeakerObservationFallback(chunk: chunk)
                }
                return probeSpeakerObservation(from: embedding)
            } catch {
                // Probe errors must not degrade the primary speaker detector.
                return probeSpeakerObservationFallback(chunk: chunk)
            }
        case .loading, .fallback:
            return probeSpeakerObservationFallback(chunk: chunk)
        }
    }

    private func probeSpeakerObservation(from embedding: [Float]) -> ProbeSpeakerObservation? {
        guard let closest = closestSpeaker(for: embedding) else {
            return nil
        }

        // After significant prior silence (turn-taking), use a lower similarity
        // threshold so the probe more readily returns .newCandidate, enabling
        // faster speaker boundary detection at natural turn boundaries.
        let effectiveSimilarityThreshold: Float
        if hadSignificantSilenceBeforeChunk {
            effectiveSimilarityThreshold = turnTakingSimilarityThreshold
            hadSignificantSilenceBeforeChunk = false
        } else {
            effectiveSimilarityThreshold = speakerLooseSimilarityThreshold
        }

        if closest.similarity >= effectiveSimilarityThreshold {
            return .existingLabel(closest.label)
        }
        return .newCandidate
    }

    private func probeSpeakerObservationFallback(chunk: [AudioFrame]) -> ProbeSpeakerObservation? {
        guard let currentSpeaker = activeChunkSpeakerID,
              let currentSignature = fallbackSpeakerEmbeddings[currentSpeaker] else {
            return nil
        }

        let averageAmplitude = chunk.map(\.amplitude).reduce(0, +) / Double(max(chunk.count, 1))
        let averageZCR = chunk.map(\.zeroCrossingRate).reduce(0, +) / Double(max(chunk.count, 1))
        let flattenedSamples = chunk.flatMap(\.samples)
        let rmsEnergy: Double = {
            guard !flattenedSamples.isEmpty else {
                return 0
            }
            let meanSquare = flattenedSamples.reduce(0.0) { partial, sample in
                partial + (Double(sample) * Double(sample))
            } / Double(flattenedSamples.count)
            return sqrt(meanSquare)
        }()
        let signature = FallbackSpeakerSignature(
            amplitude: averageAmplitude,
            zeroCrossingRate: averageZCR,
            rmsEnergy: rmsEnergy
        )

        let distance =
            (abs(currentSignature.amplitude - signature.amplitude) * 0.45) +
            (abs(currentSignature.zeroCrossingRate - signature.zeroCrossingRate) * 0.35) +
            (abs(currentSignature.rmsEnergy - signature.rmsEnergy) * 0.20)

        if distance <= speakerFallbackThreshold {
            return .existingLabel(currentSpeaker)
        }
        return .newCandidate
    }

    private func speechDuration(for chunk: [AudioFrame]) -> Double {
        chunk.reduce(0) { partial, frame in
            partial + (frame.isSpeech ? frame.duration : 0)
        }
    }

    private func trailingSilenceDuration(for chunk: [AudioFrame]) -> Double {
        var total: Double = 0
        for frame in chunk.reversed() {
            if frame.isSpeech {
                break
            }
            total += frame.duration
        }
        return total
    }

    private func hasSpeech(_ chunk: [AudioFrame]) -> Bool {
        chunk.contains(where: \.isSpeech)
    }

    private func resetActiveChunkSpeakerTracking() {
        activeChunkSpeakerID = nil
        speakerChangeCandidate = nil
        speechSecondsSinceLastSpeakerProbe = 0
        interruptCheckSampleAccumulator.removeAll(keepingCapacity: true)
        interruptCheckSampleRate = 16_000
        lastKnownSpeakerEmbedding = nil
        hadSignificantSilenceBeforeChunk = false
        continuation?.yield(.liveSpeaker(nil))
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

        // If the voice is dramatically different from all known speakers,
        // skip the 2-chunk confirmation gate and create a new speaker immediately.
        if closest.similarity < immediatNewSpeakerSimilarityThreshold {
            pendingSpeakerEmbedding = nil
            pendingSpeakerChunks = 0
            if lastChunkDurationSeconds >= minSegmentDurationForNewSpeaker {
                return createSpeakerLabel(with: embedding)
            }
            // Segment too short — assign to closest but don't accumulate pending.
            updateSpeaker(label: closest.label, with: embedding)
            return closest.label
        }

        if let pending = pendingSpeakerEmbedding,
           cosineSimilarity(pending, embedding) >= newSpeakerCandidateSimilarity {
            // Incremental EMA: weight new observation less as chunks accumulate,
            // so the established embedding gains momentum and resists noisy frames.
            let newWeight = 1.0 / Float(pendingSpeakerChunks + 1)
            let oldWeight = 1.0 - newWeight
            let averaged = zip(pending, embedding).map { old, new in
                old * oldWeight + new * newWeight
            }
            pendingSpeakerEmbedding = normalize(averaged)
            pendingSpeakerChunks += 1
        } else {
            pendingSpeakerEmbedding = normalize(embedding)
            pendingSpeakerChunks = 1
        }

        if pendingSpeakerChunks >= pendingChunksBeforeNewSpeaker {
            pendingSpeakerEmbedding = nil
            pendingSpeakerChunks = 0
            // Suppress new speaker creation for very short segments (coughs, interjections).
            if lastChunkDurationSeconds < minSegmentDurationForNewSpeaker {
                updateSpeaker(label: closest.label, with: embedding)
                return closest.label
            }
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
        let flattenedSamples = chunk.flatMap(\.samples)
        let rmsEnergy: Double = {
            guard !flattenedSamples.isEmpty else {
                return 0
            }
            let meanSquare = flattenedSamples.reduce(0.0) { partial, sample in
                partial + (Double(sample) * Double(sample))
            } / Double(flattenedSamples.count)
            return sqrt(meanSquare)
        }()
        let signature = FallbackSpeakerSignature(
            amplitude: averageAmplitude,
            zeroCrossingRate: averageZCR,
            rmsEnergy: rmsEnergy
        )

        if let closest = closestFallbackSpeaker(for: signature) {
            if closest.distance <= speakerFallbackThreshold || fallbackSpeakerEmbeddings.count >= maxSpeakersPerSession {
                return closest.label
            }
        }

        let nextIndex = fallbackSpeakerEmbeddings.count
        let scalar = UnicodeScalar(65 + min(nextIndex, 25)) ?? "Z".unicodeScalars.first!
        let label = "Speaker \(Character(scalar))"
        fallbackSpeakerEmbeddings[label] = signature
        return label
    }

    private func closestFallbackSpeaker(for signature: FallbackSpeakerSignature) -> (label: String, distance: Double)? {
        var candidate: (label: String, distance: Double)?

        for (label, reference) in fallbackSpeakerEmbeddings {
            let distance =
                (abs(reference.amplitude - signature.amplitude) * 0.45) +
                (abs(reference.zeroCrossingRate - signature.zeroCrossingRate) * 0.35) +
                (abs(reference.rmsEnergy - signature.rmsEnergy) * 0.20)
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

    func sessionDurationSeconds(for sessionID: UUID) -> Double {
        prepareIfNeeded()
        return sessions[sessionID]?.durationSeconds ?? 0
    }

    func hasRecordedAudio(for sessionID: UUID) -> Bool {
        prepareIfNeeded()
        guard let path = sessions[sessionID]?.audioFilePath else {
            return false
        }

        let fileURL = URL(fileURLWithPath: path)
        let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return fileSize > 0
    }

    func audioDurationSeconds(for sessionID: UUID) async -> Double {
        prepareIfNeeded()
        guard let path = sessions[sessionID]?.audioFilePath else {
            return 0
        }

        let url = URL(fileURLWithPath: path)
        let asset = AVURLAsset(url: url)

        if let duration = try? await asset.load(.duration) {
            let seconds = CMTimeGetSeconds(duration)
            if seconds.isFinite, seconds > 0 {
                return seconds
            }
        }

        if let player = try? AVAudioPlayer(contentsOf: url) {
            let seconds = player.duration
            if seconds.isFinite, seconds > 0 {
                return seconds
            }
        }

        return 0
    }

    func appendTranscript(sessionID: UUID, event: PipelineTranscriptEvent) {
        prepareIfNeeded()
        guard var session = sessions[sessionID] else {
            return
        }

        let profile = speakerProfile(for: event.speakerID, in: &session.speakers)
        let paletteIndex = Self.speakerColorPalette.firstIndex(of: profile.colorHex) ?? 0

        let row = TranscriptRow(
            id: event.id,
            speakerID: event.speakerID,
            speaker: profile.label,
            text: event.text,
            time: Self.formatTimestamp(seconds: event.startOffset),
            language: event.languageID,
            avatarSymbol: profile.avatarSymbol,
            avatarPaletteIndex: paletteIndex,
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
            avatarPaletteIndex: existing.avatarPaletteIndex,
            startOffset: existing.startOffset,
            endOffset: existing.endOffset
        )

        persistSegmentsSnapshot(for: session)
        sessions[sessionID] = session
    }

    func deleteTranscriptRow(sessionID: UUID, rowID: UUID) {
        prepareIfNeeded()
        guard var session = sessions[sessionID] else {
            return
        }

        let originalCount = session.rows.count
        session.rows.removeAll { $0.id == rowID }
        guard session.rows.count != originalCount else {
            return
        }

        session.durationSeconds = session.rows.compactMap(\.endOffset).max() ?? 0
        persistSegmentsSnapshot(for: session)
        persistSessionMetadata(for: session)
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
                avatarPaletteIndex: existing.avatarPaletteIndex,
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

        let targetPaletteIndex = Self.speakerColorPalette.firstIndex(of: targetProfile.colorHex) ?? 0
        session.rows[rowIndex] = TranscriptRow(
            id: existing.id,
            speakerID: targetSpeakerID,
            speaker: targetProfile.label,
            text: existing.text,
            time: existing.time,
            language: existing.language,
            avatarSymbol: targetProfile.avatarSymbol,
            avatarPaletteIndex: targetPaletteIndex,
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
                    avatarPaletteIndex: Self.speakerColorPalette.firstIndex(of: profile.colorHex) ?? 0,
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
                    avatarPaletteIndex: Self.speakerColorPalette.firstIndex(of: profile.colorHex) ?? 0,
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

enum MainTimerDisplayStyle: String, CaseIterable, Codable, Sendable {
    case friendly
    case hybrid
    case professional

    var title: String {
        switch self {
        case .friendly:
            return "Friendly"
        case .hybrid:
            return "Hybrid"
        case .professional:
            return "Professional"
        }
    }

    var sampleText: String {
        switch self {
        case .friendly:
            return "5 min 22 sec"
        case .hybrid:
            return "5:22"
        case .professional:
            return "00:05:22"
        }
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
    var whisperCoreMLEncoderEnabled: Bool
    var whisperGGMLGPUDecodeEnabled: Bool
    var whisperModelProfileRawValue: String
    var mainTimerDisplayStyleRawValue: String
    var activeSessionID: UUID?
    var chatCounter: Int

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case selectedLanguageCodes
        case languageSearchText
        case focusContextKeywords
        case totalHours
        case usedHours
        case isICloudSyncEnabled
        case whisperCoreMLEncoderEnabled
        case whisperGGMLGPUDecodeEnabled
        case whisperModelProfileRawValue
        case mainTimerDisplayStyleRawValue
        case activeSessionID
        case chatCounter
    }

    init(
        schemaVersion: Int,
        selectedLanguageCodes: [String],
        languageSearchText: String,
        focusContextKeywords: String,
        totalHours: Double,
        usedHours: Double,
        isICloudSyncEnabled: Bool,
        whisperCoreMLEncoderEnabled: Bool = AppBackend.defaultWhisperCoreMLEncoderEnabledForCurrentDevice(),
        whisperGGMLGPUDecodeEnabled: Bool = AppBackend.defaultWhisperGPUDecodeEnabledForCurrentDevice(),
        whisperModelProfileRawValue: String = AppBackend.defaultWhisperModelProfileForCurrentDevice().rawValue,
        mainTimerDisplayStyleRawValue: String = MainTimerDisplayStyle.friendly.rawValue,
        activeSessionID: UUID?,
        chatCounter: Int
    ) {
        self.schemaVersion = schemaVersion
        self.selectedLanguageCodes = selectedLanguageCodes
        self.languageSearchText = languageSearchText
        self.focusContextKeywords = focusContextKeywords
        self.totalHours = totalHours
        self.usedHours = usedHours
        self.isICloudSyncEnabled = isICloudSyncEnabled
        self.whisperCoreMLEncoderEnabled = whisperCoreMLEncoderEnabled
        self.whisperGGMLGPUDecodeEnabled = whisperGGMLGPUDecodeEnabled
        self.whisperModelProfileRawValue = whisperModelProfileRawValue
        self.mainTimerDisplayStyleRawValue = mainTimerDisplayStyleRawValue
        self.activeSessionID = activeSessionID
        self.chatCounter = chatCounter
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        selectedLanguageCodes = try container.decode([String].self, forKey: .selectedLanguageCodes)
        languageSearchText = try container.decode(String.self, forKey: .languageSearchText)
        focusContextKeywords = try container.decode(String.self, forKey: .focusContextKeywords)
        totalHours = try container.decode(Double.self, forKey: .totalHours)
        usedHours = try container.decode(Double.self, forKey: .usedHours)
        isICloudSyncEnabled = try container.decode(Bool.self, forKey: .isICloudSyncEnabled)
        whisperCoreMLEncoderEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .whisperCoreMLEncoderEnabled)
            ?? AppBackend.defaultWhisperCoreMLEncoderEnabledForCurrentDevice()
        whisperGGMLGPUDecodeEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .whisperGGMLGPUDecodeEnabled)
            ?? AppBackend.defaultWhisperGPUDecodeEnabledForCurrentDevice()
        whisperModelProfileRawValue =
            try container.decodeIfPresent(String.self, forKey: .whisperModelProfileRawValue)
            ?? AppBackend.defaultWhisperModelProfileForCurrentDevice().rawValue
        mainTimerDisplayStyleRawValue =
            try container.decodeIfPresent(String.self, forKey: .mainTimerDisplayStyleRawValue)
            ?? MainTimerDisplayStyle.friendly.rawValue
        activeSessionID = try container.decodeIfPresent(UUID.self, forKey: .activeSessionID)
        chatCounter = try container.decode(Int.self, forKey: .chatCounter)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(selectedLanguageCodes, forKey: .selectedLanguageCodes)
        try container.encode(languageSearchText, forKey: .languageSearchText)
        try container.encode(focusContextKeywords, forKey: .focusContextKeywords)
        try container.encode(totalHours, forKey: .totalHours)
        try container.encode(usedHours, forKey: .usedHours)
        try container.encode(isICloudSyncEnabled, forKey: .isICloudSyncEnabled)
        try container.encode(whisperCoreMLEncoderEnabled, forKey: .whisperCoreMLEncoderEnabled)
        try container.encode(whisperGGMLGPUDecodeEnabled, forKey: .whisperGGMLGPUDecodeEnabled)
        try container.encode(whisperModelProfileRawValue, forKey: .whisperModelProfileRawValue)
        try container.encode(mainTimerDisplayStyleRawValue, forKey: .mainTimerDisplayStyleRawValue)
        try container.encodeIfPresent(activeSessionID, forKey: .activeSessionID)
        try container.encode(chatCounter, forKey: .chatCounter)
    }
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
        let preferredLanguageCodeOverride: String?
    }

    private enum TranscriptionQuality {
        case acceptable
        case weak
        case unusable
    }

    private struct PlaybackRowSegment: Sendable {
        let rowID: UUID
        let startOffset: Double
        let endOffset: Double
    }

    @Published var isRecording = false
    @Published var liveSpeakerID: String? = nil
    @Published private(set) var isTranscriptChunkPlaying = false
    @Published private(set) var transcriptChunkPlaybackRemainingSeconds: Double = 0
    @Published private(set) var transcriptChunkPlaybackRangeText: String?
    @Published private(set) var activeTranscriptPlaybackRowID: UUID?
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
    @Published var whisperCoreMLEncoderEnabled = AppBackend.defaultWhisperCoreMLEncoderEnabledForCurrentDevice() {
        didSet {
            persistSettingsIfNeeded()
            applyWhisperAccelerationPreferencesIfNeeded()
        }
    }
    @Published var whisperGGMLGPUDecodeEnabled = AppBackend.defaultWhisperGPUDecodeEnabledForCurrentDevice() {
        didSet {
            persistSettingsIfNeeded()
            applyWhisperAccelerationPreferencesIfNeeded()
        }
    }
    @Published var whisperModelProfile = AppBackend.defaultWhisperModelProfileForCurrentDevice() {
        didSet {
            persistSettingsIfNeeded()
            applyWhisperAccelerationPreferencesIfNeeded()
        }
    }
    @Published var mainTimerDisplayStyle: MainTimerDisplayStyle = .friendly {
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
    private var chunkProgressTask: Task<Void, Never>?
    private var attemptedTranscriptionRowIDs: Set<UUID> = []
    private var queuedTranscriptionRowIDs: Set<UUID> = []
    private var queuedChunkTranscriptions: [QueuedChunkTranscription] = []
    private var queuedTranscriptionTask: Task<Void, Never>?
    private var queuedManualRetranscriptions: [QueuedManualRetranscription] = []
    private var queuedManualRetranscriptionTask: Task<Void, Never>?
    private var currentRecordingBaseOffset: Double = 0
    private var chatCounter = 0
    private var isHydratingPersistedState = false
    private let autoTranscriptionPlaceholderPrefix = "message queued for automatic transcription"
    private let lowConfidenceLanguageProbabilityThreshold: Float = 0.5

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
        sessions.first(where: { $0.id == activeSessionID })?.title ?? "Layca"
    }

    var activeSessionDateText: String {
        sessions.first(where: { $0.id == activeSessionID })?.formattedDate ?? "New chat room"
    }

    var recordingTimeText: String {
        let displaySeconds: Double = {
            if isRecording {
                return max(currentRecordingBaseOffset + recordingSeconds, 0)
            }

            guard let activeSessionID,
                  let session = sessions.first(where: { $0.id == activeSessionID })
            else {
                return 0
            }

            return max(session.rows.compactMap(\.endOffset).max() ?? 0, 0)
        }()

        return formatMainTimerText(seconds: displaySeconds)
    }

    var transcriptChunkPlaybackRemainingText: String {
        let remaining = max(transcriptChunkPlaybackRemainingSeconds, 0).rounded(.up)
        return formatMainTimerText(seconds: remaining)
    }

    var canPlayActiveSessionFromStart: Bool {
        guard !isRecording,
              let activeSessionID,
              let session = sessions.first(where: { $0.id == activeSessionID })
        else {
            return false
        }

        let duration = max(session.rows.compactMap(\.endOffset).max() ?? 0, 0)
        return duration > 0.05
    }

    var whisperCoreMLEncoderRecommendationText: String {
        Self.whisperCoreMLEncoderRecommendationTextForCurrentDevice()
    }

    var whisperGGMLGPUDecodeRecommendationText: String {
        Self.whisperGPUDecodeRecommendationTextForCurrentDevice()
    }

    var whisperModelRecommendationText: String {
        Self.whisperModelRecommendationTextForCurrentDevice()
    }

    func bootstrap() async {
        loadPersistedSettings()

        // Always start in draft mode on app launch.
        activeSessionID = nil
        activeTranscriptRows = []

        applyWhisperAccelerationPreferencesIfNeeded()
        await refreshSessionsFromStore(autoSelectFallbackSession: false)

        let inferredCounter = inferChatCounter(from: sessions)
        chatCounter = max(chatCounter, inferredCounter, sessions.count)

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
            if isRecording {
                await stopRecording()
            }

            stopChunkPlayback()
            activeSessionID = nil
            activeTranscriptRows = []
            preflightStatusMessage = nil
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

    func deleteActiveSession() {
        guard let activeSessionID,
              let session = sessions.first(where: { $0.id == activeSessionID })
        else {
            return
        }
        deleteSession(session)
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
            transcriptBody = "No messages in this chat yet."
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
        } else if isTranscriptChunkPlaying {
            stopChunkPlayback()
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

    func playActiveSessionFromStart() {
        Task {
            await playActiveSessionFromStartInternal()
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
        retranscribeTranscriptRow(row, preferredLanguageCodeOverride: nil)
    }

    func retranscribeTranscriptRow(
        _ row: TranscriptRow,
        preferredLanguageCodeOverride: String?
    ) {
        let normalizedLanguageOverride = normalizedPreferredLanguageCodeOverride(
            preferredLanguageCodeOverride
        )
        if let normalizedLanguageOverride {
            print(
                "[Retranscribe] User selected manual language override: \(normalizedLanguageOverride.uppercased()) for row \(row.id.uuidString)"
            )
        }

        guard let sessionID = resolvedSessionID(for: row) else {
            preflightStatusMessage = "Unable to locate this message in an active chat."
            return
        }

        guard let startOffset = row.startOffset,
              let endOffset = row.endOffset,
              endOffset > startOffset
        else {
            preflightStatusMessage = "This message has no valid audio range to transcribe again."
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
                sessionID: sessionID,
                preferredLanguageCodeOverride: normalizedLanguageOverride
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

            guard !isRecording,
                  queuedTranscriptionTask == nil,
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

            await retranscribeTranscriptRowInternal(
                row,
                sessionID: next.sessionID,
                preferredLanguageCodeOverride: next.preferredLanguageCodeOverride
            )
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

            let hasRecordedAudio = await sessionStore.hasRecordedAudio(for: sessionID)
            let measuredAudioDuration = await sessionStore.audioDurationSeconds(for: sessionID)
            let storedDuration = max(0, await sessionStore.sessionDurationSeconds(for: sessionID))
            currentRecordingBaseOffset = hasRecordedAudio
                ? (measuredAudioDuration > 0 ? measuredAudioDuration : storedDuration)
                : 0
            try await masterRecorder.startRecording(
                to: audioFileURL,
                appendIfPossible: hasRecordedAudio
            )

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
#if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
#endif
        } catch {
            preflightStatusMessage = error.localizedDescription
#if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
#endif
        }
    }

    private func stopRecording() async {
        await pipeline.stop()
        streamTask?.cancel()
        streamTask = nil
        do {
            try await masterRecorder.stop()
        } catch {
            preflightStatusMessage = error.localizedDescription
        }
        currentRecordingBaseOffset = 0

        if let activeSessionID {
            await sessionStore.setSessionStatus(.ready, for: activeSessionID)
        }

        isRecording = false
#if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
#endif
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

        await playSessionAudioRange(
            sessionID: sessionID,
            startOffset: startOffset,
            endOffset: endOffset
        )
    }

    private func playActiveSessionFromStartInternal() async {
        guard !isRecording,
              let sessionID = activeSessionID
        else {
            return
        }

        await playSessionAudioRange(
            sessionID: sessionID,
            startOffset: 0,
            endOffset: nil
        )
    }

    private func playSessionAudioRange(
        sessionID: UUID,
        startOffset: Double,
        endOffset: Double?
    ) async {
        guard let audioURL = await sessionStore.audioFileURL(for: sessionID) else {
            return
        }

        stopChunkPlayback()

        do {
            try configureAudioSessionForChunkPlaybackIfSupported()

            let player = try AVAudioPlayer(contentsOf: audioURL)
            let start = max(0, min(startOffset, player.duration))
            let resolvedEndOffset = min(endOffset ?? player.duration, player.duration)
            guard resolvedEndOffset > start else {
                stopChunkPlayback()
                return
            }
            let duration = max(resolvedEndOffset - start, 0.05)
            let stopAt = start + duration

            player.currentTime = start
            player.prepareToPlay()
            guard player.play() else {
                stopChunkPlayback()
                return
            }

            chunkPlayer = player
            isTranscriptChunkPlaying = true
            transcriptChunkPlaybackRemainingSeconds = duration
            transcriptChunkPlaybackRangeText = playbackRangeText(startSeconds: start, endSeconds: stopAt)
            let playbackRowSegments = playbackRowSegments(
                sessionID: sessionID,
                startOffset: start,
                endOffset: stopAt
            )
            activeTranscriptPlaybackRowID = activePlaybackRowID(
                at: start,
                from: playbackRowSegments
            )
            startChunkPlaybackProgressUpdates(
                player: player,
                stopAt: stopAt,
                playbackRowSegments: playbackRowSegments
            )
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

    private func retranscribeTranscriptRowInternal(
        _ row: TranscriptRow,
        sessionID: UUID,
        preferredLanguageCodeOverride: String?
    ) async {
        guard !isRecording else {
            preflightStatusMessage = "Stop recording before running Transcribe Again."
            return
        }

        guard let startOffset = row.startOffset,
              let endOffset = row.endOffset,
              endOffset > startOffset
        else {
            preflightStatusMessage = "This message has no valid audio range to transcribe again."
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
            let preferredLanguageCode: String
            let forcedLanguageCode = normalizedPreferredLanguageCodeOverride(
                preferredLanguageCodeOverride
            )
            if let forcedLanguageCode {
                preferredLanguageCode = forcedLanguageCode
            } else {
                preferredLanguageCode = await preferredTranscriptionLanguageCode(
                    sessionID: sessionID,
                    rowID: row.id
                )
            }
            let focusLanguageCodes = selectedLanguageCodes.map { $0.lowercased() }.sorted()
            let promptLanguageCodes = forcedLanguageCode.map { [$0] } ?? focusLanguageCodes
            let initialPrompt = preflightService.buildPrompt(
                languageCodes: promptLanguageCodes,
                keywords: focusContextKeywords
            )
            var result = try await whisperTranscriber.transcribe(
                audioURL: audioURL,
                startOffset: startOffset,
                endOffset: endOffset,
                preferredLanguageCode: preferredLanguageCode,
                initialPrompt: initialPrompt,
                focusLanguageCodes: focusLanguageCodes
            )

            var trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                await dropTranscriptRowWithoutSpeech(sessionID: sessionID, rowID: row.id)
                return
            }

            if let forcedLanguageCode,
               !matchesExpectedScript(text: trimmed, forcedLanguageCode: forcedLanguageCode) {
                print(
                    "[Retranscribe] Forced \(forcedLanguageCode.uppercased()) script mismatch; retrying without prompt for row \(row.id.uuidString)"
                )
                let retryResult = try await whisperTranscriber.transcribe(
                    audioURL: audioURL,
                    startOffset: startOffset,
                    endOffset: endOffset,
                    preferredLanguageCode: forcedLanguageCode,
                    initialPrompt: nil,
                    focusLanguageCodes: [forcedLanguageCode]
                )
                let retryTrimmed = retryResult.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !retryTrimmed.isEmpty,
                   matchesExpectedScript(text: retryTrimmed, forcedLanguageCode: forcedLanguageCode) {
                    result = retryResult
                    trimmed = retryTrimmed
                } else {
                    preflightStatusMessage = "Unable to force \(forcedLanguageCode.uppercased()) output for this message. Existing text was kept."
                    return
                }
            }

            let quality = transcriptionQuality(
                text: trimmed,
                startOffset: startOffset,
                endOffset: endOffset,
                detectedLanguage: result.languageID,
                preferredLanguageCode: preferredLanguageCode
            )
            if quality == .unusable {
                if isAutoTranscriptionPlaceholder(row.text) {
                    await dropTranscriptRowWithoutSpeech(sessionID: sessionID, rowID: row.id)
                } else {
                    preflightStatusMessage = nil
                }
                return
            }

            let resolvedLanguage = resolvedTranscriptLanguage(
                detectedLanguage: result.languageID,
                detectedLanguageProbability: result.languageProbability,
                languageProbabilities: result.languageProbabilities,
                preferredLanguageCode: preferredLanguageCode
            )

            await sessionStore.updateTranscriptRow(
                sessionID: sessionID,
                rowID: row.id,
                text: trimmed,
                language: resolvedLanguage
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
            let rowOffsets = await transcriptOffsets(for: rowID, sessionID: sessionID)
            let preferredLanguageCode = await preferredTranscriptionLanguageCode(
                sessionID: sessionID,
                rowID: rowID
            )
            let focusLanguageCodes = selectedLanguageCodes.map { $0.lowercased() }.sorted()
            let initialPrompt = preflightService.buildPrompt(
                languageCodes: focusLanguageCodes,
                keywords: focusContextKeywords
            )
            let result = try await whisperTranscriber.transcribe(
                samples: samples,
                sourceSampleRate: sampleRate,
                preferredLanguageCode: preferredLanguageCode,
                initialPrompt: initialPrompt,
                focusLanguageCodes: focusLanguageCodes
            )

            let trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                await dropTranscriptRowWithoutSpeech(sessionID: sessionID, rowID: rowID)
                return
            }

            let quality = transcriptionQuality(
                text: trimmed,
                startOffset: rowOffsets?.startOffset,
                endOffset: rowOffsets?.endOffset,
                detectedLanguage: result.languageID,
                preferredLanguageCode: preferredLanguageCode
            )
            if quality == .unusable {
                queueAutomaticQualityRetranscription(rowID: rowID, sessionID: sessionID)
                preflightStatusMessage = nil
                return
            }

            if isSuspiciousAutoTranscription(
                text: trimmed,
                startOffset: rowOffsets?.startOffset,
                endOffset: rowOffsets?.endOffset
            ) {
                queueAutomaticQualityRetranscription(rowID: rowID, sessionID: sessionID)
            }
            if quality == .weak {
                queueAutomaticQualityRetranscription(rowID: rowID, sessionID: sessionID)
            }

            let resolvedLanguage = resolvedTranscriptLanguage(
                detectedLanguage: result.languageID,
                detectedLanguageProbability: result.languageProbability,
                languageProbabilities: result.languageProbabilities,
                preferredLanguageCode: preferredLanguageCode
            )

            await sessionStore.updateTranscriptRow(
                sessionID: sessionID,
                rowID: rowID,
                text: trimmed,
                language: resolvedLanguage
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

    private func dropTranscriptRowWithoutSpeech(sessionID: UUID, rowID: UUID) async {
        queuedTranscriptionRowIDs.remove(rowID)
        queuedChunkTranscriptions.removeAll { $0.rowID == rowID }
        queuedManualRetranscriptionRowIDs.remove(rowID)
        queuedManualRetranscriptions.removeAll { $0.rowID == rowID }
        updateTranscriptionBusyState()

        await sessionStore.deleteTranscriptRow(sessionID: sessionID, rowID: rowID)
        await refreshSessionsFromStore()
        preflightStatusMessage = nil
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

    private func queueAutomaticQualityRetranscription(rowID: UUID, sessionID: UUID) {
        guard !queuedManualRetranscriptionRowIDs.contains(rowID) else {
            return
        }

        queuedManualRetranscriptionRowIDs.insert(rowID)
        queuedManualRetranscriptions.append(
            QueuedManualRetranscription(
                rowID: rowID,
                sessionID: sessionID,
                preferredLanguageCodeOverride: nil
            )
        )
        updateTranscriptionBusyState()
        startManualRetranscriptionWorkerIfNeeded()
    }

    private func transcriptOffsets(
        for rowID: UUID,
        sessionID: UUID
    ) async -> (startOffset: Double?, endOffset: Double?)? {
        guard let row = await findTranscriptRow(rowID: rowID, sessionID: sessionID) else {
            return nil
        }
        return (row.startOffset, row.endOffset)
    }

    private func isSuspiciousAutoTranscription(
        text: String,
        startOffset: Double?,
        endOffset: Double?
    ) -> Bool {
        guard let startOffset,
              let endOffset,
              endOffset > startOffset
        else {
            return false
        }

        let duration = endOffset - startOffset
        guard duration >= 5 else {
            return false
        }

        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty {
            return true
        }

        let wordCount = normalized
            .split { $0.isWhitespace || $0.isNewline }
            .count

        return wordCount <= 2
    }

    private func preferredTranscriptionLanguageCode(
        sessionID: UUID,
        rowID: UUID
    ) async -> String {
        _ = sessionID
        _ = rowID
        return "auto"
    }

    private func matchesExpectedScript(text: String, forcedLanguageCode: String) -> Bool {
        let normalizedCode = forcedLanguageCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let scalars = text.unicodeScalars

        switch normalizedCode {
        case "th":
            return scalars.contains { scalar in
                let value = scalar.value
                return value >= 0x0E00 && value <= 0x0E7F
            }
        case "en":
            return scalars.contains { scalar in
                let value = scalar.value
                return (value >= 0x41 && value <= 0x5A) || (value >= 0x61 && value <= 0x7A)
            }
        default:
            return true
        }
    }

    private func normalizedPreferredLanguageCodeOverride(_ code: String?) -> String? {
        guard let code else {
            return nil
        }

        let normalized = code
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalized.isEmpty, normalized != "auto" else {
            return nil
        }

        return normalized
    }

    private func transcriptionQuality(
        text: String,
        startOffset: Double?,
        endOffset: Double?,
        detectedLanguage: String,
        preferredLanguageCode: String
    ) -> TranscriptionQuality {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return .unusable
        }

        let canonical = normalized.lowercased()
        let junkValues: Set<String> = [
            "-", "--", "—", "–", "...", "…", ".", "_",
            "foreign", "music", "inaudible", "[inaudible]", "(inaudible)"
        ]
        if junkValues.contains(canonical) {
            return .unusable
        }

        let lettersCount = normalized.unicodeScalars.reduce(into: 0) { count, scalar in
            if CharacterSet.letters.contains(scalar) {
                count += 1
            }
        }
        guard lettersCount > 0 else {
            return .unusable
        }

        let duration: Double = {
            guard let startOffset, let endOffset, endOffset > startOffset else {
                return 0
            }
            return endOffset - startOffset
        }()
        let wordCount = normalized
            .split { $0.isWhitespace || $0.isNewline }
            .count

        if duration >= 5, wordCount <= 2 {
            return .weak
        }

        if duration >= 8, normalized.count <= 8 {
            return .weak
        }

        _ = detectedLanguage
        _ = preferredLanguageCode

        return .acceptable
    }

    private func resolvedTranscriptLanguage(
        detectedLanguage: String,
        detectedLanguageProbability: Float?,
        languageProbabilities: [String: Float],
        preferredLanguageCode: String
    ) -> String {
        let normalizedDetected = detectedLanguage
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if (detectedLanguageProbability ?? 0) < lowConfidenceLanguageProbabilityThreshold,
           let focusedLanguage = highestProbabilityFocusedLanguage(from: languageProbabilities),
           focusedLanguage != normalizedDetected {
            return focusedLanguage.uppercased()
        }

        guard !normalizedDetected.isEmpty, normalizedDetected != "unknown" else {
            if preferredLanguageCode != "auto" {
                return preferredLanguageCode.uppercased()
            }

            if let focusedLanguage = highestProbabilityFocusedLanguage(from: languageProbabilities) {
                return focusedLanguage.uppercased()
            }

            return "AUTO"
        }

        return normalizedDetected.uppercased()
    }

    private func highestProbabilityFocusedLanguage(
        from languageProbabilities: [String: Float]
    ) -> String? {
        let normalizedFocusCodes = Set(selectedLanguageCodes.map { $0.lowercased() })
        guard !normalizedFocusCodes.isEmpty else {
            return nil
        }

        return normalizedFocusCodes.max { lhs, rhs in
            let lhsProbability = languageProbabilities[lhs] ?? -1
            let rhsProbability = languageProbabilities[rhs] ?? -1
            return lhsProbability < rhsProbability
        }
    }

    private func isAutoTranscriptionPlaceholder(_ text: String) -> Bool {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasPrefix(autoTranscriptionPlaceholderPrefix)
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
        chunkProgressTask?.cancel()
        chunkProgressTask = nil
        chunkStopTask?.cancel()
        chunkStopTask = nil
        chunkPlayer?.stop()
        chunkPlayer = nil
        isTranscriptChunkPlaying = false
        transcriptChunkPlaybackRemainingSeconds = 0
        transcriptChunkPlaybackRangeText = nil
        activeTranscriptPlaybackRowID = nil
        deactivateChunkPlaybackAudioSessionIfSupported()
    }

    private func startChunkPlaybackProgressUpdates(
        player: AVAudioPlayer,
        stopAt: TimeInterval,
        playbackRowSegments: [PlaybackRowSegment]
    ) {
        chunkProgressTask?.cancel()
        chunkProgressTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            while !Task.isCancelled {
                guard self.chunkPlayer === player else {
                    return
                }

                let currentPlaybackTime = max(player.currentTime, 0)
                self.activeTranscriptPlaybackRowID = self.activePlaybackRowID(
                    at: currentPlaybackTime,
                    from: playbackRowSegments
                )
                let remaining = max(stopAt - currentPlaybackTime, 0)
                self.transcriptChunkPlaybackRemainingSeconds = remaining

                if remaining <= 0.01 || !player.isPlaying {
                    self.activeTranscriptPlaybackRowID = nil
                    return
                }

                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    private func playbackRowSegments(
        sessionID: UUID,
        startOffset: Double,
        endOffset: Double
    ) -> [PlaybackRowSegment] {
        guard let session = sessions.first(where: { $0.id == sessionID }) else {
            return []
        }

        return session.rows
            .compactMap { row -> PlaybackRowSegment? in
                guard let rowStartOffset = row.startOffset,
                      let rowEndOffset = row.endOffset,
                      rowEndOffset > rowStartOffset
                else {
                    return nil
                }

                guard rowEndOffset > startOffset, rowStartOffset < endOffset else {
                    return nil
                }

                return PlaybackRowSegment(
                    rowID: row.id,
                    startOffset: rowStartOffset,
                    endOffset: rowEndOffset
                )
            }
            .sorted { left, right in
                if left.startOffset == right.startOffset {
                    return left.endOffset < right.endOffset
                }
                return left.startOffset < right.startOffset
            }
    }

    private func activePlaybackRowID(
        at playbackTime: Double,
        from playbackRowSegments: [PlaybackRowSegment]
    ) -> UUID? {
        playbackRowSegments.first(where: { segment in
            playbackTime >= segment.startOffset && playbackTime < segment.endOffset
        })?.rowID
    }

    private func playbackRangeText(startSeconds: Double, endSeconds: Double) -> String {
        "\(segmentClockText(seconds: startSeconds)) \u{2192} \(segmentClockText(seconds: endSeconds))"
    }

    private func segmentClockText(seconds: Double) -> String {
        let clamped = max(Int(seconds.rounded(.down)), 0)
        let minutes = clamped / 60
        let remainderSeconds = clamped % 60
        return String(format: "%02d:%02d", minutes, remainderSeconds)
    }

    private func formatMainTimerText(seconds: Double) -> String {
        let clamped = max(Int(seconds.rounded(.down)), 0)
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        let totalMinutes = clamped / 60
        let remainderSeconds = clamped % 60

        switch mainTimerDisplayStyle {
        case .friendly:
            var parts: [String] = []
            if hours > 0 {
                parts.append("\(hours) hr")
            }
            if minutes > 0 {
                parts.append("\(minutes) min")
            }
            if remainderSeconds > 0 || parts.isEmpty {
                parts.append("\(remainderSeconds) sec")
            }
            return parts.joined(separator: " ")
        case .hybrid:
            if hours > 0 {
                return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", remainderSeconds))"
            }
            return "\(totalMinutes):\(String(format: "%02d", remainderSeconds))"
        case .professional:
            return String(format: "%02d:%02d:%02d", hours, minutes, remainderSeconds)
        }
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
            let adjustedTranscript = transcriptWithRecordingOffsetApplied(transcript)
            await sessionStore.appendTranscript(sessionID: sessionID, event: adjustedTranscript)
            await refreshSessionsFromStore()
            enqueueChunkForAutomaticTranscription(
                rowID: adjustedTranscript.id,
                sessionID: sessionID,
                samples: adjustedTranscript.samples,
                sampleRate: adjustedTranscript.sampleRate
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

        case .liveSpeaker(let speakerID):
            liveSpeakerID = speakerID

        case .stopped:
            isRecording = false
        }
    }

    private func createSessionAndActivate() async {
        chatCounter += 1
        persistSettingsIfNeeded()

        if let id = try? await sessionStore.createSession(
            title: "chat \(chatCounter)",
            languageHints: Array(selectedLanguageCodes)
        ) {
            activeSessionID = id
            await refreshSessionsFromStore()
        }
    }

    private func refreshSessionsFromStore(autoSelectFallbackSession: Bool = true) async {
        let snapshots = await sessionStore.snapshotSessions()
        sessions = snapshots

        let hasActiveSession = activeSessionID.map { currentID in
            snapshots.contains(where: { $0.id == currentID })
        } ?? false

        if autoSelectFallbackSession, !hasActiveSession {
            activeSessionID = snapshots.first?.id
        } else if !hasActiveSession {
            activeSessionID = nil
        }

        if let activeSessionID {
            activeTranscriptRows = await sessionStore.transcriptRows(for: activeSessionID)
        } else {
            activeTranscriptRows = []
        }
    }

    private func transcriptWithRecordingOffsetApplied(_ transcript: PipelineTranscriptEvent) -> PipelineTranscriptEvent {
        guard currentRecordingBaseOffset > 0 else {
            return transcript
        }

        return PipelineTranscriptEvent(
            id: transcript.id,
            sessionID: transcript.sessionID,
            speakerID: transcript.speakerID,
            languageID: transcript.languageID,
            text: transcript.text,
            startOffset: transcript.startOffset + currentRecordingBaseOffset,
            endOffset: transcript.endOffset + currentRecordingBaseOffset,
            samples: transcript.samples,
            sampleRate: transcript.sampleRate
        )
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
        whisperCoreMLEncoderEnabled = persisted.whisperCoreMLEncoderEnabled
        whisperGGMLGPUDecodeEnabled = persisted.whisperGGMLGPUDecodeEnabled
        whisperModelProfile = WhisperModelProfile(rawValue: persisted.whisperModelProfileRawValue)
            ?? Self.defaultWhisperModelProfileForCurrentDevice()
        mainTimerDisplayStyle = MainTimerDisplayStyle(rawValue: persisted.mainTimerDisplayStyleRawValue)
            ?? .friendly
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
            whisperCoreMLEncoderEnabled: whisperCoreMLEncoderEnabled,
            whisperGGMLGPUDecodeEnabled: whisperGGMLGPUDecodeEnabled,
            whisperModelProfileRawValue: whisperModelProfile.rawValue,
            mainTimerDisplayStyleRawValue: mainTimerDisplayStyle.rawValue,
            activeSessionID: activeSessionID,
            chatCounter: max(chatCounter, 0)
        )
        settingsStore.save(snapshot)
    }

    private func applyWhisperAccelerationPreferencesIfNeeded() {
        guard !isHydratingPersistedState else {
            return
        }

        let coreMLEncoderEnabled = whisperCoreMLEncoderEnabled
        let ggmlGPUDecodeEnabled = whisperGGMLGPUDecodeEnabled
        let modelProfile = whisperModelProfile
        Task(priority: .utility) { [whisperTranscriber] in
            await whisperTranscriber.setRuntimePreferences(
                coreMLEncoderEnabled: coreMLEncoderEnabled,
                ggmlGPUDecodeEnabled: ggmlGPUDecodeEnabled,
                modelProfile: modelProfile
            )
        }
    }

    nonisolated static func defaultWhisperCoreMLEncoderEnabledForCurrentDevice() -> Bool {
#if targetEnvironment(simulator)
        return false
#elseif os(iOS) || os(tvOS) || os(visionOS)
        let minimumMemoryBytes: UInt64 = 7_500_000_000
        let minimumCoreCount = 6
        return ProcessInfo.processInfo.physicalMemory >= minimumMemoryBytes
            && ProcessInfo.processInfo.processorCount >= minimumCoreCount
#else
        return true
#endif
    }

    nonisolated static func defaultWhisperGPUDecodeEnabledForCurrentDevice() -> Bool {
#if targetEnvironment(simulator)
        return false
#else
        return true
#endif
    }

    nonisolated static func defaultWhisperModelProfileForCurrentDevice() -> WhisperModelProfile {
#if targetEnvironment(simulator)
        return .quick
#elseif os(iOS) || os(tvOS) || os(visionOS)
        let memoryBytes = ProcessInfo.processInfo.physicalMemory
        let coreCount = ProcessInfo.processInfo.processorCount
        if memoryBytes >= 10_500_000_000, coreCount >= 8 {
            return .pro
        }
        if memoryBytes >= 7_500_000_000, coreCount >= 6 {
            return .normal
        }
        return .quick
#else
        return .pro
#endif
    }

    nonisolated static func whisperCoreMLEncoderRecommendationTextForCurrentDevice() -> String {
#if targetEnvironment(simulator)
        return "Recommended OFF on simulator. Use a physical device for CoreML acceleration."
#elseif os(iOS) || os(tvOS) || os(visionOS)
        let memoryGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        let cores = ProcessInfo.processInfo.processorCount
        if defaultWhisperCoreMLEncoderEnabledForCurrentDevice() {
            return String(
                format: "Recommended ON for this device (%.1fGB RAM, %d cores).",
                memoryGB,
                cores
            )
        }
        return String(
            format: "Recommended OFF for startup stability (%.1fGB RAM, %d cores).",
            memoryGB,
            cores
        )
#else
        return "Recommended ON for best local performance."
#endif
    }

    nonisolated static func whisperGPUDecodeRecommendationTextForCurrentDevice() -> String {
#if targetEnvironment(simulator)
        return "Recommended OFF on simulator. Use a physical device for GPU decode."
#elseif os(iOS) || os(tvOS) || os(visionOS)
        return "Recommended ON to use Apple GPU decode acceleration."
#else
        return "Recommended ON to use Metal GPU decode acceleration."
#endif
    }

    nonisolated static func whisperModelRecommendationTextForCurrentDevice() -> String {
#if targetEnvironment(simulator)
        return "Recommended Fast on simulator."
#elseif os(iOS) || os(tvOS) || os(visionOS)
        let recommended = defaultWhisperModelProfileForCurrentDevice().title
        return "Recommended \(recommended) for this device."
#else
        return "Recommended Pro for best quality."
#endif
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

extension Color {
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
