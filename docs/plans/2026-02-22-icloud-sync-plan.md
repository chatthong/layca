# iCloud Sync Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Sync Layca sessions (transcripts + optional audio) across Apple devices via iCloud Drive, with per-row last-write-wins merge.

**Architecture:** New `ICloudSyncService` actor owns all iCloud logic. `SessionStore` (local `Documents/Sessions/`) stays the source of truth. Sync mirrors to `iCloud~com~cropbinary~layca/Documents/Sessions/`. `NSMetadataQuery` watches for remote changes.

**Tech Stack:** `FileManager` ubiquitous container, `NSFileCoordinator`, `NSMetadataQuery`, `Foundation`, no CloudKit, no third-party packages.

---

## Pre-requisite: Xcode Manual Setup (do this before any code)

> This cannot be automated. Do it once in Xcode.

1. Open `xcode/layca.xcodeproj` in Xcode
2. Select the `layca` target → **Signing & Capabilities**
3. Click **+ Capability** → add **iCloud**
4. Under iCloud: check **iCloud Documents** (NOT CloudKit)
5. Set container to `iCloud.com.cropbinary.layca`
6. Xcode auto-creates `layca.entitlements` with the correct keys
7. Verify `layca.entitlements` now contains:
   ```xml
   <key>com.apple.developer.icloud-container-identifiers</key>
   <array><string>iCloud.com.cropbinary.layca</string></array>
   <key>com.apple.developer.ubiquity-container-identifiers</key>
   <array><string>iCloud.com.cropbinary.layca</string></array>
   ```

---

## Task 1: Add iCloud keys to macOS entitlements

**Files:**
- Modify: `xcode/layca/layca-macos.entitlements`

**Step 1: Add the two iCloud keys**

Open `xcode/layca/layca-macos.entitlements`. Add after the existing keys:

```xml
<key>com.apple.developer.icloud-container-identifiers</key>
<array>
    <string>iCloud.com.cropbinary.layca</string>
</array>
<key>com.apple.developer.ubiquity-container-identifiers</key>
<array>
    <string>iCloud.com.cropbinary.layca</string>
</array>
```

Final file should look like:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.device.audio-input</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-only</key>
    <true/>
    <key>com.apple.developer.icloud-container-identifiers</key>
    <array>
        <string>iCloud.com.cropbinary.layca</string>
    </array>
    <key>com.apple.developer.ubiquity-container-identifiers</key>
    <array>
        <string>iCloud.com.cropbinary.layca</string>
    </array>
