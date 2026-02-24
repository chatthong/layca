# AGENTS.md — Codex Parallel Agent Team

## Purpose
Codex-side agent roster for running parallel work across multiple iTerm terminals/worktrees.
Use this file (not `CLAUDE.md`) when assigning Codex teammates.

## Team Lead (Coordinator)
- `codex-team-lead` — Task decomposition, terminal/worktree assignment, interface contracts, merge order, cross-agent review, conflict prevention (Extra high model)

## Existing Codex Agents
- `ml-inference-lead-codex` — CoreML, Metal GPU, ANE routing, Whisper/VAD/diarization model optimization, on-device inference latency (High model)
- `audio-processing-lead-codex` — AVAudioEngine, AVAudioSession, signal processing, VAD tuning, buffer alignment, audio quality (High model)
- `swift-engineer-1-codex` — architecture, code quality, bugs (Medium model)
- `swift-engineer-2-codex` — architecture, code quality, bugs (Medium model)

## New Codex Agents (Added for Parallel iTerm Work)
- `qa-test-lead-codex` — XCTest/UI test coverage, regression validation, repro steps, edge-case testing, test plan execution (High model)
- `swiftui-platform-lead-codex` — SwiftUI views, navigation flows, platform-specific UI behavior (iOS/macOS/visionOS), interaction bugs (High model)
- `data-persistence-lead-codex` — session storage, JSON schema changes, migrations, import/export, file integrity and recovery paths (High model)
- `tooling-release-lead-codex` — Xcode build settings, scripts, CI workflows, packaging/release prep, lint/format/build automation (Medium model)

## Parallel Execution Rules (iTerm + Multi-Terminal)
- One agent per terminal and one workstream at a time.
- Prefer one git worktree per agent to avoid file contention.
- Team lead assigns file ownership before coding (who touches which paths).
- Agents should avoid overlapping edits unless explicitly coordinated.
- Each agent reports back with: changed files, risks, tests run, blockers.
- Team lead merges in this order: foundations (`data/tooling`) -> pipeline (`audio/ml`) -> app/UI (`swift/swiftui`) -> QA validation.

## Suggested iTerm Layout
- Terminal 1: `codex-team-lead` (triage, task board, merge/review)
- Terminal 2: `ml-inference-lead-codex`
- Terminal 3: `audio-processing-lead-codex`
- Terminal 4: `swift-engineer-1-codex`
- Terminal 5: `swift-engineer-2-codex`
- Terminal 6: `qa-test-lead-codex`
- Terminal 7: `swiftui-platform-lead-codex`
- Terminal 8: `data-persistence-lead-codex`
- Terminal 9: `tooling-release-lead-codex`

## Assignment Template (Lead -> Agent)
- Goal:
- Scope (files/modules):
- Constraints:
- Deliverable:
- Validation required:
- Branch/worktree:
