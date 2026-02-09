import Foundation
import CoreML

enum SileroVADCoreMLError: LocalizedError {
    case invalidRemoteURL
    case invalidResponse
    case missingOutput(String)
    case invalidInputShape

    var errorDescription: String? {
        switch self {
        case .invalidRemoteURL:
            return "Silero VAD model URL is invalid."
        case .invalidResponse:
            return "Silero VAD model download failed."
        case .missingOutput(let name):
            return "Silero VAD model output '\(name)' is missing."
        case .invalidInputShape:
            return "Silero VAD input tensor shape is invalid."
        }
    }
}

actor SileroVADCoreMLService {
    private struct Constants {
        static let modelDirectoryName = "silero-vad-unified-256ms-v6.0.0.mlmodelc"
        static let sampleRate: Double = 16_000
        static let windowSamples = 4_160
        static let hopSamples = 512
        static let stateSize = 128
        static let maxBufferedSamples = 24_000

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
    private var audioBuffer: [Float] = []
    private var hiddenState: MLMultiArray?
    private var cellState: MLMultiArray?

    init(fileManager: FileManager = .default, rootDirectory: URL? = nil) {
        self.fileManager = fileManager

        if let rootDirectory {
            self.rootDirectory = rootDirectory
        } else {
            let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            self.rootDirectory = caches.appendingPathComponent("SileroVAD", isDirectory: true)
        }
    }

    func prepareIfNeeded() async throws {
        if model != nil {
            try resetRuntimeState()
            return
        }

        let modelURL = try await ensureModelDirectory()
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all

        model = try MLModel(contentsOf: modelURL, configuration: configuration)
        try resetRuntimeState()
    }

    func reset() {
        audioBuffer.removeAll(keepingCapacity: true)

        if let hiddenState {
            zeroOut(hiddenState)
        }
        if let cellState {
            zeroOut(cellState)
        }
    }

    func ingest(samples: [Float], sampleRate: Double) throws -> Float? {
        guard model != nil else {
            return nil
        }

        let converted = Self.resampleTo16k(samples: samples, sourceSampleRate: sampleRate)
        guard !converted.isEmpty else {
            return nil
        }

        audioBuffer.append(contentsOf: converted)

        var latestProbability: Float?
        while audioBuffer.count >= Constants.windowSamples {
            let window = Array(audioBuffer.prefix(Constants.windowSamples))
            latestProbability = try predict(window: window)

            let drop = min(Constants.hopSamples, audioBuffer.count)
            audioBuffer.removeFirst(drop)
        }

        if audioBuffer.count > Constants.maxBufferedSamples {
            audioBuffer.removeFirst(audioBuffer.count - Constants.maxBufferedSamples)
        }

        return latestProbability
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
            let remoteURLString = "https://huggingface.co/FluidInference/silero-vad-coreml/resolve/main/\(encodedPath)?download=true"

            guard let remoteURL = URL(string: remoteURLString) else {
                throw SileroVADCoreMLError.invalidRemoteURL
            }

            let (data, response) = try await URLSession.shared.data(from: remoteURL)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw SileroVADCoreMLError.invalidResponse
            }

            try data.write(to: destinationURL, options: .atomic)
        }

        return modelDirectory
    }

    private func bundledModelDirectory() -> URL? {
        let directURL = Bundle.main.resourceURL?
            .appendingPathComponent(Constants.modelDirectoryName, isDirectory: true)

        if let directURL, hasAllRequiredFiles(at: directURL) {
            return directURL
        }

        if let namedURL = Bundle.main.url(
            forResource: "silero-vad-unified-256ms-v6.0.0",
            withExtension: "mlmodelc"
        ), hasAllRequiredFiles(at: namedURL) {
            return namedURL
        }

        return nil
    }

    private func hasAllRequiredFiles(at directory: URL) -> Bool {
        Constants.requiredFiles.allSatisfy { relativePath in
            let path = directory.appendingPathComponent(relativePath).path
            return fileManager.fileExists(atPath: path)
        }
    }

    private func resetRuntimeState() throws {
        audioBuffer.removeAll(keepingCapacity: true)

        hiddenState = try makeZeroStateArray(size: Constants.stateSize)
        cellState = try makeZeroStateArray(size: Constants.stateSize)
    }

    private func predict(window: [Float]) throws -> Float {
        guard window.count == Constants.windowSamples else {
            throw SileroVADCoreMLError.invalidInputShape
        }
        guard let model, let hiddenState, let cellState else {
            return 0
        }

        let audioInput = try MLMultiArray(
            shape: [1, NSNumber(value: Constants.windowSamples)],
            dataType: .float32
        )
        fill(audioInput, with: window)

        let input = try MLDictionaryFeatureProvider(dictionary: [
            "audio_input": audioInput,
            "hidden_state": hiddenState,
            "cell_state": cellState
        ])

        let output = try model.prediction(from: input)

        guard let vadOutput = output.featureValue(for: "vad_output")?.multiArrayValue else {
            throw SileroVADCoreMLError.missingOutput("vad_output")
        }
        guard let newHidden = output.featureValue(for: "new_hidden_state")?.multiArrayValue else {
            throw SileroVADCoreMLError.missingOutput("new_hidden_state")
        }
        guard let newCell = output.featureValue(for: "new_cell_state")?.multiArrayValue else {
            throw SileroVADCoreMLError.missingOutput("new_cell_state")
        }

        self.hiddenState = newHidden
        self.cellState = newCell

        return value(at: 0, from: vadOutput)
    }

    private func makeZeroStateArray(size: Int) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: [1, NSNumber(value: size)], dataType: .float32)
        zeroOut(array)
        return array
    }

    private func fill(_ array: MLMultiArray, with values: [Float]) {
        let count = min(array.count, values.count)
        if array.dataType == .float32 {
            let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: array.count)
            for index in 0..<count {
                pointer[index] = values[index]
            }
            if count < array.count {
                for index in count..<array.count {
                    pointer[index] = 0
                }
            }
        } else {
            for index in 0..<count {
                array[index] = NSNumber(value: values[index])
            }
            if count < array.count {
                for index in count..<array.count {
                    array[index] = 0
                }
            }
        }
    }

    private func zeroOut(_ array: MLMultiArray) {
        if array.dataType == .float32 {
            let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: array.count)
            for index in 0..<array.count {
                pointer[index] = 0
            }
        } else {
            for index in 0..<array.count {
                array[index] = 0
            }
        }
    }

    private func value(at index: Int, from array: MLMultiArray) -> Float {
        if array.dataType == .float32 {
            let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: array.count)
            return pointer[min(max(index, 0), max(array.count - 1, 0))]
        }
        return array[min(max(index, 0), max(array.count - 1, 0))].floatValue
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