</dict>
</plist>
```

**Step 2: Commit**
```bash
git add xcode/layca/layca-macos.entitlements
git commit -m "feat: add iCloud container entitlements for macOS"
```

---

## Task 2: Add `updatedAt` to `TranscriptRow` and `SegmentSnapshot`

**Files:**
- Modify: `xcode/layca/Models/Domain/TranscriptRow.swift`
- Modify: `xcode/layca/App/AppBackend.swift` (`SegmentSnapshot` struct at line ~1540)

**Step 1: Add `updatedAt` to `TranscriptRow`**

In `TranscriptRow.swift`, add `var updatedAt: Date` after `endOffset`:

```swift
struct TranscriptRow: Identifiable {
    let id: UUID
    let speakerID: String
    let speaker: String
    var text: String          // change let → var (needed for text edits)
    let time: String
    let language: String
    let avatarSymbol: String
    let avatarPaletteIndex: Int
    let startOffset: Double?
    let endOffset: Double?
    var updatedAt: Date       // ← add this
    // ...
}
```

Update the `init` to include `updatedAt: Date = Date()` with a default:

```swift
nonisolated init(
    id: UUID = UUID(),
    speakerID: String,
    speaker: String,
    text: String,
    time: String,
    language: String,
    avatarSymbol: String,
    avatarPaletteIndex: Int,
    startOffset: Double?,
    endOffset: Double?,
    updatedAt: Date = Date()   // ← add, default = now
) {
    // ... existing assignments ...
    self.updatedAt = updatedAt
}
```

**Step 2: Add `updatedAt` to `SegmentSnapshot`**

In `AppBackend.swift`, find `SegmentSnapshot` (~line 1540). Add `updatedAt`:

```swift
private struct SegmentSnapshot: Codable {
    let id: UUID?
    let speakerID: String
    let speaker: String
    let text: String
    let time: String?
    let language: String
    let avatarSymbol: String?
    let avatarColorHex: String?
    let startOffset: Double?
    let endOffset: Double?
    let updatedAt: Date?      // ← add, optional for backward compat
}
```

**Step 3: Update `persistSegmentsSnapshot` to encode `updatedAt`**

Find `persistSegmentsSnapshot` (~line 2205). In the `SegmentSnapshot` initializer inside the map, add:

```swift
SegmentSnapshot(
    id: row.id,
    speakerID: row.speakerID,
    speaker: row.speaker,
    text: row.text,
    time: row.time,
    language: row.language,
    avatarSymbol: row.avatarSymbol,
    avatarColorHex: session.speakers[row.speakerID]?.colorHex,
    startOffset: row.startOffset,
    endOffset: row.endOffset,
    updatedAt: row.updatedAt   // ← add
)
```

**Step 4: Update the segment-loading path to decode `updatedAt`**

Find where `SegmentSnapshot` is decoded back into `TranscriptRow` (search for `SegmentSnapshot` usage in `loadSession`). Pass through `updatedAt`:

```swift
TranscriptRow(
    id: snapshot.id ?? UUID(),
    speakerID: snapshot.speakerID,
    speaker: snapshot.speaker,
    text: snapshot.text,
    time: snapshot.time ?? "00:00:00",
    language: snapshot.language,
    avatarSymbol: snapshot.avatarSymbol ?? "person.fill",
    avatarPaletteIndex: paletteIndex,
    startOffset: snapshot.startOffset,
    endOffset: snapshot.endOffset,
    updatedAt: snapshot.updatedAt ?? .distantPast  // ← add, .distantPast = always loses merge
)
```

**Step 5: Bump `updatedAt` on text/speaker edits**

In `SessionStore.updateTranscriptRow(...)` and `SessionStore.updateSpeakerName(...)`, after mutating the row, set `row.updatedAt = Date()`. Both functions exist around lines 1776–1867.

**Step 6: Build to confirm no compile errors**

In Xcode: Product → Build (⌘B). Fix any call sites that don't compile due to the `text: let → var` change (there should be none since it was already assignable through the store).

**Step 7: Commit**
```bash
git add xcode/layca/Models/Domain/TranscriptRow.swift xcode/layca/App/AppBackend.swift
git commit -m "feat: add updatedAt to TranscriptRow and SegmentSnapshot for sync merge"
```

---

## Task 3: Add `updatedAt` to `SessionMetadataSnapshot` and `StoredSession`

**Files:**
- Modify: `xcode/layca/App/AppBackend.swift`

**Step 1: Add `updatedAt` to `StoredSession`**

Find `private struct StoredSession` (~line 1507). Add:

```swift
private struct StoredSession {
    let id: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date       // ← add
    var rows: [TranscriptRow]
    var speakers: [String: SpeakerProfile]
    // ... rest unchanged
}
```

**Step 2: Add `updatedAt` to `SessionMetadataSnapshot`**

Find `private struct SessionMetadataSnapshot: Codable` (~line 1527). Add:

```swift
private struct SessionMetadataSnapshot: Codable {
    let schemaVersion: Int
    let id: UUID
    let title: String
    let createdAt: Date
    let updatedAt: Date?      // ← add, optional for backward compat
    let languageHints: [String]
    // ... rest unchanged
}
```

**Step 3: Update `persistSessionMetadata` to encode `updatedAt`**

Find `persistSessionMetadata` (~line 2180). In the `SessionMetadataSnapshot` initializer, add `updatedAt: session.updatedAt`.

**Step 4: Update session-loading to decode `updatedAt`**

Find where `SessionMetadataSnapshot` is decoded (in `loadSession`). Pass `updatedAt` when constructing `StoredSession`:

```swift
StoredSession(
    id: ...,
    title: ...,
    createdAt: ...,
    updatedAt: metadata?.updatedAt ?? .distantPast,  // ← add
    // ...
)
```

**Step 5: Bump `updatedAt` on all mutation functions**

In `SessionStore`, add `session.updatedAt = Date()` in these functions before calling `persistSessionMetadata`:
- `renameSession(sessionID:title:)`
- `updateSessionConfig(sessionID:languageHints:)`
- `updateStatus(sessionID:status:)`
- `updateSpeakerName(sessionID:speakerID:newName:)` (also bumps `updatedAt` on affected rows)
- `appendRow(sessionID:row:event:)` — already bumps row `updatedAt`, also bump session

**Step 6: Fix `createSession` initializer call sites**

`StoredSession` now has an `updatedAt` field — add `updatedAt: Date()` to the `createSession` initializer in `SessionStore`.

**Step 7: Build (⌘B) — fix any remaining compile errors**

**Step 8: Commit**
```bash
git add xcode/layca/App/AppBackend.swift
git commit -m "feat: add updatedAt to StoredSession and SessionMetadataSnapshot"
```

---

## Task 4: Create `ICloudSyncService` — skeleton + container URL

**Files:**
- Create: `xcode/layca/Services/ICloudSyncService.swift`

**Step 1: Create the Services directory and file**

```bash
mkdir -p xcode/layca/Services
```

Create `ICloudSyncService.swift`:

```swift
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
```

**Step 2: Add to Xcode project**

In Xcode, right-click `xcode/layca/Services/` folder → Add Files → select `ICloudSyncService.swift`. Make sure the `layca` target is checked.

**Step 3: Build (⌘B)**

**Step 4: Commit**
```bash
git add xcode/layca/Services/ICloudSyncService.swift
git commit -m "feat: add ICloudSyncService skeleton with container URL"
```

---

## Task 5: `ICloudSyncService` — push local → iCloud

**Files:**
- Modify: `xcode/layca/Services/ICloudSyncService.swift`

**Step 1: Add push method**

Add to `ICloudSyncService`:

```swift
/// Copies local session files to the iCloud container.
/// - Parameters:
///   - sessionID: The session UUID.
///   - localDirectory: Local `Documents/Sessions/{UUID}/` URL.
///   - includeAudio: Whether to also copy `session_full.m4a`.
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

