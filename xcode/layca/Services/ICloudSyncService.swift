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

    // MARK: - Merge Types (lightweight Codable mirrors)

    private struct SyncSessionMeta: Codable {
        let id: UUID
        var title: String
        var updatedAt: Date?
        var speakers: [String: SyncSpeakerProfile]?
        var durationSeconds: Double?
        var status: String?
    }

    private struct SyncSpeakerProfile: Codable {
        let label: String
        let colorHex: String
        let avatarSymbol: String
    }

    private struct SyncSegment: Codable {
        let id: UUID?
        var text: String
        var speaker: String
        var speakerID: String
        var updatedAt: Date?
        var time: String?
        var language: String
        var avatarSymbol: String?
        var avatarColorHex: String?
        var startOffset: Double?
        var endOffset: Double?
    }

    // MARK: - Merge Helpers

    private func mergeSegments(local: [SyncSegment], remote: [SyncSegment]) -> [SyncSegment] {
        var merged: [UUID: SyncSegment] = [:]
        for seg in local  { if let id = seg.id { merged[id] = seg } }
        for seg in remote {
            guard let id = seg.id else { continue }
            if let existing = merged[id] {
                let localDate = existing.updatedAt ?? .distantPast
                let remoteDate = seg.updatedAt ?? .distantPast
                if remoteDate >= localDate { merged[id] = seg }
            } else {
                merged[id] = seg
            }
        }
        let localIDs = local.compactMap(\.id)
        let remoteOnlyIDs = remote.compactMap(\.id).filter { !localIDs.contains($0) }
        let orderedIDs = localIDs + remoteOnlyIDs
        return orderedIDs.compactMap { merged[$0] }
    }

    private func mergeMetadata(local: SyncSessionMeta, remote: SyncSessionMeta) -> SyncSessionMeta {
        let localDate = local.updatedAt ?? .distantPast
        let remoteDate = remote.updatedAt ?? .distantPast
        return remoteDate > localDate ? remote : local
    }

    // MARK: - Pull

    func pull(sessionID: UUID, localDirectory: URL) async {
        guard let iCloudSessions = containerSessionsURL else { return }
        let iCloudDir = iCloudSessions.appendingPathComponent(sessionID.uuidString, isDirectory: true)
        guard fileManager.fileExists(atPath: iCloudDir.path) else { return }

        setStatus(.syncing)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        do {
            let localMetaURL  = localDirectory.appendingPathComponent("session.json")
            let remoteMetaURL = iCloudDir.appendingPathComponent("session.json")

            if fileManager.fileExists(atPath: localMetaURL.path),
               fileManager.fileExists(atPath: remoteMetaURL.path) {
                let coordinator = NSFileCoordinator()
                var coordError: NSError?
                coordinator.coordinate(
                    readingItemAt: remoteMetaURL, options: .withoutChanges,
                    writingItemAt: localMetaURL,  options: .forReplacing,
                    error: &coordError
                ) { remoteSrc, localDest in
                    guard let localData  = try? Data(contentsOf: localDest),
                          let remoteData = try? Data(contentsOf: remoteSrc),
                          let localMeta  = try? decoder.decode(SyncSessionMeta.self, from: localData),
                          let remoteMeta = try? decoder.decode(SyncSessionMeta.self, from: remoteData)
                    else { return }
                    let merged = mergeMetadata(local: localMeta, remote: remoteMeta)
                    if let out = try? encoder.encode(merged) {
                        try? out.write(to: localDest, options: .atomic)
                        try? out.write(to: remoteSrc, options: .atomic)
                    }
                }
                if let err = coordError { throw err }
            }

            let localSegsURL  = localDirectory.appendingPathComponent("segments.json")
            let remoteSegsURL = iCloudDir.appendingPathComponent("segments.json")

            if fileManager.fileExists(atPath: localSegsURL.path),
               fileManager.fileExists(atPath: remoteSegsURL.path) {
                let coordinator = NSFileCoordinator()
                var coordError: NSError?
                coordinator.coordinate(
                    readingItemAt: remoteSegsURL, options: .withoutChanges,
                    writingItemAt: localSegsURL,  options: .forReplacing,
                    error: &coordError
                ) { remoteSrc, localDest in
                    guard let localData   = try? Data(contentsOf: localDest),
                          let remoteData  = try? Data(contentsOf: remoteSrc),
                          let localSegs   = try? decoder.decode([SyncSegment].self, from: localData),
                          let remoteSegs  = try? decoder.decode([SyncSegment].self, from: remoteData)
                    else { return }
                    let merged = mergeSegments(local: localSegs, remote: remoteSegs)
                    if let out = try? encoder.encode(merged) {
                        try? out.write(to: localDest, options: .atomic)
                        try? out.write(to: remoteSrc, options: .atomic)
                    }
                }
                if let err = coordError { throw err }
            }

            setStatus(.idle(lastSynced: Date()))
        } catch {
            setStatus(.error(error.localizedDescription))
        }
    }

    // MARK: - Monitoring

    func startMonitoring(localSessionsDirectory: URL, includeAudio: Bool) {
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K LIKE '*.json'", NSMetadataItemFSNameKey)
        self.metadataQuery = query

        NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: query,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            Task {
                await self.handleQueryUpdate(
                    notification: notification,
                    localSessionsDirectory: localSessionsDirectory,
                    includeAudio: includeAudio
                )
            }
        }

        Task { @MainActor in
            query.start()
        }
    }

    func stopMonitoring() {
        guard let query = metadataQuery else { return }
        Task { @MainActor in
            query.stop()
        }
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidUpdate, object: query)
        metadataQuery = nil
    }

    private func handleQueryUpdate(
        notification: Notification,
        localSessionsDirectory: URL,
        includeAudio: Bool
    ) async {
        guard let items = notification.userInfo?[NSMetadataQueryUpdateChangedItemsKey]
                as? [NSMetadataItem] else { return }

        for item in items {
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            let url = URL(fileURLWithPath: path)
            let components = url.pathComponents
            guard let sessionsIdx = components.firstIndex(of: "Sessions"),
                  components.indices.contains(sessionsIdx + 1),
                  let sessionID = UUID(uuidString: components[sessionsIdx + 1]) else { continue }

            let localDir = localSessionsDirectory.appendingPathComponent(sessionID.uuidString, isDirectory: true)
            await pull(sessionID: sessionID, localDirectory: localDir)
        }
    }

    func syncAll(localSessionsDirectory: URL, includeAudio: Bool) async {
        guard isAvailable else {
            setStatus(.unavailable)
            return
        }
        setStatus(.syncing)
        let contents = (try? fileManager.contentsOfDirectory(
            at: localSessionsDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        for url in contents {
            guard let sessionID = UUID(uuidString: url.lastPathComponent) else { continue }
            await push(sessionID: sessionID, localDirectory: url, includeAudio: includeAudio)
        }
        setStatus(.idle(lastSynced: Date()))
    }

    // MARK: - Helpers

    private func setStatus(_ newStatus: ICloudSyncStatus) {
        status = newStatus
        onStatusChange?(newStatus)
    }
}
