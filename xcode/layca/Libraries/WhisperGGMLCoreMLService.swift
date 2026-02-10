import Foundation
import AVFoundation
import whisper

struct WhisperTranscriptionResult: Sendable {
    let languageID: String
    let text: String
}

enum WhisperGGMLCoreMLError: LocalizedError {
    case invalidChunkOffsets
    case modelUnavailable
    case downloadFailed
    case contextInitializationFailed
    case noAudioSamples
    case inferenceFailed

    var errorDescription: String? {
        switch self {
        case .invalidChunkOffsets:
            return "Invalid chunk range for Whisper transcription."
        case .modelUnavailable:
            return "Whisper model file is not available."
        case .downloadFailed:
            return "Whisper model download failed."
        case .contextInitializationFailed:
            return "Whisper failed to initialize model context."
        case .noAudioSamples:
            return "No audio samples were found for this chunk."
        case .inferenceFailed:
            return "Whisper failed while transcribing this chunk."
        }
    }
}

actor WhisperGGMLCoreMLService {
    private struct Constants {
        static let modelFileName = "ggml-large-v3-turbo.bin"
        static let modelName = "ggml-large-v3-turbo"
        static let encoderDirectoryName = "ggml-large-v3-turbo-encoder.mlmodelc"
        static let encoderModelName = "ggml-large-v3-turbo-encoder"
        static let bundledSubdirectories = ["Models/RuntimeAssets", "Models"]
        static let modelDownloadURL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin?download=true"
        static let targetSampleRate: Double = 16_000
        static let minimumModelSizeBytes: Int64 = 1_000_000_000
        static let coreMLEncoderEnvKey = "LAYCA_ENABLE_WHISPER_COREML_ENCODER"
        static let coreMLEncoderEnabledByDefault = false
    }

    private let fileManager: FileManager
    private let rootDirectory: URL
    private var context: OpaquePointer?
    private var activeModelPath: String?
    private var didWarmupInference = false
    private var shouldForceCPUContext = false

    init(fileManager: FileManager = .default, rootDirectory: URL? = nil) {
        self.fileManager = fileManager

        if let rootDirectory {
            self.rootDirectory = rootDirectory
        } else {
            let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            self.rootDirectory = caches.appendingPathComponent("WhisperGGML", isDirectory: true)
        }
    }

    deinit {
        if let context {
            whisper_free(context)
        }
    }

    func prepareIfNeeded() async throws {
        let ctx = try await ensureContext()
        try warmupInferenceIfNeeded(context: ctx)
    }

    func transcribe(
        audioURL: URL,
        startOffset: Double,
        endOffset: Double,
        preferredLanguageCode: String,
        initialPrompt: String?
    ) async throws -> WhisperTranscriptionResult {
        guard endOffset > startOffset else {
            throw WhisperGGMLCoreMLError.invalidChunkOffsets
        }

        let ctx = try await ensureContext()
        let samples16k = try Self.loadSamples(
            from: audioURL,
            startOffset: startOffset,
            endOffset: endOffset
        )
        guard !samples16k.isEmpty else {
            throw WhisperGGMLCoreMLError.noAudioSamples
        }

        return try transcribeSamples(
            samples16k,
            context: ctx,
            preferredLanguageCode: preferredLanguageCode,
            initialPrompt: initialPrompt
        )
    }

    func transcribe(
        samples: [Float],
        sourceSampleRate: Double,
        preferredLanguageCode: String,
        initialPrompt: String?
    ) async throws -> WhisperTranscriptionResult {
        let ctx = try await ensureContext()
        let samples16k = Self.resampleTo16k(samples: samples, sourceSampleRate: sourceSampleRate)
        guard !samples16k.isEmpty else {
            throw WhisperGGMLCoreMLError.noAudioSamples
        }

        return try transcribeSamples(
            samples16k,
            context: ctx,
            preferredLanguageCode: preferredLanguageCode,
            initialPrompt: initialPrompt
        )
    }

    private func transcribeSamples(
        _ samples: [Float],
        context: OpaquePointer,
        preferredLanguageCode: String,
        initialPrompt: String?
    ) throws -> WhisperTranscriptionResult {
        let normalizedLanguage = preferredLanguageCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let languageCode: String
        if normalizedLanguage.isEmpty || normalizedLanguage == "auto" {
            languageCode = "auto"
        } else if whisper_lang_id(normalizedLanguage) >= 0 {
            languageCode = normalizedLanguage
        } else {
            languageCode = "auto"
        }
        let maxThreads = min(8, max(ProcessInfo.processInfo.processorCount - 2, 1))

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_realtime = false
        params.print_progress = false
        params.print_timestamps = false
        params.print_special = false
        params.translate = false
        params.n_threads = Int32(maxThreads)
        params.offset_ms = 0
        params.no_context = true
        params.single_segment = true
        params.no_timestamps = true
        let prompt = initialPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        let promptOrNil = (prompt?.isEmpty == false) ? prompt : nil

        func runWhisper(
            languagePointer: UnsafePointer<CChar>?,
            detectLanguage: Bool,
            promptPointer: UnsafePointer<CChar>?
        ) -> Int32 {
            params.language = languagePointer
            params.detect_language = detectLanguage
            params.initial_prompt = promptPointer
            whisper_reset_timings(context)
            return samples.withUnsafeBufferPointer { bufferPointer in
                whisper_full(context, params, bufferPointer.baseAddress, Int32(bufferPointer.count))
            }
        }

        let runStatus: Int32
        if let promptOrNil {
            runStatus = promptOrNil.withCString { cPrompt in
                if languageCode == "auto" {
                    return runWhisper(
                        languagePointer: nil,
                        detectLanguage: true,
                        promptPointer: cPrompt
                    )
                }
                return languageCode.withCString { cLanguage in
                    runWhisper(
                        languagePointer: cLanguage,
                        detectLanguage: false,
                        promptPointer: cPrompt
                    )
                }
            }
        } else if languageCode == "auto" {
            runStatus = runWhisper(
                languagePointer: nil,
                detectLanguage: true,
                promptPointer: nil
            )
        } else {
            runStatus = languageCode.withCString { cLanguage in
                runWhisper(
                    languagePointer: cLanguage,
                    detectLanguage: false,
                    promptPointer: nil
                )
            }
        }

        guard runStatus == 0 else {
            throw WhisperGGMLCoreMLError.inferenceFailed
        }

        func collectText() -> String {
            let segmentCount = Int(whisper_full_n_segments(context))
            var parts: [String] = []
            parts.reserveCapacity(segmentCount)

            for index in 0..<segmentCount {
                if let segment = whisper_full_get_segment_text(context, Int32(index)) {
                    let text = String(cString: segment).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        parts.append(text)
                    }
                }
            }

            return parts.joined(separator: " ")
        }

        func detectedLanguageCode() -> String {
            let languageID = whisper_full_lang_id(context)
            guard languageID >= 0, let cLanguage = whisper_lang_str(languageID) else {
                return "unknown"
            }
            return String(cString: cLanguage)
        }

        var detectedLanguage = detectedLanguageCode()
        var finalText = collectText()
        let looksLikePromptLeak = promptOrNil.map { Self.isLikelyPromptLeak(text: finalText, prompt: $0) } ?? false

        // If output is empty or looks like the instruction prompt itself,
        // rerun once without initial prompt.
        if (finalText.isEmpty || looksLikePromptLeak), promptOrNil != nil {
            let fallbackStatus: Int32
            if languageCode == "auto" {
                fallbackStatus = runWhisper(
                    languagePointer: nil,
                    detectLanguage: true,
                    promptPointer: nil
                )
            } else {
                fallbackStatus = languageCode.withCString { cLanguage in
                    runWhisper(
                        languagePointer: cLanguage,
                        detectLanguage: false,
                        promptPointer: nil
                    )
                }
            }

            if fallbackStatus == 0 {
                detectedLanguage = detectedLanguageCode()
                finalText = collectText()
            }
        }

        // Some chunks still yield empty output in auto mode; retry once with detected language.
        if finalText.isEmpty, languageCode == "auto", whisper_lang_id(detectedLanguage) >= 0 {
            let fallbackStatus = detectedLanguage.withCString { cLanguage in
                runWhisper(
                    languagePointer: cLanguage,
                    detectLanguage: false,
                    promptPointer: nil
                )
            }
            if fallbackStatus == 0 {
                detectedLanguage = detectedLanguageCode()
                finalText = collectText()
            }
        }

        return WhisperTranscriptionResult(languageID: detectedLanguage, text: finalText)
    }

    private func warmupInferenceIfNeeded(context: OpaquePointer) throws {
        guard !didWarmupInference else {
            return
        }

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_realtime = false
        params.print_progress = false
        params.print_timestamps = false
        params.print_special = false
        params.translate = false
        params.n_threads = 1
        params.offset_ms = 0
        params.no_context = true
        params.single_segment = true
        params.no_timestamps = true
        params.detect_language = true
        params.language = nil
        params.initial_prompt = nil

        // Prime model backends (CoreML/Metal/decoder graph) before first user tap.
        let warmupSamples = Array(repeating: Float.zero, count: Int(Constants.targetSampleRate))
        let status = warmupSamples.withUnsafeBufferPointer { bufferPointer in
            whisper_full(context, params, bufferPointer.baseAddress, Int32(bufferPointer.count))
        }

        guard status == 0 else {
            throw WhisperGGMLCoreMLError.inferenceFailed
        }

        whisper_reset_timings(context)
        didWarmupInference = true
    }

    private static func isLikelyPromptLeak(text: String, prompt: String) -> Bool {
        let normalizedText = text.lowercased()
        let normalizedPrompt = prompt.lowercased()

        if normalizedText.isEmpty {
            return false
        }

        let signaturePhrases = [
            "verbatim transcript",
            "verbatim",
            "speakers switch between languages",
            "transcribe exactly what is spoken",
            "do not translate",
            "context:"
        ]

        if signaturePhrases.contains(where: { normalizedText.contains($0) }) {
            return true
        }

        let separators = CharacterSet.alphanumerics.inverted
        let textWords = normalizedText
            .components(separatedBy: separators)
            .filter { $0.count >= 3 }
        guard textWords.count >= 3 else {
            return false
        }

        let promptWordSet = Set(
            normalizedPrompt
                .components(separatedBy: separators)
                .filter { $0.count >= 3 }
        )
        guard !promptWordSet.isEmpty else {
            return false
        }

        let overlap = textWords.reduce(0) { count, word in
            count + (promptWordSet.contains(word) ? 1 : 0)
        }
        let ratio = Double(overlap) / Double(textWords.count)
        return ratio >= 0.5
    }

    private func ensureContext() async throws -> OpaquePointer {
        let modelURL = try await ensureModelFile()
        let shouldUseGPUPath = isCoreMLEncoderEnabled()

        if let context, activeModelPath == modelURL.path {
            return context
        }

        if let context {
            whisper_free(context)
            self.context = nil
        }

        if shouldUseGPUPath,
           !shouldForceCPUContext,
           let created = makeContext(modelURL: modelURL, useGPU: true) {
            self.context = created
            self.activeModelPath = modelURL.path
            self.didWarmupInference = false
            return created
        }

        guard let fallback = makeContext(modelURL: modelURL, useGPU: false) else {
            throw WhisperGGMLCoreMLError.contextInitializationFailed
        }

        shouldForceCPUContext = true
        self.context = fallback
        self.activeModelPath = modelURL.path
        self.didWarmupInference = false
        return fallback
    }

    private func makeContext(modelURL: URL, useGPU: Bool) -> OpaquePointer? {
        var params = whisper_context_default_params()
#if targetEnvironment(simulator)
        params.use_gpu = false
        params.flash_attn = false
#else
        params.use_gpu = useGPU
        params.flash_attn = useGPU
#endif
        return whisper_init_from_file_with_params(modelURL.path, params)
    }

    private func ensureModelFile() async throws -> URL {
        let coreMLEncoderEnabled = isCoreMLEncoderEnabled()
        if coreMLEncoderEnabled,
           let bundled = bundledModelFileURL(),
           isValidModelFile(at: bundled) {
            return bundled
        }

        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)

        let cachedModelURL = rootDirectory.appendingPathComponent(Constants.modelFileName)
        if !coreMLEncoderEnabled {
            try removeCachedCoreMLEncoderIfPresent()
        }

        if !isValidModelFile(at: cachedModelURL) {
            if let bundled = bundledModelFileURL(), isValidModelFile(at: bundled) {
                try materializeCachedModel(from: bundled, to: cachedModelURL)
            } else {
                guard let remoteURL = URL(string: Constants.modelDownloadURL) else {
                    throw WhisperGGMLCoreMLError.modelUnavailable
                }

                let (temporaryURL, response) = try await URLSession.shared.download(from: remoteURL)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    throw WhisperGGMLCoreMLError.downloadFailed
                }

                if fileManager.fileExists(atPath: cachedModelURL.path) {
                    try? fileManager.removeItem(at: cachedModelURL)
                }
                try fileManager.moveItem(at: temporaryURL, to: cachedModelURL)
            }

            guard isValidModelFile(at: cachedModelURL) else {
                throw WhisperGGMLCoreMLError.modelUnavailable
            }
        }

        if coreMLEncoderEnabled, let bundledEncoder = bundledEncoderDirectoryURL() {
            let targetEncoder = rootDirectory.appendingPathComponent(Constants.encoderDirectoryName, isDirectory: true)
            if !hasRequiredCoreMLFiles(at: targetEncoder) {
                try fileManager.createDirectory(at: targetEncoder, withIntermediateDirectories: true)
                try copyCoreMLDirectory(from: bundledEncoder, to: targetEncoder)
            }
        }

        return cachedModelURL
    }

    private func isCoreMLEncoderEnabled() -> Bool {
        guard let rawValue = ProcessInfo.processInfo.environment[Constants.coreMLEncoderEnvKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        else {
            return Constants.coreMLEncoderEnabledByDefault
        }

        switch rawValue {
        case "1", "true", "yes", "on":
            return true
        case "0", "false", "no", "off":
            return false
        default:
            return Constants.coreMLEncoderEnabledByDefault
        }
    }

    private func removeCachedCoreMLEncoderIfPresent() throws {
        let encoderURL = rootDirectory.appendingPathComponent(Constants.encoderDirectoryName, isDirectory: true)
        guard fileManager.fileExists(atPath: encoderURL.path) else {
            return
        }
        try fileManager.removeItem(at: encoderURL)
    }

    private func materializeCachedModel(from source: URL, to destination: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }

    private func bundledModelFileURL() -> URL? {
        for subdirectory in Constants.bundledSubdirectories {
            if let direct = Bundle.main.resourceURL?
                .appendingPathComponent(subdirectory, isDirectory: true)
                .appendingPathComponent(Constants.modelFileName),
               fileManager.fileExists(atPath: direct.path) {
                return direct
            }
        }

        if let direct = Bundle.main.resourceURL?.appendingPathComponent(Constants.modelFileName),
           fileManager.fileExists(atPath: direct.path) {
            return direct
        }

        for subdirectory in Constants.bundledSubdirectories {
            if let named = Bundle.main.url(
                forResource: Constants.modelName,
                withExtension: "bin",
                subdirectory: subdirectory
            ), fileManager.fileExists(atPath: named.path) {
                return named
            }
        }

        return Bundle.main.url(forResource: Constants.modelName, withExtension: "bin")
    }

    private func isValidModelFile(at url: URL) -> Bool {
        guard fileManager.fileExists(atPath: url.path) else {
            return false
        }
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = values.fileSize else {
            return false
        }
        return Int64(fileSize) >= Constants.minimumModelSizeBytes
    }

    private func bundledEncoderDirectoryURL() -> URL? {
        for subdirectory in Constants.bundledSubdirectories {
            if let direct = Bundle.main.resourceURL?
                .appendingPathComponent(subdirectory, isDirectory: true)
                .appendingPathComponent(Constants.encoderDirectoryName, isDirectory: true),
               hasRequiredCoreMLFiles(at: direct) {
                return direct
            }
        }

        if let direct = Bundle.main.resourceURL?
            .appendingPathComponent(Constants.encoderDirectoryName, isDirectory: true),
           hasRequiredCoreMLFiles(at: direct) {
            return direct
        }

        for subdirectory in Constants.bundledSubdirectories {
            if let named = Bundle.main.url(
                forResource: Constants.encoderModelName,
                withExtension: "mlmodelc",
                subdirectory: subdirectory
            ), hasRequiredCoreMLFiles(at: named) {
                return named
            }
        }

        if let named = Bundle.main.url(
            forResource: Constants.encoderModelName,
            withExtension: "mlmodelc"
        ), hasRequiredCoreMLFiles(at: named) {
            return named
        }

        return nil
    }

    private func copyCoreMLDirectory(from source: URL, to destination: URL) throws {
        let sourcePaths = [
            "coremldata.bin",
            "metadata.json",
            "model.mil",
            "weights/weight.bin",
            "analytics/coremldata.bin"
        ]

        for relativePath in sourcePaths {
            let sourceURL = source.appendingPathComponent(relativePath)
            let destinationURL = destination.appendingPathComponent(relativePath)
            let parent = destinationURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)

            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }
    }

    private func hasRequiredCoreMLFiles(at directory: URL) -> Bool {
        let required = [
            "coremldata.bin",
            "metadata.json",
            "model.mil",
            "weights/weight.bin",
            "analytics/coremldata.bin"
        ]

        return required.allSatisfy { relativePath in
            fileManager.fileExists(atPath: directory.appendingPathComponent(relativePath).path)
        }
    }

    private static func loadSamples(
        from audioURL: URL,
        startOffset: Double,
        endOffset: Double
    ) throws -> [Float] {
        let file = try AVAudioFile(
            forReading: audioURL,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let format = file.processingFormat
        let sampleRate = format.sampleRate

        let totalFrames = file.length
        let startFrame = max(0, min(totalFrames, AVAudioFramePosition(startOffset * sampleRate)))
        let endFrame = max(startFrame, min(totalFrames, AVAudioFramePosition(endOffset * sampleRate)))
        let frameCount = AVAudioFrameCount(endFrame - startFrame)

        guard frameCount > 0 else {
            return []
        }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return []
        }

        file.framePosition = startFrame
        try file.read(into: buffer, frameCount: frameCount)

        let mono = monoSamples(from: buffer)
        return resampleTo16k(samples: mono, sourceSampleRate: sampleRate)
    }

    private static func monoSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)

        guard frameLength > 0, channelCount > 0 else {
            return []
        }

        guard let channelData = buffer.floatChannelData else {
            return []
        }

        var mono = Array(repeating: Float.zero, count: frameLength)
        let scale = Float(1.0 / Double(channelCount))

        for channel in 0..<channelCount {
            let samples = channelData[channel]
            for index in 0..<frameLength {
                mono[index] += samples[index] * scale
            }
        }

        return mono
    }

    private static func resampleTo16k(samples: [Float], sourceSampleRate: Double) -> [Float] {
        guard !samples.isEmpty, sourceSampleRate > 0 else {
            return []
        }

        let ratio = sourceSampleRate / Constants.targetSampleRate
        if abs(ratio - 1) < 0.0001 {
            return samples
        }

        let targetCount = Int(Double(samples.count) / ratio)
        guard targetCount > 0 else {
            return []
        }

        var output = Array(repeating: Float.zero, count: targetCount)
        for targetIndex in 0..<targetCount {
            let sourcePosition = Double(targetIndex) * ratio
            let lower = Int(sourcePosition.rounded(.down))
            let upper = min(lower + 1, samples.count - 1)
            let fraction = Float(sourcePosition - Double(lower))

            if lower == upper {
                output[targetIndex] = samples[lower]
            } else {
                output[targetIndex] = samples[lower] + (samples[upper] - samples[lower]) * fraction
            }
        }

        return output
    }
}