// MARK: - Debounced push

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
```

**Step 2: Build (⌘B)**

**Step 3: Commit**
```bash
git add xcode/layca/Services/ICloudSyncService.swift
git commit -m "feat: ICloudSyncService push local→iCloud with debounce"
```

---

## Task 6: `ICloudSyncService` — pull + merge (iCloud → local)

**Files:**
- Modify: `xcode/layca/Services/ICloudSyncService.swift`

**Step 1: Add merge structs**

Add lightweight Codable mirrors used only for merge (avoids coupling to private `AppBackend` types):

```swift
// Lightweight decode-only mirrors for merge. Must stay in sync with
// SessionMetadataSnapshot and SegmentSnapshot in AppBackend.swift.
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
    // Passthrough fields (not merged, just preserved)
    var time: String?
    var language: String
    var avatarSymbol: String?
    var avatarColorHex: String?
    var startOffset: Double?
    var endOffset: Double?
}
```

**Step 2: Add merge helpers**

```swift
/// Merges two arrays of segments using per-row last-write-wins by updatedAt.
/// Rows in remote but not local are added. Remote row wins on tie.
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
            merged[id] = seg  // new row from remote
        }
    }
    // Preserve original local order, append remote-only rows at end
    let localIDs = local.compactMap(\.id)
    let remoteOnlyIDs = remote.compactMap(\.id).filter { !localIDs.contains($0) }
    let orderedIDs = localIDs + remoteOnlyIDs
    return orderedIDs.compactMap { merged[$0] }
}

