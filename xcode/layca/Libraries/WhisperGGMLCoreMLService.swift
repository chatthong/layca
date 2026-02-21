import Foundation
import AVFoundation
import whisper

struct WhisperTranscriptionResult: Sendable {
    let languageID: String
    let languageProbability: Float?
    let languageProbabilities: [String: Float]
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
            return "Invalid message range for Whisper transcription."
        case .modelUnavailable:
            return "Whisper model file is not available."
        case .downloadFailed:
            return "Whisper model download failed."
        case .contextInitializationFailed:
            return "Whisper failed to initialize model context."
        case .noAudioSamples:
            return "No audio samples were found for this message."
        case .inferenceFailed:
            return "Whisper failed while transcribing this message."
        }
    }
}

enum WhisperModelProfile: String, CaseIterable, Codable, Sendable {
    case quick
    case normal
    case pro

    nonisolated var title: String {
        switch self {
        case .quick:
            return "Fast"
        case .normal:
            return "Normal"
        case .pro:
            return "Pro"
        }
    }

    nonisolated var detailText: String {
        switch self {
        case .quick:
            return "Fastest speed, lower accuracy (Q5)."
        case .normal:
            return "Balanced speed and quality (Q8)."
        case .pro:
            return "Best quality, highest load (Turbo)."
        }
    }
}

