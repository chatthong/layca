# Qwen On-Device Summary Feature Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add an on-device "Summary" action (Summary | Share | Rename | Delete) that runs Qwen3-4B-Q4_K_M locally via llama.cpp to produce a structured markdown summary of any session transcript.

**Architecture:** `QwenSummaryService` (actor) wraps llama.cpp Swift bindings; it loads the GGUF lazily, formats input via ExportService's NotepadMinutes formatter, and streams tokens back to `SummarySheetView`. ChatTabView gains a new `isSummarySheetPresented` state and a Summary button prepended to both ControlGroup and context menu.

**Tech Stack:** MLX Swift (`ml-explore/mlx-swift-examples` SPM, product `MLXLLM`), Swift Concurrency (actor + AsyncStream), SwiftUI `.sheet`, ExportService (existing)

> ⚠️ **Correction from v1:** `ggml-org/llama.cpp` has no `Package.swift` — switched to `ml-explore/mlx-swift-examples` which has real SPM support AND routes through ANE+GPU on Apple Silicon (faster than llama.cpp Metal-only). GGUF file is obsolete; model auto-downloads as `mlx-community/Qwen3-4B-4bit`.

---

## Task 0: Move GGUF to proper location + update gitignore

**Files:**
- Move: `/Users/ter/Desktop/layca/Qwen_Qwen3-4B-Q4_K_M.gguf` → `xcode/layca/Models/RuntimeAssets/Qwen_Qwen3-4B-Q4_K_M.gguf`
- Modify: `.gitignore`

**Step 1: Move the file**
```bash
mv /Users/ter/Desktop/layca/Qwen_Qwen3-4B-Q4_K_M.gguf \
   /Users/ter/Desktop/layca/xcode/layca/Models/RuntimeAssets/Qwen_Qwen3-4B-Q4_K_M.gguf
```

**Step 2: Verify .gitignore already covers new path**

The existing `.gitignore` line `/xcode/layca/Models/RuntimeAssets` covers this. Verify:
```bash
cd /Users/ter/Desktop/layca && git check-ignore -v xcode/layca/Models/RuntimeAssets/Qwen_Qwen3-4B-Q4_K_M.gguf
```
Expected: `.gitignore:XX:/xcode/layca/Models/RuntimeAssets`
If NOT shown, add to `.gitignore`:
```
xcode/layca/Models/RuntimeAssets/Qwen_Qwen3-4B-Q4_K_M.gguf
```

Also remove the now-stale root-level line `Qwen_Qwen3-4B-Q4_K_M.gguf` from `.gitignore`.

**Step 3: Commit**
```bash
git add .gitignore
git commit -m "chore: move Qwen GGUF to Models/RuntimeAssets, tidy gitignore"
```

---

## Task 1: Add mlx-swift-examples Swift Package to Xcode project

**Files:**
- Modify: `xcode/layca.xcodeproj/project.pbxproj` (via Xcode UI only)

**Step 1: Open Xcode and add package**

In Xcode:
- File → Add Package Dependencies…
- URL: `https://github.com/ml-explore/mlx-swift-examples`
- Branch: `main`
- Add product **`MLXLLM`** to the `layca` target (MLXLMCommon is pulled in automatically)

**Step 2: Verify the package resolves**
```bash
cd /Users/ter/Desktop/layca/xcode && \
  xcodebuild -resolvePackageDependencies -scheme layca 2>&1 | tail -5
```
Expected: `Resolved source packages:` with mlx-swift-examples listed.

**Step 3: Commit**
```bash
cd /Users/ter/Desktop/layca
git add xcode/layca.xcodeproj/project.pbxproj \
        xcode/layca.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
git commit -m "feat: add mlx-swift-examples SPM dependency (MLXLLM) for Qwen on-device summary"
```

---

## Task 2: Implement `QwenSummaryService` actor

**Files:**
- Create: `xcode/layca/Libraries/QwenSummaryService.swift`

**Step 1: Write the service**

