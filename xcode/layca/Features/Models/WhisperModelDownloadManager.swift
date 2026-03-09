import Foundation
import SwiftUI

// MARK: - Download State

enum WhisperModelDownloadState: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded
    case active
}

// MARK: - Download Manager

@MainActor
final class WhisperModelDownloadManager: ObservableObject {

    @Published private(set) var states: [WhisperModelProfile: WhisperModelDownloadState] = [:]
    @Published private(set) var downloadErrors: [WhisperModelProfile: String] = [:]

    private let service: WhisperGGMLCoreMLService
    private var downloadTasks: [WhisperModelProfile: Task<Void, Never>] = [:]

    init(service: WhisperGGMLCoreMLService) {
        self.service = service
    }

    // MARK: - Public API

    /// Syncs state dict with filesystem. Call on app launch and after downloads.
    func refreshStates(activeProfile: WhisperModelProfile) async {
        for profile in WhisperModelProfile.allCases {
            guard downloadTasks[profile] == nil else { continue }
            let downloaded = service.cachedModelURL(for: profile) != nil
            if profile == activeProfile && downloaded {
                states[profile] = .active
            } else if downloaded {
                states[profile] = .downloaded
            } else {
                states[profile] = .notDownloaded
            }
        }
    }

    /// True if any profile has a downloaded or active model on disk.
    var hasAnyDownloadedModel: Bool {
        states.values.contains { $0 == .downloaded || $0 == .active }
    }

    /// Begins downloading the model binary from HuggingFace with live progress.
    func download(profile: WhisperModelProfile) {
        guard downloadTasks[profile] == nil else { return }
        downloadErrors[profile] = nil
        states[profile] = .downloading(progress: 0)

        downloadTasks[profile] = Task { [weak self] in
            guard let self else { return }
            do {
                try service.prepareCacheDirectory()

                guard let remoteURL = service.remoteDownloadURL(for: profile) else {
                    await MainActor.run {
                        self.states[profile] = .notDownloaded
                        self.downloadErrors[profile] = "No download URL configured for this model."
                        self.downloadTasks[profile] = nil
                    }
                    return
                }

                let (destination, minimumBytes) = service.cacheDestination(for: profile)

                let (asyncBytes, response) = try await URLSession.shared.bytes(from: remoteURL)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }

                let totalBytes = response.expectedContentLength
                let tempURL = destination.deletingLastPathComponent()
                    .appendingPathComponent(destination.lastPathComponent + ".tmp")

                FileManager.default.createFile(atPath: tempURL.path, contents: nil)
                let handle = try FileHandle(forWritingTo: tempURL)
                var receivedBytes: Int64 = 0

                for try await byte in asyncBytes {
                    try handle.write(contentsOf: [byte])
                    receivedBytes += 1
                    if receivedBytes % 65_536 == 0 {
                        let progress = totalBytes > 0 ? Double(receivedBytes) / Double(totalBytes) : 0
                        self.states[profile] = .downloading(progress: progress)
                    }
                    if Task.isCancelled { break }
                }
                try handle.close()

                if Task.isCancelled {
                    try? FileManager.default.removeItem(at: tempURL)
                    self.states[profile] = .notDownloaded
                    self.downloadTasks[profile] = nil
                    return
                }

                let attrs = try FileManager.default.attributesOfItem(atPath: tempURL.path)
                let size = attrs[.size] as? Int64 ?? 0
                guard size >= minimumBytes else {
                    try? FileManager.default.removeItem(at: tempURL)
                    throw URLError(.cannotDecodeContentData)
                }

                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: tempURL, to: destination)

                self.states[profile] = .downloaded
                self.downloadTasks[profile] = nil

            } catch {
                let isCancelled = error is CancellationError
                    || (error as? URLError)?.code == .cancelled
                self.states[profile] = .notDownloaded
                if !isCancelled {
                    self.downloadErrors[profile] = error.localizedDescription
                }
                self.downloadTasks[profile] = nil
            }
        }
    }

    /// Cancels an in-flight download and resets state to notDownloaded.
    func cancel(profile: WhisperModelProfile) {
        downloadTasks[profile]?.cancel()
        downloadTasks[profile] = nil
        states[profile] = .notDownloaded
    }

    /// Marks a profile as the active model. Demotes any previously active profile to downloaded.
    func markActive(_ profile: WhisperModelProfile) {
        for p in WhisperModelProfile.allCases where states[p] == .active {
            states[p] = .downloaded
        }
        states[profile] = .active
    }
}