actor WhisperGGMLCoreMLService {
    private struct ModelAssetSpec {
        let profile: WhisperModelProfile
        let bundledFileNames: [String]
        let cacheFileName: String
        let minimumFileSizeBytes: Int64
        let downloadURL: String?
    }

    private struct Constants {
        static let encoderDirectoryName = "ggml-large-v3-turbo-encoder.mlmodelc"
        static let encoderModelName = "ggml-large-v3-turbo-encoder"
        static let bundledSubdirectories = ["Models/RuntimeAssets", "Models"]
        static let targetSampleRate: Double = 16_000
        static let minimumTurboModelSizeBytes: Int64 = 1_000_000_000
        static let minimumQ8ModelSizeBytes: Int64 = 600_000_000
        static let minimumQ5ModelSizeBytes: Int64 = 350_000_000
        static let coreMLEncoderEnvKey = "LAYCA_ENABLE_WHISPER_COREML_ENCODER"
        static let coreMLEncoderEnabledByDefault = true
        static let forceCoreMLEncoderOnIOSEnvKey = "LAYCA_FORCE_WHISPER_COREML_ENCODER_IOS"
        // Use a practical threshold (about 7.5 GB) so 8 GB-class devices
        // like iPhone 15 Pro/Pro Max are classified correctly.
        static let minimumIOSEncoderMemoryBytes: UInt64 = 7_500_000_000
        static let minimumIOSEncoderCoreCount = 6
        static let ggmlGPUDecodeEnvKey = "LAYCA_ENABLE_WHISPER_GGML_GPU_DECODE"
        static let ggmlGPUDecodeEnabledByDefault = true
        static let lowConfidenceLanguageProbabilityThreshold: Float = 0.5
    }

    private let fileManager: FileManager
    private let rootDirectory: URL
    private var context: OpaquePointer?
    private var activeModelPath: String?
    private var didWarmupInference = false
    private var shouldForceCPUContext = false
    private var coreMLEncoderOverride: Bool?
    private var ggmlGPUDecodeOverride: Bool?
    private var modelProfileOverride: WhisperModelProfile?

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

    func setRuntimePreferences(
        coreMLEncoderEnabled: Bool,
        ggmlGPUDecodeEnabled: Bool,
        modelProfile: WhisperModelProfile
    ) {
        let didChange =
            coreMLEncoderOverride != coreMLEncoderEnabled ||
            ggmlGPUDecodeOverride != ggmlGPUDecodeEnabled ||
            modelProfileOverride != modelProfile

        coreMLEncoderOverride = coreMLEncoderEnabled
        ggmlGPUDecodeOverride = ggmlGPUDecodeEnabled
        modelProfileOverride = modelProfile

        guard didChange else {
            return
        }

        // Settings changed: force a fresh context with the new backend combination.
        shouldForceCPUContext = false
        didWarmupInference = false
        activeModelPath = nil

        if let context {
            whisper_free(context)
            self.context = nil
        }
    }

    func transcribe(
        audioURL: URL,
        startOffset: Double,
        endOffset: Double,
        preferredLanguageCode: String,
        initialPrompt: String?,
        focusLanguageCodes: [String] = []
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
            initialPrompt: initialPrompt,
            focusLanguageCodes: focusLanguageCodes
        )
    }

    func transcribe(
        samples: [Float],
        sourceSampleRate: Double,
        preferredLanguageCode: String,
        initialPrompt: String?,
        focusLanguageCodes: [String] = []
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
            initialPrompt: initialPrompt,
            focusLanguageCodes: focusLanguageCodes
        )
    }

    private func transcribeSamples(
        _ samples: [Float],
        context: OpaquePointer,
        preferredLanguageCode: String,
        initialPrompt: String?,
        focusLanguageCodes: [String]
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
        // For short chunks (≤6 s) single-segment / no-timestamp mode is fast and
        // accurate. For longer chunks, restoring timestamp-conditioned multi-segment
        // decoding prevents greedy attention drift: without timestamp tokens the
        // decoder has no temporal anchor and locks onto the clearest tail phrase,
        // discarding everything before it. collectText() already joins all segments.
        let isLongChunk = samples.count > Int(Constants.targetSampleRate * 6)
        params.single_segment = !isLongChunk
        params.no_timestamps = !isLongChunk
        let prompt = initialPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        let promptOrNil = (prompt?.isEmpty == false) ? prompt : nil
        let normalizedFocusLanguageCodes = Set(
            focusLanguageCodes
                .map { Self.normalizedLanguageCode($0) }
                .filter { !$0.isEmpty && whisper_lang_id($0) >= 0 }
        )

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

        func collectLanguageProbabilities() -> [String: Float] {
            let maxLanguageID = Int(whisper_lang_max_id())
            guard maxLanguageID >= 0 else {
                return [:]
            }

            var probabilities = Array(repeating: Float.zero, count: maxLanguageID + 1)
            let autoDetectResult = probabilities.withUnsafeMutableBufferPointer { bufferPointer in
                whisper_lang_auto_detect(context, 0, Int32(maxThreads), bufferPointer.baseAddress)
            }
            guard autoDetectResult >= 0 else {
                return [:]
            }

            var byLanguageCode: [String: Float] = [:]
            byLanguageCode.reserveCapacity(maxLanguageID + 1)
            for id in 0...maxLanguageID {
                guard let cLanguage = whisper_lang_str(Int32(id)) else {
                    continue
                }
                byLanguageCode[String(cString: cLanguage)] = probabilities[id]
            }
            return byLanguageCode
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

        var languageProbabilities = collectLanguageProbabilities()
        var detectedLanguageProbability = Self.languageProbability(
            for: detectedLanguage,
            in: languageProbabilities
        )
        let isLowConfidenceAutoDetect =
            languageCode == "auto" &&
            (detectedLanguageProbability ?? 0) < Constants.lowConfidenceLanguageProbabilityThreshold
        let focusedLanguageCandidate = Self.highestProbabilityLanguage(
            in: normalizedFocusLanguageCodes,
            from: languageProbabilities
        )
        let focusedLanguageCandidateProbability = focusedLanguageCandidate.flatMap {
            languageProbabilities[$0]
        }

        if isLowConfidenceAutoDetect {
            logLowConfidenceLanguageDetection(
                detectedLanguage: detectedLanguage,
                detectedProbability: detectedLanguageProbability,
                threshold: Constants.lowConfidenceLanguageProbabilityThreshold,
                focusFallbackLanguage: focusedLanguageCandidate,
                focusFallbackProbability: focusedLanguageCandidateProbability
            )
        }

        // If auto-detect is weak, force decode with the strongest focus language.
        if isLowConfidenceAutoDetect,
           let focusedLanguage = focusedLanguageCandidate,
           focusedLanguage != Self.normalizedLanguageCode(detectedLanguage) {
            let previousDetectedLanguage = detectedLanguage
            let previousDetectedLanguageProbability = detectedLanguageProbability
            let focusFallbackStatus = focusedLanguage.withCString { cLanguage in
                runWhisper(
                    languagePointer: cLanguage,
                    detectLanguage: false,
                    promptPointer: nil
                )
            }

            if focusFallbackStatus == 0 {
                let focusedText = collectText()
                if !focusedText.isEmpty {
                    finalText = focusedText
                    detectedLanguage = detectedLanguageCode()
                    let normalizedDetected = Self.normalizedLanguageCode(detectedLanguage)
                    if normalizedDetected.isEmpty || normalizedDetected == "unknown" {
                        detectedLanguage = focusedLanguage
                    }
                }
            }

            languageProbabilities = collectLanguageProbabilities()
            detectedLanguageProbability = Self.languageProbability(
                for: detectedLanguage,
                in: languageProbabilities
            )

            logLowConfidenceFallbackResult(
                previousLanguage: previousDetectedLanguage,
                previousProbability: previousDetectedLanguageProbability,
                newLanguage: detectedLanguage,
                newProbability: detectedLanguageProbability
            )
        }

        return WhisperTranscriptionResult(
            languageID: detectedLanguage,
            languageProbability: detectedLanguageProbability,
            languageProbabilities: languageProbabilities,
            text: finalText
        )
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
        params.detect_language = false
        params.initial_prompt = nil

        // Prime model backends (CoreML/Metal/decoder graph) before first user tap.
        let warmupSamples = Array(repeating: Float.zero, count: Int(Constants.targetSampleRate))
        let status = "en".withCString { cLanguage in
            params.language = cLanguage
            return warmupSamples.withUnsafeBufferPointer { bufferPointer in
                whisper_full(context, params, bufferPointer.baseAddress, Int32(bufferPointer.count))
            }
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

    private static func normalizedLanguageCode(_ languageCode: String) -> String {
        languageCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func languageProbability(
        for languageCode: String,
        in languageProbabilities: [String: Float]
    ) -> Float? {
        let normalizedLanguage = normalizedLanguageCode(languageCode)
        guard !normalizedLanguage.isEmpty else {
            return nil
        }
        return languageProbabilities[normalizedLanguage]
    }

    private static func highestProbabilityLanguage(
        in languageCodes: Set<String>,
        from languageProbabilities: [String: Float]
    ) -> String? {
        languageCodes.max { lhs, rhs in
            let lhsProbability = languageProbabilities[lhs] ?? -1
            let rhsProbability = languageProbabilities[rhs] ?? -1
            return lhsProbability < rhsProbability
        }
    }

    private func ensureContext() async throws -> OpaquePointer {
        let modelProfileConfig = resolvedModelProfileConfiguration()
        let modelURL = try await ensureModelFile(profile: modelProfileConfig.profile)
        let coreMLEncoderConfig = resolvedCoreMLEncoderConfiguration()
        let coreMLEncoderEnabled = coreMLEncoderConfig.enabled
        let shouldUseGPUPath = isGGMLGPUDecodeEnabled()

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
            logAccelerationStatus(
                coreMLEncoderEnabled: coreMLEncoderEnabled,
                ggmlGPUDecodeEnabled: true,
                modelProfile: modelProfileConfig.profile,
                reason: [modelProfileConfig.reason, coreMLEncoderConfig.reason]
                    .compactMap { $0 }
                    .joined(separator: " ")
            )
            return created
        }

        guard let fallback = makeContext(modelURL: modelURL, useGPU: false) else {
            throw WhisperGGMLCoreMLError.contextInitializationFailed
        }

        let wasForcedCPUContext = shouldForceCPUContext
        var fallbackReason: String
        if !shouldUseGPUPath {
            if ggmlGPUDecodeOverride != nil {
                fallbackReason = "ggml GPU decode disabled by user setting."
            } else {
                fallbackReason = "\(Constants.ggmlGPUDecodeEnvKey)=OFF, ggml GPU decode not requested."
            }
        } else if wasForcedCPUContext {
            fallbackReason = "ggml GPU context previously failed in this app run, forced CPU fallback."
        } else {
            fallbackReason = "ggml GPU context init failed on this runtime/device; using CPU fallback."
        }
        if let encoderReason = coreMLEncoderConfig.reason {
            fallbackReason += " \(encoderReason)"
        }
        if let profileReason = modelProfileConfig.reason {
            fallbackReason += " \(profileReason)"
        }

        shouldForceCPUContext = true
        self.context = fallback
        self.activeModelPath = modelURL.path
        self.didWarmupInference = false
        logAccelerationStatus(
            coreMLEncoderEnabled: coreMLEncoderEnabled,
            ggmlGPUDecodeEnabled: false,
            modelProfile: modelProfileConfig.profile,
            reason: fallbackReason
        )
        return fallback
    }

    private func makeContext(modelURL: URL, useGPU: Bool) -> OpaquePointer? {
        var params = whisper_context_default_params()
#if targetEnvironment(simulator)
        params.use_gpu = false
        params.flash_attn = false
#else
        params.use_gpu = useGPU
#if os(iOS)
        // Flash attention has been unstable on iOS hardware for this model size.
        params.flash_attn = false
#else
        params.flash_attn = useGPU
#endif
#endif
        return whisper_init_from_file_with_params(modelURL.path, params)
    }

    private func ensureModelFile(profile: WhisperModelProfile) async throws -> URL {
        let modelSpec = modelSpec(for: profile)
        let coreMLEncoderEnabled = resolvedCoreMLEncoderConfiguration().enabled
        if coreMLEncoderEnabled,
           let bundled = bundledModelFileURL(modelSpec: modelSpec),
           isValidModelFile(at: bundled, minimumFileSizeBytes: modelSpec.minimumFileSizeBytes) {
            return bundled
        }

        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)

        let cachedModelURL = rootDirectory.appendingPathComponent(modelSpec.cacheFileName)
        if !coreMLEncoderEnabled {
            try removeCachedCoreMLEncoderIfPresent()
        }

        if !isValidModelFile(at: cachedModelURL, minimumFileSizeBytes: modelSpec.minimumFileSizeBytes) {
            if let bundled = bundledModelFileURL(modelSpec: modelSpec),
               isValidModelFile(at: bundled, minimumFileSizeBytes: modelSpec.minimumFileSizeBytes) {
                try materializeCachedModel(from: bundled, to: cachedModelURL)
            } else {
                guard let remoteURLString = modelSpec.downloadURL,
                      let remoteURL = URL(string: remoteURLString) else {
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

            guard isValidModelFile(at: cachedModelURL, minimumFileSizeBytes: modelSpec.minimumFileSizeBytes) else {
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

    private func resolvedModelProfileConfiguration() -> (profile: WhisperModelProfile, reason: String?) {
        if let modelProfileOverride {
            return (modelProfileOverride, "Model profile set by user setting (\(modelProfileOverride.title)).")
        }

        return (.pro, nil)
    }

    private func modelSpec(for profile: WhisperModelProfile) -> ModelAssetSpec {
        switch profile {
        case .quick:
            return ModelAssetSpec(
                profile: .quick,
                bundledFileNames: [
                    "ggml-large-v3-turbo-q5_0.bin",
                    "ggml-large-v3-turbo-q5_0"
                ],
                cacheFileName: "ggml-large-v3-turbo-q5_0.bin",
                minimumFileSizeBytes: Constants.minimumQ5ModelSizeBytes,
                downloadURL: nil
            )
        case .normal:
            return ModelAssetSpec(
                profile: .normal,
                bundledFileNames: [
                    "ggml-large-v3-turbo-q8_0.bin",
                    "ggml-large-v3-turbo-q8_0"
                ],
                cacheFileName: "ggml-large-v3-turbo-q8_0.bin",
                minimumFileSizeBytes: Constants.minimumQ8ModelSizeBytes,
                downloadURL: nil
            )
        case .pro:
            return ModelAssetSpec(
                profile: .pro,
                bundledFileNames: ["ggml-large-v3-turbo.bin"],
                cacheFileName: "ggml-large-v3-turbo.bin",
                minimumFileSizeBytes: Constants.minimumTurboModelSizeBytes,
                downloadURL: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin?download=true"
            )
        }
    }

    private func resolvedCoreMLEncoderConfiguration() -> (enabled: Bool, reason: String?) {
        if let coreMLEncoderOverride {
            return (
                coreMLEncoderOverride,
                "CoreML encoder set by user setting (\(coreMLEncoderOverride ? "ON" : "OFF"))."
            )
        }

        let requested = parseBooleanEnv(
            key: Constants.coreMLEncoderEnvKey,
            defaultValue: Constants.coreMLEncoderEnabledByDefault
        )

#if os(iOS) && !targetEnvironment(simulator)
        guard requested else {
            return (false, nil)
        }

        let forceEnableOnIOS = parseBooleanEnv(
            key: Constants.forceCoreMLEncoderOnIOSEnvKey,
            defaultValue: false
        )
        if forceEnableOnIOS {
            return (true, "iOS CoreML encoder forced ON via \(Constants.forceCoreMLEncoderOnIOSEnvKey).")
        }

        let physicalMemoryBytes = ProcessInfo.processInfo.physicalMemory
        let cpuCoreCount = ProcessInfo.processInfo.processorCount
        let memoryGB = Double(physicalMemoryBytes) / 1_073_741_824
        let supportsPerformanceProfile =
            physicalMemoryBytes >= Constants.minimumIOSEncoderMemoryBytes &&
            cpuCoreCount >= Constants.minimumIOSEncoderCoreCount

        if supportsPerformanceProfile {
            return (
                true,
                String(
                    format: "iOS auto-performance profile enabled CoreML encoder (%.1fGB RAM, %d cores).",
                    memoryGB,
                    cpuCoreCount
                )
            )
        }

        return (
            false,
            String(
                format: "iOS auto-safety profile disabled CoreML encoder (%.1fGB RAM, %d cores). Set %@=ON to force.",
                memoryGB,
                cpuCoreCount,
                Constants.forceCoreMLEncoderOnIOSEnvKey
            )
        )
#else
        return (requested, nil)
#endif
    }

    private func isGGMLGPUDecodeEnabled() -> Bool {
        if let ggmlGPUDecodeOverride {
            return ggmlGPUDecodeOverride
        }

        return parseBooleanEnv(
            key: Constants.ggmlGPUDecodeEnvKey,
            defaultValue: Constants.ggmlGPUDecodeEnabledByDefault
        )
    }

    private func parseBooleanEnv(key: String, defaultValue: Bool) -> Bool {
        guard let rawValue = ProcessInfo.processInfo.environment[key]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        else {
            return defaultValue
        }

        switch rawValue {
        case "1", "true", "yes", "on":
            return true
        case "0", "false", "no", "off":
            return false
        default:
            return defaultValue
        }
    }

    private func logAccelerationStatus(
        coreMLEncoderEnabled: Bool,
        ggmlGPUDecodeEnabled: Bool,
        modelProfile: WhisperModelProfile,
        reason: String?
    ) {
        var line = "[Whisper] Model: \(modelProfile.title), CoreML encoder: \(coreMLEncoderEnabled ? "ON" : "OFF"), ggml GPU decode: \(ggmlGPUDecodeEnabled ? "ON" : "OFF")"
        if let reason {
            line += " (\(reason))"
        }
        print(line)
    }

    private func logLowConfidenceLanguageDetection(
        detectedLanguage: String,
        detectedProbability: Float?,
        threshold: Float,
        focusFallbackLanguage: String?,
        focusFallbackProbability: Float?
    ) {
        var line = "[Whisper][Lang] Low-confidence auto-detect: \(detectedLanguage) (p = \(Self.formattedProbability(detectedProbability)), threshold = \(Self.formattedProbability(threshold)))."
        if let focusFallbackLanguage {
            line += " Focus fallback candidate: \(focusFallbackLanguage) (p = \(Self.formattedProbability(focusFallbackProbability)))."
        } else {
            line += " No focus fallback candidate available."
        }
        print(line)
    }

    private func logLowConfidenceFallbackResult(
        previousLanguage: String,
        previousProbability: Float?,
        newLanguage: String,
        newProbability: Float?
    ) {
        print(
            "[Whisper][Lang] Focus fallback rerun result: \(previousLanguage) (p = \(Self.formattedProbability(previousProbability))) -> \(newLanguage) (p = \(Self.formattedProbability(newProbability)))."
        )
    }

    private static func formattedProbability(_ probability: Float?) -> String {
        guard let probability else {
            return "n/a"
        }
        return String(format: "%.6f", probability)
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

    private func bundledModelFileURL(modelSpec: ModelAssetSpec) -> URL? {
        for fileName in modelSpec.bundledFileNames {
            for subdirectory in Constants.bundledSubdirectories {
                if let direct = Bundle.main.resourceURL?
                    .appendingPathComponent(subdirectory, isDirectory: true)
                    .appendingPathComponent(fileName),
                   fileManager.fileExists(atPath: direct.path) {
                    return direct
                }
            }

            if let direct = Bundle.main.resourceURL?.appendingPathComponent(fileName),
               fileManager.fileExists(atPath: direct.path) {
                return direct
            }
        }

        return nil
    }

    private func isValidModelFile(at url: URL, minimumFileSizeBytes: Int64) -> Bool {
        guard fileManager.fileExists(atPath: url.path) else {
            return false
        }
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = values.fileSize else {
            return false
        }
        return Int64(fileSize) >= minimumFileSizeBytes
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