Create `xcode/layca/Libraries/QwenSummaryService.swift`:

```swift
//
//  QwenSummaryService.swift
//  layca
//
//  On-device summary using Qwen3-4B-Q4_K_M.gguf via llama.cpp
//

import Foundation
import llama

/// Hard-coded system prompt. Not user-configurable.
private let kSummarySystemPrompt = """
You are a precise meeting secretary. Read the transcript and respond ONLY with:

## Topic
[One crisp line: what this session was about]

## Summary
[3–5 sentences: who spoke, what was decided or discussed, key outcomes]

## Action Items
- [ ] [specific task, owner if mentioned]
(Omit the Action Items section entirely if there are no action items)

Be concise. Do not repeat the transcript. Do not add any preamble.
"""

/// Infers where the GGUF lives — mirrors WhisperGGMLCoreMLService path resolution.
private func qwenModelURL() -> URL? {
    // Development: Models/RuntimeAssets inside the source tree (not in app bundle)
    let runtimeAssets = URL(fileURLWithPath: #file)
        .deletingLastPathComponent()   // Libraries/
        .deletingLastPathComponent()   // layca/
        .appending(path: "Models/RuntimeAssets/Qwen_Qwen3-4B-Q4_K_M.gguf")
    if FileManager.default.fileExists(atPath: runtimeAssets.path) {
        return runtimeAssets
    }
    // Production: bundled resource (would require model bundling step)
    if let bundled = Bundle.main.url(forResource: "Qwen_Qwen3-4B-Q4_K_M", withExtension: "gguf") {
        return bundled
    }
    return nil
}

/// Actor that owns llama.cpp model + context. Call from any Task.
actor QwenSummaryService {

    static let shared = QwenSummaryService()

    private var llamaModel: OpaquePointer?
    private var llamaCtx: OpaquePointer?
    private var isLoaded = false

    // MARK: - Public API

    /// Produces a structured markdown summary of a NotepadMinutes transcript.
    /// Streams tokens progressively via the returned AsyncThrowingStream.
    func summarize(notepadMinutesText: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try self.loadIfNeeded()
                    let output = try self.runInference(transcript: notepadMinutesText)
                    continuation.yield(output)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private

    private func loadIfNeeded() throws {
        guard !isLoaded else { return }

        guard let modelURL = qwenModelURL() else {
            throw QwenError.modelNotFound
        }

        llama_backend_init()

        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = 99  // offload all to GPU/ANE when available

        guard let model = llama_model_load_from_file(modelURL.path, modelParams) else {
            throw QwenError.modelLoadFailed
        }

        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx = 4096
        ctxParams.n_threads = Int32(max(1, ProcessInfo.processInfo.processorCount - 2))
        ctxParams.n_threads_batch = ctxParams.n_threads

        guard let ctx = llama_new_context_with_model(model, ctxParams) else {
            llama_model_free(model)
            throw QwenError.contextCreateFailed
        }

        self.llamaModel = model
        self.llamaCtx = ctx
        self.isLoaded = true
    }

    private func runInference(transcript: String) throws -> String {
        guard let model = llamaModel, let ctx = llamaCtx else {
            throw QwenError.notLoaded
        }

        // Build Qwen3 chat messages
        let systemMsg  = "system\0" + kSummarySystemPrompt + "\0"
        let userMsg    = "user\0" + transcript + "\0"
        let messages: [llama_chat_message] = [
            llama_chat_message(role: "system", content: kSummarySystemPrompt),
            llama_chat_message(role: "user",   content: transcript),
        ]

        // Apply chat template from GGUF metadata
        var buf = [CChar](repeating: 0, count: 8192)
        let templateLen = llama_chat_apply_template(model, nil, messages, messages.count, true, &buf, Int32(buf.count))
        guard templateLen > 0 else { throw QwenError.templateFailed }

        let prompt = String(cString: buf)

        // Tokenise
        var tokens = [llama_token](repeating: 0, count: 4096)
        let nTokens = llama_tokenize(model, prompt, Int32(prompt.utf8.count), &tokens, 4096, true, true)
        guard nTokens > 0 else { throw QwenError.tokenizeFailed }

        tokens = Array(tokens.prefix(Int(nTokens)))

        // Eval
        llama_kv_cache_clear(ctx)
        var batch = llama_batch_init(512, 0, 1)
        defer { llama_batch_free(batch) }

        for (i, tok) in tokens.enumerated() {
            llama_batch_add(&batch, tok, llama_pos(i), [0], i == tokens.count - 1)
        }
        guard llama_decode(ctx, batch) == 0 else { throw QwenError.decodeFailed }

        // Sample up to 1024 new tokens
        var output = ""
        var nCur = Int32(tokens.count)
        let nMax  = Int32(tokens.count) + 1024

        var sparams = llama_sampler_chain_default_params()
        let sampler = llama_sampler_chain_init(sparams)
        defer { llama_sampler_free(sampler) }
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(0.3))
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(UInt32.random(in: 0..<UInt32.max)))

        while nCur < nMax {
            let newToken = llama_sampler_sample(sampler, ctx, -1)
            llama_sampler_accept(sampler, newToken)

            if llama_token_is_eog(model, newToken) { break }

            var piece = [CChar](repeating: 0, count: 256)
            let nPiece = llama_token_to_piece(model, newToken, &piece, 256, 0, true)
            if nPiece > 0 {
                output += String(cString: piece)
            }

            llama_batch_clear(&batch)
            llama_batch_add(&batch, newToken, nCur, [0], true)
            guard llama_decode(ctx, batch) == 0 else { break }
            nCur += 1
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum QwenError: LocalizedError {
    case modelNotFound, modelLoadFailed, contextCreateFailed
    case notLoaded, templateFailed, tokenizeFailed, decodeFailed

    var errorDescription: String? {
        switch self {
        case .modelNotFound:      return "Qwen model file not found. Place Qwen_Qwen3-4B-Q4_K_M.gguf in Models/RuntimeAssets/."
        case .modelLoadFailed:    return "Failed to load Qwen model."
        case .contextCreateFailed:return "Failed to create llama context."
        case .notLoaded:          return "Model not loaded."
        case .templateFailed:     return "Chat template application failed."
        case .tokenizeFailed:     return "Tokenization failed."
        case .decodeFailed:       return "Inference decode failed."
        }
    }
}
```

