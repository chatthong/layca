import Foundation
import CoreML

enum SpeakerDiarizationCoreMLError: LocalizedError {
    case invalidRemoteURL
    case invalidResponse
    case missingOutput(String)

    var errorDescription: String? {
        switch self {
        case .invalidRemoteURL:
            return "Speaker diarization model URL is invalid."
        case .invalidResponse:
            return "Speaker diarization model download failed."
        case .missingOutput(let name):
            return "Speaker diarization model output '\(name)' is missing."
        }
    }
}

actor SpeakerDiarizationCoreMLService {
    private struct Constants {
        static let modelDirectoryName = "wespeaker_v2.mlmodelc"
        static let modelName = "wespeaker_v2"
        static let bundledSubdirectories = ["Models/RuntimeAssets", "Models"]
        static let sampleRate: Double = 16_000
        static let inputSamples = 160_000
        static let waveformBatch = 3
        static let maskLength = 589
        static let minSamplesForInference = 24_000

        static let requiredFiles = [
            "coremldata.bin",
            "metadata.json",
            "model.mil",
            "weights/weight.bin",
            "analytics/coremldata.bin"
        ]
    }

    private let fileManager: FileManager
    private let rootDirectory: URL
    private var model: MLModel?

    init(fileManager: FileManager = .default, rootDirectory: URL? = nil) {
        self.fileManager = fileManager

        if let rootDirectory {
            self.rootDirectory = rootDirectory
        } else {
            let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            self.rootDirectory = caches.appendingPathComponent("SpeakerDiarization", isDirectory: true)
        }
    }

    func prepareIfNeeded() async throws {
        if model != nil {
            return
        }

        let modelURL = try await ensureModelDirectory()
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        model = try MLModel(contentsOf: modelURL, configuration: configuration)
    }

    func reset() {
        // Stateless model; API kept for lifecycle symmetry with other pipeline services.
    }

    func embedding(for samples: [Float], sampleRate: Double) throws -> [Float]? {
        guard let model else {
            return nil
        }

        let converted = Self.resampleTo16k(samples: samples, sourceSampleRate: sampleRate)
        let trimmed = Self.trimSilenceEdges(converted, threshold: 0.003)
        guard trimmed.count >= Constants.minSamplesForInference else {
            return nil
        }

        let fixedInput = Self.fitToInputLength(trimmed, targetCount: Constants.inputSamples)

        let waveform = try MLMultiArray(
            shape: [
                NSNumber(value: Constants.waveformBatch),
                NSNumber(value: Constants.inputSamples)
            ],
            dataType: .float32
        )
        fillBatch(waveform, with: fixedInput)

        let mask = try MLMultiArray(
            shape: [
                NSNumber(value: Constants.waveformBatch),
                NSNumber(value: Constants.maskLength)
            ],
            dataType: .float32
        )
        fillMask(mask, validRatio: min(Double(trimmed.count) / Double(Constants.inputSamples), 1.0))

        let input = try MLDictionaryFeatureProvider(dictionary: [
            "waveform": waveform,
            "mask": mask
        ])

        let output = try model.prediction(from: input)
        guard let embeddingMatrix = output.featureValue(for: "embedding")?.multiArrayValue else {
            throw SpeakerDiarizationCoreMLError.missingOutput("embedding")
        }

        let vector = extractFirstRow(from: embeddingMatrix)
        return Self.normalize(vector)
    }

    private func ensureModelDirectory() async throws -> URL {
        if let bundled = bundledModelDirectory() {
            return bundled
        }

        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let modelDirectory = rootDirectory.appendingPathComponent(Constants.modelDirectoryName, isDirectory: true)

        if hasAllRequiredFiles(at: modelDirectory) {
            return modelDirectory
        }

        if fileManager.fileExists(atPath: modelDirectory.path) {
            try fileManager.removeItem(at: modelDirectory)
        }
        try fileManager.createDirectory(at: modelDirectory, withIntermediateDirectories: true)

        for relativePath in Constants.requiredFiles {
            let destinationURL = modelDirectory.appendingPathComponent(relativePath)
            let parent = destinationURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)

            let encodedPath = "\(Constants.modelDirectoryName)/\(relativePath)"
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "\(Constants.modelDirectoryName)/\(relativePath)"
            let remoteURLString = "https://huggingface.co/FluidInference/speaker-diarization-coreml/resolve/main/\(encodedPath)?download=true"

            guard let remoteURL = URL(string: remoteURLString) else {
                throw SpeakerDiarizationCoreMLError.invalidRemoteURL
            }

            let (data, response) = try await URLSession.shared.data(from: remoteURL)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw SpeakerDiarizationCoreMLError.invalidResponse
            }

            try data.write(to: destinationURL, options: .atomic)
        }

        return modelDirectory
    }

    private func bundledModelDirectory() -> URL? {
        for subdirectory in Constants.bundledSubdirectories {
            if let directURL = Bundle.main.resourceURL?
                .appendingPathComponent(subdirectory, isDirectory: true)
                .appendingPathComponent(Constants.modelDirectoryName, isDirectory: true),
               hasAllRequiredFiles(at: directURL) {
                return directURL
            }
        }

        let directURL = Bundle.main.resourceURL?
            .appendingPathComponent(Constants.modelDirectoryName, isDirectory: true)
        if let directURL, hasAllRequiredFiles(at: directURL) {
            return directURL
        }

        for subdirectory in Constants.bundledSubdirectories {
            if let namedURL = Bundle.main.url(
                forResource: Constants.modelName,
                withExtension: "mlmodelc",
                subdirectory: subdirectory
            ), hasAllRequiredFiles(at: namedURL) {
                return namedURL
            }
        }

        if let namedURL = Bundle.main.url(
            forResource: Constants.modelName,
            withExtension: "mlmodelc"
        ), hasAllRequiredFiles(at: namedURL) {
            return namedURL
        }

        return nil
    }

    private func hasAllRequiredFiles(at directory: URL) -> Bool {
        Constants.requiredFiles.allSatisfy { relativePath in
            fileManager.fileExists(atPath: directory.appendingPathComponent(relativePath).path)
        }
    }

    private func fillBatch(_ array: MLMultiArray, with values: [Float]) {
        if array.dataType == .float32 {
            let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: array.count)
            let rowSize = Constants.inputSamples
            for row in 0..<Constants.waveformBatch {
                let base = row * rowSize
                for index in 0..<rowSize {
                    pointer[base + index] = values[index]
                }
            }
            return
        }

        for row in 0..<Constants.waveformBatch {
            for index in 0..<Constants.inputSamples {
                array[row * Constants.inputSamples + index] = NSNumber(value: values[index])
            }
        }
    }

    private func fillMask(_ array: MLMultiArray, validRatio: Double) {
        let activeCount = max(1, Int((Double(Constants.maskLength) * validRatio).rounded(.toNearestOrAwayFromZero)))

        if array.dataType == .float32 {
            let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: array.count)
            let rowSize = Constants.maskLength
            for row in 0..<Constants.waveformBatch {
                let base = row * rowSize
                for index in 0..<rowSize {
                    pointer[base + index] = index < activeCount ? 1 : 0
                }
            }
            return
        }

        for row in 0..<Constants.waveformBatch {
            for index in 0..<Constants.maskLength {
                array[row * Constants.maskLength + index] = index < activeCount ? 1 : 0
            }
        }
    }

    private func extractFirstRow(from matrix: MLMultiArray) -> [Float] {
        let vectorLength = 256
        var output = Array(repeating: Float.zero, count: vectorLength)

        if matrix.dataType == .float32 {
            let pointer = matrix.dataPointer.bindMemory(to: Float.self, capacity: matrix.count)
            for index in 0..<vectorLength where index < matrix.count {
                output[index] = pointer[index]
            }
            return output
        }

        for index in 0..<vectorLength where index < matrix.count {
            output[index] = matrix[index].floatValue
        }

        return output
    }

    private static func fitToInputLength(_ samples: [Float], targetCount: Int) -> [Float] {
        guard !samples.isEmpty else {
            return Array(repeating: 0, count: targetCount)
        }

        if samples.count == targetCount {
            return samples
        }

        if samples.count > targetCount {
            let start = max((samples.count - targetCount) / 2, 0)
            let end = min(start + targetCount, samples.count)
            return Array(samples[start..<end])
        }

        var output = Array(repeating: Float.zero, count: targetCount)
        output.replaceSubrange(0..<samples.count, with: samples)
        return output
    }

    private static func trimSilenceEdges(_ samples: [Float], threshold: Float) -> [Float] {
        guard !samples.isEmpty else {
            return samples
        }

        var start = 0
        while start < samples.count && abs(samples[start]) < threshold {
            start += 1
        }

        var end = samples.count - 1
        while end >= start && abs(samples[end]) < threshold {
            end -= 1
        }

        if start >= samples.count || end < start {
            return []
        }

        return Array(samples[start...end])
    }

    private static func normalize(_ vector: [Float]) -> [Float] {
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

    private static func resampleTo16k(samples: [Float], sourceSampleRate: Double) -> [Float] {
        guard !samples.isEmpty, sourceSampleRate > 0 else {
            return []
        }

        if abs(sourceSampleRate - Constants.sampleRate) < 0.5 {
            return samples
        }

        let ratio = Constants.sampleRate / sourceSampleRate
        let outputCount = max(Int((Double(samples.count) * ratio).rounded(.down)), 1)
        var output = Array(repeating: Float.zero, count: outputCount)

        for index in 0..<outputCount {
            let sourcePosition = Double(index) / ratio
            let leftIndex = Int(sourcePosition.rounded(.down))
            let rightIndex = min(leftIndex + 1, samples.count - 1)
            let fraction = Float(sourcePosition - Double(leftIndex))
            let left = samples[min(max(leftIndex, 0), samples.count - 1)]
            let right = samples[rightIndex]
            output[index] = left + ((right - left) * fraction)
        }

        return output
    }
}