/// Returns the metadata snapshot that was updated more recently.
private func mergeMetadata(local: SyncSessionMeta, remote: SyncSessionMeta) -> SyncSessionMeta {
    let localDate = local.updatedAt ?? .distantPast
    let remoteDate = remote.updatedAt ?? .distantPast
    return remoteDate > localDate ? remote : local
}
```

**Step 3: Add pull method**

```swift
/// Reads remote session from iCloud, merges with local file, writes merged result to both.
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
        // --- Merge session.json ---
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

        // --- Merge segments.json ---
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
```

**Step 4: Build (⌘B)**

**Step 5: Commit**
```bash
git add xcode/layca/Services/ICloudSyncService.swift
git commit -m "feat: ICloudSyncService pull+merge with per-row last-write-wins"
```

---

## Task 7: `ICloudSyncService` — `NSMetadataQuery` monitoring

**Files:**
- Modify: `xcode/layca/Services/ICloudSyncService.swift`

**Step 1: Add `startMonitoring` / `stopMonitoring`**

`NSMetadataQuery` requires being started on the main thread. Bridge with `@MainActor`:

```swift
/// Start watching the iCloud container for remote changes.
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
        // Extract session UUID from path: .../Sessions/{UUID}/session.json
        let components = url.pathComponents
        guard let sessionsIdx = components.firstIndex(of: "Sessions"),
              components.indices.contains(sessionsIdx + 1),
              let sessionID = UUID(uuidString: components[sessionsIdx + 1]) else { continue }

        let localDir = localSessionsDirectory.appendingPathComponent(sessionID.uuidString, isDirectory: true)
        await pull(sessionID: sessionID, localDirectory: localDir)
    }
}

