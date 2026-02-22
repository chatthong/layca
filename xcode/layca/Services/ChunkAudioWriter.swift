import AVFoundation

enum ChunkAudioWriterError: Error {
    case invalidSampleRate(Double)
    case emptySamples
    case failedToAllocatePCMBuffer
    case missingChannelData
}

actor ChunkAudioWriter {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Writes a finalized AAC/M4A chunk file for a transcript row.
    /// The returned URL is `chunksDirectory/chunk-<rowID>.m4a`.
    func write(
        samples: [Float],
        sampleRate: Double,
        rowID: UUID,
        chunksDirectory: URL
    ) async throws -> URL {
        guard sampleRate > 0 else {
            throw ChunkAudioWriterError.invalidSampleRate(sampleRate)
        }
        guard !samples.isEmpty else {
            throw ChunkAudioWriterError.emptySamples
        }

        try fileManager.createDirectory(
            at: chunksDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let url = chunksDirectory.appendingPathComponent(
            "chunk-\(rowID.uuidString).m4a",
            isDirectory: false
        )

        let sourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!

        let fileSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let file = try AVAudioFile(
            forWriting: url,
            settings: fileSettings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: sourceFormat,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else {
            throw ChunkAudioWriterError.failedToAllocatePCMBuffer
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)

        guard let channelData = buffer.floatChannelData else {
            throw ChunkAudioWriterError.missingChannelData
        }

        samples.withUnsafeBufferPointer { source in
            guard let baseAddress = source.baseAddress else { return }
            channelData[0].initialize(from: baseAddress, count: samples.count)
        }

        try file.write(from: buffer)
        return url
    }
}
