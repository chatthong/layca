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
}