/// Full sync: upload all local sessions to iCloud on first enable.
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
```

**Step 2: Build (⌘B)**

**Step 3: Commit**
```bash
git add xcode/layca/Services/ICloudSyncService.swift
git commit -m "feat: ICloudSyncService NSMetadataQuery monitoring and syncAll"
```

---

## Task 8: `AppBackend` — sync status enum + published properties

**Files:**
- Modify: `xcode/layca/App/AppBackend.swift`

**Step 1: Add `isAudioSyncEnabled` to `AppSettingsStore`**

Find `AppSettingsStore` struct (near line 2260). Add:

```swift
var isAudioSyncEnabled: Bool   // ← after isICloudSyncEnabled
```

Add to `CodingKeys`, `init`, `init(from:)`, and `encode(to:)` — follow the exact same pattern as `isICloudSyncEnabled`.

**Step 2: Add `@Published var isAudioSyncEnabled` to `AppBackend`**

Near line 2447 where `isICloudSyncEnabled` is declared, add:

```swift
@Published var isAudioSyncEnabled = false {
    didSet { persistSettingsIfNeeded() }
}
```

**Step 3: Add `@Published var iCloudSyncStatus`**

```swift
@Published var iCloudSyncStatus: ICloudSyncStatus = .idle(lastSynced: nil)
```

**Step 4: Wire `isAudioSyncEnabled` through settings load/save**

In `loadPersistedSettings()` (~line 3894): add `isAudioSyncEnabled = persisted.isAudioSyncEnabled`
In the settings snapshot builder: add `isAudioSyncEnabled: isAudioSyncEnabled`

**Step 5: Build (⌘B)**

**Step 6: Commit**
```bash
git add xcode/layca/App/AppBackend.swift
git commit -m "feat: AppBackend iCloudSyncStatus and isAudioSyncEnabled properties"
```

---

## Task 9: `AppBackend` — wire `ICloudSyncService` into session lifecycle

**Files:**
- Modify: `xcode/layca/App/AppBackend.swift`

**Step 1: Add `ICloudSyncService` instance**

Near line 2487 where `sessionStore` is declared, add:

```swift
private let syncService: ICloudSyncService
```

Initialize it in `AppBackend.init()` (or via lazy init):

```swift
syncService = ICloudSyncService(sessionStore: sessionStore)
syncService.onStatusChange = { [weak self] status in
    Task { @MainActor in
        self?.iCloudSyncStatus = status
    }
}
```

**Step 2: Replace the empty iCloud hook with a real push call**

Find the empty stub (~line 3819):
```swift
if isICloudSyncEnabled {
    Task.detached {
        try? await Task.sleep(nanoseconds: 120_000_000)
    }
}
```

Replace with a helper method call. Add this private method to `AppBackend`:

```swift
private func scheduleSyncIfEnabled(sessionID: UUID) {
    guard isICloudSyncEnabled else { return }
    guard let localDir = sessionStore.sessionDirectory(for: sessionID) else { return }
    Task {
        await syncService.schedulePush(
            sessionID: sessionID,
            localDirectory: localDir,
            includeAudio: isAudioSyncEnabled
        )
    }
}
```

You'll need to add `func sessionDirectory(for:) -> URL?` to `SessionStore`:
```swift
func sessionDirectory(for sessionID: UUID) -> URL? {
    guard sessions[sessionID] != nil else { return nil }
    return sessionsDirectory.appendingPathComponent(sessionID.uuidString, isDirectory: true)
}
```

**Step 3: Call `scheduleSyncIfEnabled` after session writes**

In `AppBackend`, search for every call to `sessionStore.appendRow`, `sessionStore.updateTranscriptRow`, `sessionStore.updateSpeakerName`, `sessionStore.renameSession`, `sessionStore.updateSessionConfig`. After each, call:

```swift
scheduleSyncIfEnabled(sessionID: sessionID)
```

**Step 4: Wire `isICloudSyncEnabled` didSet to enable/disable monitoring**

```swift
@Published var isICloudSyncEnabled = true {
    didSet {
        persistSettingsIfNeeded()
        if isICloudSyncEnabled {
            Task {
                let localSessionsDir = await sessionStore.sessionsDirectoryURL()
                await syncService.syncAll(
                    localSessionsDirectory: localSessionsDir,
                    includeAudio: isAudioSyncEnabled
                )
                await syncService.startMonitoring(
                    localSessionsDirectory: localSessionsDir,
                    includeAudio: isAudioSyncEnabled
                )
            }
        } else {
            Task { await syncService.stopMonitoring() }
        }
    }
}
```

Add `func sessionsDirectoryURL() -> URL` to `SessionStore`:
```swift
func sessionsDirectoryURL() -> URL { sessionsDirectory }
```

**Step 5: Start monitoring on app launch if sync enabled**

In `AppBackend.loadPersistedSettings()` or after app init, add:

```swift
if isICloudSyncEnabled {
    Task {
        let localDir = await sessionStore.sessionsDirectoryURL()
        await syncService.startMonitoring(
            localSessionsDirectory: localDir,
            includeAudio: isAudioSyncEnabled
        )
    }
}
```

**Step 6: Build (⌘B) — fix any remaining compile errors**

**Step 7: Commit**
```bash
git add xcode/layca/App/AppBackend.swift
git commit -m "feat: wire ICloudSyncService into AppBackend session lifecycle"
```

---

## Task 10: Settings UI — audio toggle + sync status section

**Files:**
- Modify: `xcode/layca/Features/Share/SettingsSheetFlowView.swift`

**Step 1: Update `SettingsCloudAndPurchasesStepView` binding signature**

Find the struct at line 648. Update its properties:

```swift
private struct SettingsCloudAndPurchasesStepView: View {
    @Binding var isICloudSyncEnabled: Bool
    @Binding var isAudioSyncEnabled: Bool       // ← add
    let iCloudSyncStatus: ICloudSyncStatus       // ← add
    let isRestoringPurchases: Bool
    let restoreStatusMessage: String?
    let onRestorePurchases: () -> Void
    let onSyncNow: () -> Void                    // ← add
    // ...
}
```

**Step 2: Update the body**

Replace the `iCloud` section:

```swift
Section("iCloud") {
    Toggle("Sync sessions via iCloud", isOn: $isICloudSyncEnabled)

    if isICloudSyncEnabled {
        Toggle(isOn: $isAudioSyncEnabled) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Include audio files")
                Text("Each session can be 50–150 MB")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 16)
    }
}

