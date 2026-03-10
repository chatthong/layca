import Combine
import Foundation
import SwiftUI

// MARK: - Download State

enum WhisperModelDownloadState: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded
    case active
}

// MARK: - Download Delegate

private final class ModelDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {

    private let destination: URL
    private let minimumBytes: Int64
    private let onProgress: (Double) -> Void
    private let onComplete: (Result<Void, Error>) -> Void
    private var finished = false

    init(destination: URL, minimumBytes: Int64,
         onProgress: @escaping (Double) -> Void,
         onComplete: @escaping (Result<Void, Error>) -> Void) {
        self.destination = destination
        self.minimumBytes = minimumBytes
        self.onProgress = onProgress
        self.onComplete = onComplete
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData _: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let effectiveTotal = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : minimumBytes
        let progress = min(Double(totalBytesWritten) / Double(effectiveTotal), 0.99)
        onProgress(progress)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard !finished else { return }
        finished = true
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: location.path)
            let size = attrs[.size] as? Int64 ?? 0
            guard size >= minimumBytes else {
                throw URLError(.cannotDecodeContentData)
            }
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            onComplete(.success(()))
        } catch {
            onComplete(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !finished, let error else { return }
        finished = true
        onComplete(.failure(error))
    }
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
        autoActivateIfOnlyOne()
    }

    /// True if any profile has a downloaded or active model on disk.
    var hasAnyDownloadedModel: Bool {
        states.values.contains { $0 == .downloaded || $0 == .active }
    }

    /// Downloads the model binary using a native URLSessionDownloadTask for full speed.
    func download(profile: WhisperModelProfile) {
        guard downloadTasks[profile] == nil else { return }
        downloadErrors[profile] = nil
        states[profile] = .downloading(progress: 0)

        downloadTasks[profile] = Task { [weak self] in
            guard let self else { return }
            do {
                try service.prepareCacheDirectory()

                guard let remoteURL = service.remoteDownloadURL(for: profile) else {
                    states[profile] = .notDownloaded
                    downloadErrors[profile] = "No download URL configured for this model."
                    downloadTasks[profile] = nil
                    return
                }

                let (destination, minimumBytes) = service.cacheDestination(for: profile)

                var request = URLRequest(url: remoteURL)
                request.setValue(
                    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                    forHTTPHeaderField: "User-Agent")
                request.setValue("*/*", forHTTPHeaderField: "Accept")

                try await withNativeDownload(request: request, destination: destination,
                                             minimumBytes: minimumBytes, profile: profile)

                states[profile] = .downloaded
                downloadTasks[profile] = nil
                autoActivateIfOnlyOne()

            } catch {
                let isCancelled = error is CancellationError
                    || (error as? URLError)?.code == .cancelled
                states[profile] = .notDownloaded
                if !isCancelled {
                    downloadErrors[profile] = error.localizedDescription
                }
                downloadTasks[profile] = nil
            }
        }
    }

    /// Cancels an in-flight download and resets state to notDownloaded.
    func cancel(profile: WhisperModelProfile) {
        downloadTasks[profile]?.cancel()
        states[profile] = .notDownloaded
        downloadErrors[profile] = nil
    }

    /// Deletes the cached model file from disk and resets state to notDownloaded.
    func delete(profile: WhisperModelProfile) {
        guard downloadTasks[profile] == nil else { return }
        let (destination, _) = service.cacheDestination(for: profile)
        try? FileManager.default.removeItem(at: destination)
        states[profile] = .notDownloaded
        downloadErrors[profile] = nil
        autoActivateIfOnlyOne()
    }

    /// Marks a profile as the active model. Demotes any previously active profile to downloaded.
    func markActive(_ profile: WhisperModelProfile) {
        for p in WhisperModelProfile.allCases where states[p] == .active {
            states[p] = .downloaded
        }
        states[profile] = .active
    }

    // MARK: - Private

    /// If exactly one model is on disk and none are active yet, mark it active automatically.
    private func autoActivateIfOnlyOne() {
        let hasActive = states.values.contains { $0 == .active }
        guard !hasActive else { return }
        let downloaded = states.filter { $0.value == .downloaded }
        guard downloaded.count == 1, let profile = downloaded.keys.first else { return }
        states[profile] = .active
    }

    private func withNativeDownload(request: URLRequest, destination: URL,
                                    minimumBytes: Int64, profile: WhisperModelProfile) async throws {
        // Wrap URLSessionDownloadTask in async/await with proper cancellation support.
        let sessionBox = SessionBox()

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let delegate = ModelDownloadDelegate(
                    destination: destination,
                    minimumBytes: minimumBytes,
                    onProgress: { [weak self] progress in
                        Task { @MainActor [weak self] in
                            self?.states[profile] = .downloading(progress: progress)
                        }
                    },
                    onComplete: { result in
                        continuation.resume(with: result)
                    }
                )
                let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
                sessionBox.session = session
                session.downloadTask(with: request).resume()
            }
        } onCancel: {
            sessionBox.session?.invalidateAndCancel()
        }
    }
}

// MARK: - Helpers

/// Sendable reference box so the cancellation handler can reach the session.
private final class SessionBox: @unchecked Sendable {
    var session: URLSession?
}