**Step 2: Verify it compiles (no unit test needed for actor shell)**
```bash
cd /Users/ter/Desktop/layca/xcode && \
  xcodebuild -scheme layca -destination 'platform=macOS' \
    build 2>&1 | grep -E "error:|BUILD SUCCEEDED"
```
Expected: `BUILD SUCCEEDED`

**Step 3: Commit**
```bash
git add xcode/layca/Libraries/QwenSummaryService.swift
git commit -m "feat: add QwenSummaryService actor (llama.cpp GGUF inference)"
```

---

## Task 3: Implement `SummarySheetView`

**Files:**
- Create dir: `xcode/layca/Features/Summary/`
- Create: `xcode/layca/Features/Summary/SummarySheetView.swift`

**Step 1: Write the view**

```swift
//
//  SummarySheetView.swift
//  layca
//

import SwiftUI

struct SummarySheetView: View {

    let snapshot: ExportSessionSnapshot

    @State private var phase: Phase = .idle
    @Environment(\.dismiss) private var dismiss

    enum Phase {
        case idle
        case loading
        case result(String)
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Session Summary")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    if case .result(let text) = phase {
                        ToolbarItem(placement: .confirmationAction) {
                            Button {
                                UIPasteboard.general.string = text
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                        }
                    }
                }
                .task { await runSummary() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle, .loading:
            loadingView

        case .result(let markdown):
            ScrollView {
                Text(attributedMarkdown(markdown))
                    .textSelection(.enabled)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .failed(let message):
            ContentUnavailableView {
                Label("Summary Failed", systemImage: "exclamationmark.bubble")
            } description: {
                Text(message)
            } actions: {
                Button("Retry") { phase = .idle; Task { await runSummary() } }
                    .buttonStyle(.bordered)
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Qwen is reading the transcript…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Running fully on-device")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func runSummary() async {
        guard case .idle = phase else { return }
        phase = .loading
        let input = ExportService.build(format: .notepadMinutes, snapshot: snapshot)
        do {
            for try await chunk in QwenSummaryService.shared.summarize(notepadMinutesText: input) {
                if case .loading = phase {
                    phase = .result(chunk)
                } else if case .result(let prev) = phase {
                    phase = .result(prev + chunk)
                }
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func attributedMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}
```