if isICloudSyncEnabled {
    Section("Sync Status") {
        HStack {
            switch iCloudSyncStatus {
            case .idle(let lastSynced):
                if let date = lastSynced {
                    Text("Last synced: \(date.formatted(.relative(presentation: .named)))")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not yet synced")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Sync Now", action: onSyncNow)
                    .buttonStyle(.borderless)
            case .syncing:
                ProgressView()
                    .controlSize(.small)
                Text("Syncing…")
                    .foregroundStyle(.secondary)
            case .error(let msg):
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                Text(msg)
                    .foregroundStyle(.red)
                    .font(.caption)
            case .unavailable:
                Image(systemName: "icloud.slash")
                    .foregroundStyle(.secondary)
                Text("iCloud not available")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
```

**Step 3: Update all call sites of `SettingsCloudAndPurchasesStepView`**

Search for `SettingsCloudAndPurchasesStepView(` and add the new parameters:
- `isAudioSyncEnabled: isAudioSyncEnabledBinding` (add a binding computed var in the parent view, same pattern as `iCloudSyncBinding`)
- `iCloudSyncStatus: backend.iCloudSyncStatus`
- `onSyncNow: { Task { await backend.syncNow() } }`

**Step 4: Add `syncNow()` to `AppBackend`**

```swift
func syncNow() async {
    guard isICloudSyncEnabled else { return }
    let localDir = await sessionStore.sessionsDirectoryURL()
    await syncService.syncAll(localSessionsDirectory: localDir, includeAudio: isAudioSyncEnabled)
}
```

**Step 5: Build (⌘B)**

**Step 6: Commit**
```bash
git add xcode/layca/Features/Share/SettingsSheetFlowView.swift xcode/layca/App/AppBackend.swift
git commit -m "feat: iCloud sync UI — audio toggle and sync status section"
```

---

## Task 11: Manual smoke test checklist

> No automated tests for iCloud behavior (requires real devices). Test on two physical Apple devices signed into the same Apple ID.

**Test A — Basic metadata sync:**
1. Device A: Record a 30-second session. Verify transcript appears.
2. Device B: Wait ~30s. Verify session appears with correct title and transcript rows.

**Test B — Transcript edit sync:**
1. Device A: Long-press a transcript bubble → edit text → confirm.
2. Device B: Wait ~30s. Verify edited text appears.

**Test C — Speaker rename sync:**
1. Device A: Long-press a bubble → rename speaker "A" → "Alice".
2. Device B: Wait ~30s. Verify all "A" bubbles show "Alice".

**Test D — Conflict merge:**
1. Enable airplane mode on both devices.
2. Device A: Edit bubble text to "Hello from A".
3. Device B: Edit same bubble to "Hello from B".
4. Re-enable network on both.
5. Wait ~60s. Verify whichever device re-enabled network last "wins" — no crash.

**Test E — Audio sync:**
1. Enable "Include audio files" on Device A.
2. Record session. Wait for sync.
3. Device B: Tap a transcript bubble. Verify audio plays from iCloud-synced M4A.

**Test F — Toggle off:**
1. Disable "Sync sessions via iCloud". Verify status section disappears. Verify no more background sync calls (check console for `[iCloudSync]` logs).

---

## Files Changed Summary

| Action | File |
|---|---|
| Modify | `xcode/layca/layca-macos.entitlements` |
| Modify | `xcode/layca/Models/Domain/TranscriptRow.swift` |
| Modify | `xcode/layca/App/AppBackend.swift` |
| Create | `xcode/layca/Services/ICloudSyncService.swift` |
| Modify | `xcode/layca/Features/Share/SettingsSheetFlowView.swift` |
| Manual | Xcode Signing & Capabilities → iCloud Documents |
