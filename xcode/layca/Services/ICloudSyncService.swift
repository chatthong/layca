import Foundation

enum ICloudSyncStatus: Equatable {
    case idle(lastSynced: Date?)
    case syncing
    case error(String)
    case unavailable
}

actor ICloudSyncService {
    static let containerID = "iCloud.com.cropbinary.layca"

    // MARK: - Dependencies
    private let fileManager: FileManager
    private weak var sessionStore: SessionStore?

    // MARK: - State
    private var metadataQuery: NSMetadataQuery?
    private var debounceTask: Task<Void, Never>?
    private(set) var status: ICloudSyncStatus = .idle(lastSynced: nil)
    var onStatusChange: ((ICloudSyncStatus) -> Void)?

    init(fileManager: FileManager = .default, sessionStore: SessionStore) {
        self.fileManager = fileManager
        self.sessionStore = sessionStore
    }

    // MARK: - Container URL

    /// Returns the iCloud Documents/Sessions URL, or nil if iCloud is unavailable.
    var containerSessionsURL: URL? {
        guard fileManager.ubiquityIdentityToken != nil else { return nil }
        guard let container = fileManager.url(
            forUbiquityContainerIdentifier: Self.containerID
        ) else { return nil }
        let url = container
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("Sessions", isDirectory: true)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// True when iCloud Drive is accessible on this device.
    var isAvailable: Bool {
        fileManager.ubiquityIdentityToken != nil &&
        fileManager.url(forUbiquityContainerIdentifier: Self.containerID) != nil
    }

    // MARK: - Push

    /// Copies local session files to the iCloud container.
    func push(sessionID: UUID, localDirectory: URL, includeAudio: Bool) async {
        guard let iCloudSessions = containerSessionsURL else {
            setStatus(.unavailable)
            return
        }

        setStatus(.syncing)
        let iCloudDir = iCloudSessions.appendingPathComponent(sessionID.uuidString, isDirectory: true)

        do {
            try fileManager.createDirectory(at: iCloudDir, withIntermediateDirectories: true)

            let filesToCopy = ["session.json", "segments.json"]
                + (includeAudio ? ["session_full.m4a"] : [])

            let coordinator = NSFileCoordinator()
            var coordinatorError: NSError?

            for fileName in filesToCopy {
                let source = localDirectory.appendingPathComponent(fileName)
                let destination = iCloudDir.appendingPathComponent(fileName)
                guard fileManager.fileExists(atPath: source.path) else { continue }

                coordinator.coordinate(
                    writingItemAt: destination,
                    options: .forReplacing,
                    error: &coordinatorError
                ) { dest in
                    try? fileManager.removeItem(at: dest)
                    try? fileManager.copyItem(at: source, to: dest)
                }

                if let err = coordinatorError { throw err }
            }

            setStatus(.idle(lastSynced: Date()))
        } catch {
            setStatus(.error(error.localizedDescription))
        }
    }

    /// Call after any session mutation. Waits 3s then pushes.
    func schedulePush(sessionID: UUID, localDirectory: URL, includeAudio: Bool) {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            await push(sessionID: sessionID, localDirectory: localDirectory, includeAudio: includeAudio)
        }
    }

    // MARK: - Helpers

    private func setStatus(_ newStatus: ICloudSyncStatus) {
        status = newStatus
        onStatusChange?(newStatus)
    }
}