> **Note on macOS `UIPasteboard`**: Replace with `NSPasteboard.general.setString(text, forType: .string)` inside `#if os(macOS)` guard. The agent should add platform-conditional clipboard code.

**Step 2: Compile check**
```bash
cd /Users/ter/Desktop/layca/xcode && \
  xcodebuild -scheme layca -destination 'platform=macOS' \
    build 2>&1 | grep -E "error:|BUILD SUCCEEDED"
```

**Step 3: Commit**
```bash
git add xcode/layca/Features/Summary/SummarySheetView.swift
git commit -m "feat: add SummarySheetView with loading/result/error states"
```

---

## Task 4: Update `ChatTabView` — add Summary action

**Files:**
- Modify: `xcode/layca/Features/Chat/ChatTabView.swift`

**Context:** ChatTabView has two places with Share/Rename/Delete:
1. `topTrailingSessionActionsToolbarControl` — `ControlGroup` shown on wider screens
2. `topTrailingMenuActions` — `@ViewBuilder` used in a `Menu` on narrow screens

**Step 1: Add state + snapshot helper near top of struct**

After `@State private var isDeleteDialogPresented = false` (line ~56), add:
```swift
@State private var isSummarySheetPresented = false
```

**Step 2: Add a computed `ExportSessionSnapshot` property**

After the existing `@State` declarations, add:
```swift
private var exportSnapshot: ExportSessionSnapshot {
    ExportSessionSnapshot(
        title: activeSessionTitle,
        createdAtText: activeSessionDateText,
        rows: liveChatItems
    )
}
```

**Step 3: Update `topTrailingSessionActionsToolbarControl`**

Find the `ControlGroup` block and prepend the Summary button:
```swift
// BEFORE first Button(action: onExportTap):
Button {
    isSummarySheetPresented = true
} label: {
    topToolbarSummaryIconLabel
}
.disabled(isDraftSession || liveChatItems.isEmpty)
```

**Step 4: Update `topTrailingMenuActions`**

Prepend before the Share button:
```swift
Button {
    isSummarySheetPresented = true
} label: {
    Label("Summary", systemImage: "sparkles.rectangle.stack")
}
.disabled(isDraftSession || liveChatItems.isEmpty)
```

**Step 5: Add icon label computed property**

After `topToolbarShareIconLabel`, add:
```swift
private var topToolbarSummaryIconLabel: some View {
    Label("Summary", systemImage: "sparkles.rectangle.stack")
        .labelStyle(.iconOnly)
        .font(.system(size: 12, weight: .semibold))
}
```

**Step 6: Attach sheet modifier**

Find the block with `.confirmationDialog("Delete this chat?", ...)` and after it add:
```swift
.sheet(isPresented: $isSummarySheetPresented) {
    SummarySheetView(snapshot: exportSnapshot)
}
```

**Step 7: Compile + verify menu order is Summary | Share | Rename | Delete**

```bash
cd /Users/ter/Desktop/layca/xcode && \
  xcodebuild -scheme layca -destination 'platform=macOS' \
    build 2>&1 | grep -E "error:|BUILD SUCCEEDED"
```

