# iCloud Sync — Design Document

**Date:** 2026-02-22
**Status:** Approved, ready for implementation
**Approach:** iCloud Drive (ubiquitous container) — Approach A

---

## Goals

- Sync transcript sessions across a user's Apple devices (iPhone, iPad, Mac)
- Default: metadata only (`session.json` + `segments.json`)
- Optional: include audio (`session_full.m4a`) — user toggle, default OFF
- Conflict resolution: per-row last-write-wins via `updatedAt` timestamps
- No cloud backend, no CloudKit schema — pure iCloud Drive

---

## Architecture

```
AppBackend
  └── ICloudSyncService (actor)          Services/ICloudSyncService.swift
        ├── NSMetadataQuery              watches for remote device changes
        ├── NSFileCoordinator            safe coordinated reads/writes
        └── SessionStore (shared ref)    merge writes back through existing store
```

**Source of truth:** local `Documents/Sessions/` always. iCloud container is a sync mirror.

**Container path:**
```
iCloud~com~cropbinary~layca/Documents/Sessions/{UUID}/
  session.json
  segments.json
  session_full.m4a    ← only when "Include audio" enabled
```

Same folder structure as local — minimal `SessionStore` refactoring.

---

## Data Model Changes

### `TranscriptRow` — add `updatedAt: Date`
- Set on creation
- Bumped on user text edit or speaker rename
- Decoded with `decodeIfPresent`, fallback `.now` — backward compatible

### `StoredSession` metadata — add `updatedAt: Date`
- Bumped on title change, speaker rename, status change, duration update
- Decoded with `decodeIfPresent`, fallback `.now` — backward compatible

---

## Merge Logic

```
merge(local: StoredSession, remote: StoredSession) -> StoredSession

  Metadata (session.json):
    winner = whichever session.updatedAt is newer

  Segments (segments.json):
    union rows by row.id
    per-row winner = row with higher updatedAt
    rows in remote not in local → added (new rows from other device)
    deleted rows → not tombstoned (reappear if deleted locally, present remotely)
                   acceptable edge case; revisit post-launch
```

---

## Sync Lifecycle

### Enable sync (first time)
1. Check `FileManager.ubiquityIdentityToken != nil`
2. If unavailable → show alert: "iCloud not available. Sign in to iCloud in Settings."
3. If available → upload all existing local sessions, start `NSMetadataQuery`

### Normal cycle
```
Local write
  → debounce 3s
  → ICloudSyncService.push(sessionID:)
  → NSFileCoordinator write to iCloud container

Remote change detected
  → NSMetadataQuery fires
  → ICloudSyncService.pull(sessionID:)
  → NSFileCoordinator read remote
  → merge(local:remote:)
  → write merged to both local + iCloud
```

### Additional triggers
- App foreground (`scenePhase == .active` / `NSApplicationDidBecomeActiveNotification`)
- "Sync Now" button (manual)
- Toggle turned ON → initial upload of all sessions

### Disable sync
- Stop `NSMetadataQuery`, cancel debounce timers
- Leave iCloud container files in place (user may re-enable or use another device)

### Error handling
- iCloud unavailable mid-session → skip silently, retry on next foreground
- NSFileCoordinator conflict → use `NSFileVersion.currentVersionOfItem`, apply merge
- Offline → local writes continue normally; iCloud daemon handles upload retry automatically

---

## UI Additions

**Settings > Account (existing screen):**

```
iCloud
  [Toggle] Sync sessions via iCloud          ← existing, now wired
  [Toggle] Include audio files               ← new, visible only when sync ON
           "Each session can be 50–150 MB"   ← warning subtitle

Sync Status                                  ← new section, visible only when sync ON
  Last synced: 2 minutes ago                 ← idle state
  [ProgressView] Syncing…                    ← syncing state
  Sync failed. Check iCloud settings.        ← error state (red)
  [Button] Sync Now                          ← manual trigger
```

**`AppBackend` additions:**
```swift
enum ICloudSyncStatus {
    case idle(lastSynced: Date?)
    case syncing
    case error(String)
    case unavailable
}

@Published var iCloudSyncStatus: ICloudSyncStatus = .idle(lastSynced: nil)
@Published var isAudioSyncEnabled: Bool = false   // persisted in AppSettingsStore
```

No per-bubble sync indicators. Conflicts resolve silently.

---

## Entitlements & Project Setup

### `layca.entitlements`
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

### Xcode — Signing & Capabilities
- Add "iCloud" capability
- Check "iCloud Documents" (not CloudKit)
- Container: `iCloud.com.cropbinary.layca`

### macOS sandbox
- Add `com.apple.developer.icloud-container-identifiers` to macOS entitlements file

No `Info.plist` changes needed. Container auto-provisioned by Apple on first signed-device access.

---

## Files to Create / Modify

| Action | File |
|---|---|
| **Create** | `xcode/layca/Services/ICloudSyncService.swift` |
| **Modify** | `xcode/layca/Models/Domain/TranscriptRow.swift` — add `updatedAt` |
| **Modify** | `xcode/layca/App/AppBackend.swift` — `StoredSession.updatedAt`, `iCloudSyncStatus`, `isAudioSyncEnabled`, wire `ICloudSyncService` |
| **Modify** | `xcode/layca/Features/Share/SettingsSheetFlowView.swift` — audio toggle + sync status UI |
| **Modify** | `xcode/layca/layca.entitlements` — iCloud container identifiers |
| **Modify** | `xcode/layca/layca-macOS.entitlements` (if exists) — same |

---

## Out of Scope (Post-Launch)

- Delete tombstones / deleted-row sync
- Per-row conflict UI (show both versions to user)
- Selective session sync (sync only starred sessions)
- iCloud storage usage display in Settings
- Background refresh / silent push for instant cross-device updates