**Step 8: Commit**
```bash
git add xcode/layca/Features/Chat/ChatTabView.swift
git commit -m "feat: add Summary action to chat toolbar and context menu (Summary|Share|Rename|Delete)"
```

---

## Task 5: Wire `AppBackend` snapshot to call sites (if needed)

**Files:**
- Modify: `xcode/layca/App/ContentView.swift` (check call sites)
- Modify: `xcode/layca/App/AppBackend.swift` (if snapshot factory needed)

**Step 1: Grep all ChatTabView instantiation sites**
```bash
grep -rn "ChatTabView(" /Users/ter/Desktop/layca/xcode --include="*.swift"
```

**Step 2: For each site**, confirm `activeSessionTitle`, `activeSessionDateText`, and `liveChatItems` are already passed. They should be — they're existing parameters. No new props needed on ChatTabView (the snapshot is assembled internally in Task 4).

**Step 3: Compile full scheme**
```bash
cd /Users/ter/Desktop/layca/xcode && \
  xcodebuild -scheme layca -destination 'platform=macOS' \
    build 2>&1 | grep -E "error:|BUILD SUCCEEDED"
```
Expected: `BUILD SUCCEEDED`

**Step 4: Commit if any changes were needed**
```bash
git add -p && git commit -m "fix: wire Summary sheet snapshot through ChatTabView call sites"
```

---

## Task 6: Agent Review Checkpoint

**swift-engineer reviews:**
- `QwenSummaryService.swift` — concurrency safety, actor isolation, llama.cpp lifetime
- `ChatTabView.swift` diff — state management correctness

**apple-design-lead reviews:**
- `SummarySheetView.swift` — HIG compliance, loading state, typography, platform adaptation

Run both agents in parallel (no shared state between reviews):
```bash
# Terminal 1
claude "Use the swift-engineer agent to review xcode/layca/Libraries/QwenSummaryService.swift and the Summary-related changes in ChatTabView.swift. Focus on actor isolation, llama.cpp handle lifetimes, and concurrency correctness."

# Terminal 2
claude "Use the apple-design-lead agent to HIG-audit xcode/layca/Features/Summary/SummarySheetView.swift. Check: loading state, empty state, error recovery, typography, platform adaptation (iOS/macOS/visionOS), and sheet presentation style."
```

Apply any critical (Severity=Critical/High) feedback before final commit.

---

## Task 7: Final integration commit + update TODO

**Step 1: Run full build one last time**
```bash
cd /Users/ter/Desktop/layca/xcode && \
  xcodebuild -scheme layca -destination 'platform=macOS' \
    build 2>&1 | grep -E "error:|BUILD SUCCEEDED"
```

**Step 2: Update TODO.md**

Add to completed section:
```markdown
- [x] On-device Qwen summary feature (Summary | Share | Rename | Delete menu)
- [x] QwenSummaryService actor (llama.cpp GGUF, Qwen3-4B-Q4_K_M)
- [x] GGUF moved to Models/RuntimeAssets/
```

**Step 3: Final commit**
```bash
git add TODO.md .claude/agents/qwen-ios-senior.md
git commit -m "chore: update TODO + qwen-ios-senior agent with Codex CLI workflow"
```

---

## Parallel Agent Assignment

| Task | Primary Agent | Approach |
|---|---|---|
| Task 0 — GGUF move | qwen-ios-senior | Direct shell + gitignore edit |
| Task 1 — SPM package | qwen-ios-senior | Xcode UI (can't edit pbxproj safely via CLI) |
| Task 2 — QwenSummaryService | qwen-ios-senior | Codex CLI for implementation |
| Task 3 — SummarySheetView | qwen-ios-senior | Codex CLI for implementation |
| Task 4 — ChatTabView update | qwen-ios-senior | Codex CLI for targeted edits |
| Task 5 — Wire call sites | qwen-ios-senior | Grep + targeted Edit |
| Task 6 — Review | swift-engineer + apple-design-lead | Parallel review |
| Task 7 — Finalize | main session | Direct |
