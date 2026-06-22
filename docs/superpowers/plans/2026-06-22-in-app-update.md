# In-App One-Click Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a one-click "Update Now" to `UpdateAvailableSheet` that downloads the release zip, verifies it, atomically replaces the running app bundle in place, and relaunches.

**Architecture:** `UpdateChecker` learns to parse the `-mac.zip` asset URL. A pure `UpdateInstallTarget` decides whether the running bundle can be replaced. A new `@MainActor @Observable Updater` runs download→unpack→verify→swap→relaunch with an observable phase. `UpdateAvailableSheet` drives it; failures fall back to the existing manual install command. Trust model: HTTPS + unpacked-bundle version sanity check (no signature/checksum verification this iteration).

**Tech Stack:** Swift 5.10, SwiftUI, `@Observable`, `URLSession`, `Process` (`ditto`/`xattr`), `FileManager.replaceItemAt`. XCTest with the existing `StubURLProtocol`.

**Spec:** `docs/superpowers/specs/2026-06-22-in-app-update-design.md`

---

## File Structure

- **Modify** `Sources/Parallel/Services/UpdateChecker.swift` — add `UpdateInfo.assetURL`, decode `assets[]`, add pure `selectMacZipAsset`.
- **Create** `Sources/Parallel/Services/UpdateInstallTarget.swift` — pure `resolve(bundleURL:isWritable:)`.
- **Create** `Sources/Parallel/Services/Updater.swift` — `@MainActor @Observable`; `Phase`, `UpdaterError`, pure `bundleShortVersion(at:)`, and the side-effecting pipeline.
- **Modify** `Sources/Parallel/Views/Sheets/UpdateAvailableSheet.swift` — Update Now + progress + fallback.
- **Modify** `Sources/Parallel/ParallelApp.swift` — own + inject `Updater`.
- **Create** `Tests/ParallelTests/UpdateInstallTargetTests.swift`, `Tests/ParallelTests/UpdaterHelpersTests.swift`.
- **Modify** `Tests/ParallelTests/UpdateCheckerTests.swift` — assert `assetURL` parsing.

---

### Task 1: Parse the download asset URL in UpdateChecker

**Files:**
- Modify: `Sources/Parallel/Services/UpdateChecker.swift`
- Test: `Tests/ParallelTests/UpdateCheckerTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `Tests/ParallelTests/UpdateCheckerTests.swift` (inside the class). Note: add a second payload helper that includes an `assets` array, then two tests:

```swift
    private func payloadWithAssets(tag: String) -> Data {
        let json = #"""
        {
          "tag_name": "\#(tag)",
          "html_url": "https://github.com/BottlePumpkin/Parallel/releases/tag/\#(tag)",
          "body": "notes",
          "published_at": "2026-06-15T12:00:00Z",
          "assets": [
            {"name": "source.txt", "browser_download_url": "https://example.com/source.txt"},
            {"name": "Parallel-\#(tag.dropFirst())-mac.zip", "browser_download_url": "https://example.com/Parallel-mac.zip"}
          ]
        }
        """#
        return json.data(using: .utf8)!
    }

    func test_check_parses_mac_zip_asset_url() async {
        StubURLProtocol.requestHandler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, self.payloadWithAssets(tag: "v0.1.5"))
        }
        let checker = makeChecker()
        await checker.check(force: true)
        guard case .available(let info)? = checker.lastCheckResult else {
            return XCTFail("expected .available")
        }
        XCTAssertEqual(info.assetURL, URL(string: "https://example.com/Parallel-mac.zip"))
    }

    func test_check_assetURL_nil_when_no_mac_zip() async {
        StubURLProtocol.requestHandler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, self.payload(tag: "v0.1.5"))  // existing helper: no assets key
        }
        let checker = makeChecker()
        await checker.check(force: true)
        guard case .available(let info)? = checker.lastCheckResult else {
            return XCTFail("expected .available")
        }
        XCTAssertNil(info.assetURL)
    }

    func test_selectMacZipAsset_picks_first_mac_zip() {
        let url = UpdateChecker.selectMacZipAsset(from: [
            ("notes.txt", URL(string: "https://e.com/notes.txt")!),
            ("Parallel-0.4.0-mac.zip", URL(string: "https://e.com/a-mac.zip")!),
            ("Parallel-0.5.0-mac.zip", URL(string: "https://e.com/b-mac.zip")!),
        ])
        XCTAssertEqual(url, URL(string: "https://e.com/a-mac.zip"))
        XCTAssertNil(UpdateChecker.selectMacZipAsset(from: [("x.txt", URL(string: "https://e.com/x")!)]))
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter UpdateCheckerTests 2>&1 | tail -20`
Expected: compile failure / FAIL — `UpdateInfo` has no `assetURL`, `selectMacZipAsset` undefined.

- [ ] **Step 3: Implement in `UpdateChecker.swift`**

Add `assetURL` to the struct (after `publishedAt`):

```swift
struct UpdateInfo: Equatable {
    let latestTag: String
    let latestVersion: SemanticVersion
    let releaseURL: URL
    let releaseNotes: String
    let publishedAt: Date
    let assetURL: URL?
}
```

Add the pure selector as a static method on `UpdateChecker` (place it just above `checkIfStale`):

```swift
    /// First asset whose filename ends in `-mac.zip` (the notarized build).
    static func selectMacZipAsset(from assets: [(name: String, url: URL)]) -> URL? {
        assets.first { $0.name.hasSuffix("-mac.zip") }?.url
    }
```

Extend `ReleasePayload` to decode assets (tolerate a missing key so existing test fixtures still decode):

```swift
private struct ReleasePayload: Decodable {
    let tagName: String
    let htmlUrl: URL
    let body: String?
    let publishedAt: Date
    let assets: [Asset]?
    struct Asset: Decodable {
        let name: String
        let browserDownloadUrl: URL
        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadUrl = "browser_download_url"
        }
    }
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
        case body
        case publishedAt = "published_at"
        case assets
    }
}
```

In `check(force:)`, where `UpdateInfo(...)` is built (the `if latest > current` branch), compute and pass `assetURL`:

```swift
            let assetURL = UpdateChecker.selectMacZipAsset(
                from: (payload.assets ?? []).map { ($0.name, $0.browserDownloadUrl) }
            )
            let info = UpdateInfo(
                latestTag: payload.tagName,
                latestVersion: latest,
                releaseURL: payload.htmlUrl,
                releaseNotes: payload.body ?? "",
                publishedAt: payload.publishedAt,
                assetURL: assetURL
            )
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter UpdateCheckerTests 2>&1 | tail -20`
Expected: PASS (all UpdateCheckerTests including the 3 new ones; the older tests still pass because `assets` is optional).

- [ ] **Step 5: Commit**

```bash
git add Sources/Parallel/Services/UpdateChecker.swift Tests/ParallelTests/UpdateCheckerTests.swift
git commit -m "feat(updates): parse -mac.zip asset URL into UpdateInfo (#5)"
```

---

### Task 2: UpdateInstallTarget — replaceability of the running bundle

**Files:**
- Create: `Sources/Parallel/Services/UpdateInstallTarget.swift`
- Test: `Tests/ParallelTests/UpdateInstallTargetTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/ParallelTests/UpdateInstallTargetTests.swift`:

```swift
import XCTest
@testable import Parallel

final class UpdateInstallTargetTests: XCTestCase {
    private func url(_ p: String) -> URL { URL(fileURLWithPath: p) }

    func test_normal_app_in_applications_is_replaceable() {
        let r = UpdateInstallTarget.resolve(bundleURL: url("/Applications/Parallel.app"),
                                            isWritable: { _ in true })
        XCTAssertEqual(r, .replaceable(url("/Applications/Parallel.app")))
    }

    func test_dev_build_non_app_is_unsupported() {
        let r = UpdateInstallTarget.resolve(bundleURL: url("/Users/me/dev/Parallel/.build/debug/Parallel"),
                                            isWritable: { _ in true })
        guard case .unsupported = r else { return XCTFail("expected unsupported for non-.app") }
    }

    func test_app_translocation_path_is_unsupported() {
        let r = UpdateInstallTarget.resolve(
            bundleURL: url("/private/var/folders/ab/AppTranslocation/XYZ/d/Parallel.app"),
            isWritable: { _ in true })
        guard case .unsupported = r else { return XCTFail("expected unsupported for translocation") }
    }

    func test_non_writable_parent_is_unsupported() {
        let r = UpdateInstallTarget.resolve(bundleURL: url("/Applications/Parallel.app"),
                                            isWritable: { _ in false })
        guard case .unsupported = r else { return XCTFail("expected unsupported for read-only parent") }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter UpdateInstallTargetTests 2>&1 | tail -15`
Expected: compile failure — `UpdateInstallTarget` doesn't exist.

- [ ] **Step 3: Implement `UpdateInstallTarget.swift`**

```swift
import Foundation

/// Decides whether the currently-running app bundle can be replaced in place by
/// an in-app update. Pure (filesystem access is injected) so it is unit-tested.
enum UpdateInstallTarget: Equatable {
    /// The `.app` bundle URL to replace.
    case replaceable(URL)
    /// Update can't proceed; the String is a user-facing reason.
    case unsupported(String)

    static func resolve(
        bundleURL: URL,
        isWritable: (URL) -> Bool = { FileManager.default.isWritableFile(atPath: $0.path) }
    ) -> UpdateInstallTarget {
        guard bundleURL.pathExtension == "app" else {
            return .unsupported("Running from a development build — update via the install command instead.")
        }
        if bundleURL.path.contains("/AppTranslocation/") {
            return .unsupported("Move Parallel into /Applications first, then update.")
        }
        let parent = bundleURL.deletingLastPathComponent()
        guard isWritable(parent) else {
            return .unsupported("Can't write to \(parent.path) — install manually.")
        }
        return .replaceable(bundleURL)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter UpdateInstallTargetTests 2>&1 | tail -15`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/Parallel/Services/UpdateInstallTarget.swift Tests/ParallelTests/UpdateInstallTargetTests.swift
git commit -m "feat(updates): UpdateInstallTarget replaceability resolver (#5)"
```

---

### Task 3: Updater skeleton + bundle-version helper

**Files:**
- Create: `Sources/Parallel/Services/Updater.swift`
- Test: `Tests/ParallelTests/UpdaterHelpersTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/ParallelTests/UpdaterHelpersTests.swift`:

```swift
import XCTest
@testable import Parallel

final class UpdaterHelpersTests: XCTestCase {

    /// Build a throwaway `.app` with Contents/Info.plist carrying the version.
    private func makeBundle(version: String?) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("Parallel.app", isDirectory: true)
        let contents = root.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var dict: [String: Any] = ["CFBundleName": "Parallel"]
        if let version { dict["CFBundleShortVersionString"] = version }
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return root
    }

    func test_bundleShortVersion_reads_value() throws {
        let bundle = try makeBundle(version: "0.4.0")
        XCTAssertEqual(Updater.bundleShortVersion(at: bundle), "0.4.0")
    }

    func test_bundleShortVersion_nil_when_missing_key() throws {
        let bundle = try makeBundle(version: nil)
        XCTAssertNil(Updater.bundleShortVersion(at: bundle))
    }

    func test_bundleShortVersion_nil_when_no_plist() {
        let bogus = FileManager.default.temporaryDirectory.appendingPathComponent("Nope.app")
        XCTAssertNil(Updater.bundleShortVersion(at: bogus))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter UpdaterHelpersTests 2>&1 | tail -15`
Expected: compile failure — `Updater` doesn't exist.

- [ ] **Step 3: Implement the `Updater.swift` skeleton**

Create `Sources/Parallel/Services/Updater.swift` (pipeline filled in Task 4; this compiles and satisfies the helper test):

```swift
import Foundation
import AppKit
import Observation

enum UpdaterError: Error {
    case message(String)
    var text: String {
        if case .message(let m) = self { return m }
        return "Update failed."
    }
}

/// Downloads a release zip, verifies it, atomically replaces the running bundle
/// in place, and relaunches. The pure `bundleShortVersion` helper is unit-tested;
/// the side-effecting pipeline (network, ditto, file swap, relaunch) is verified
/// manually, like SessionManager.
@MainActor
@Observable
final class Updater {
    enum Phase: Equatable {
        case idle
        case downloading(fraction: Double)
        case unpacking
        case verifying
        case installing
        case relaunching
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private var task: Task<Void, Never>?

    /// Reads `CFBundleShortVersionString` from a `.app` bundle URL. Pure.
    static func bundleShortVersion(at bundleURL: URL) -> String? {
        let plist = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let obj = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = obj as? [String: Any] else { return nil }
        return dict["CFBundleShortVersionString"] as? String
    }

    func cancel() {
        task?.cancel()
        phase = .idle
    }

    /// Kicks off the update pipeline (implemented in Task 4).
    func update(from info: UpdateInfo, target: URL, session: URLSession = .shared) {
        // Implemented in Task 4.
        phase = .failed("Updater not yet implemented.")
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter UpdaterHelpersTests 2>&1 | tail -15`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/Parallel/Services/Updater.swift Tests/ParallelTests/UpdaterHelpersTests.swift
git commit -m "feat(updates): Updater skeleton + bundle-version helper (#5)"
```

---

### Task 4: Updater pipeline (download → unpack → verify → swap → relaunch)

**Files:**
- Modify: `Sources/Parallel/Services/Updater.swift`

This task is side-effecting (network/Process/file swap) and is verified by `swift build` + manual run, not unit tests.

- [ ] **Step 1: Replace the `update(from:target:session:)` stub and add private helpers**

In `Updater.swift`, replace the stub `update(...)` method with the real implementation and the helpers below (insert before the closing brace of the class):

```swift
    func update(from info: UpdateInfo, target: URL, session: URLSession = .shared) {
        guard let assetURL = info.assetURL else {
            phase = .failed("This release has no downloadable build attached.")
            return
        }
        task = Task { [weak self] in
            await self?.run(assetURL: assetURL,
                            expectedVersion: info.latestVersion.description,
                            target: target,
                            session: session)
        }
    }

    private func run(assetURL: URL, expectedVersion: String, target: URL, session: URLSession) async {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ParallelUpdate-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            phase = .downloading(fraction: 0)
            let zipURL = tempDir.appendingPathComponent("Parallel.zip")
            try await download(assetURL, to: zipURL, session: session)
            try Task.checkCancellation()

            phase = .unpacking
            let unpackDir = tempDir.appendingPathComponent("unpacked", isDirectory: true)
            try FileManager.default.createDirectory(at: unpackDir, withIntermediateDirectories: true)
            try runProcess("/usr/bin/ditto", ["-x", "-k", zipURL.path, unpackDir.path])
            let newApp = unpackDir.appendingPathComponent("Parallel.app")
            guard FileManager.default.fileExists(atPath: newApp.path) else {
                throw UpdaterError.message("Downloaded archive didn't contain Parallel.app.")
            }

            phase = .verifying
            let got = Self.bundleShortVersion(at: newApp)
            guard got == expectedVersion else {
                throw UpdaterError.message("Version mismatch: expected \(expectedVersion), got \(got ?? "unknown").")
            }
            // Best-effort: a download may carry the quarantine xattr.
            try? runProcess("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])

            phase = .installing
            try swap(target: target, with: newApp)

            phase = .relaunching
            relaunch(bundleURL: target)
            NSApp.terminate(nil)
        } catch is CancellationError {
            phase = .idle
        } catch {
            phase = .failed((error as? UpdaterError)?.text ?? error.localizedDescription)
        }
    }

    /// Streams the asset to `dest`, publishing download fraction when the server
    /// reports a content length.
    private func download(_ url: URL, to dest: URL, session: URLSession) async throws {
        let (bytes, response) = try await session.bytes(from: url)
        let total = response.expectedContentLength
        FileManager.default.createFile(atPath: dest.path, contents: nil)
        let handle = try FileHandle(forWritingTo: dest)
        defer { try? handle.close() }
        var buffer = Data()
        buffer.reserveCapacity(262_144)
        var received: Int64 = 0
        for try await byte in bytes {
            buffer.append(byte)
            received += 1
            if buffer.count >= 262_144 {
                try handle.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
                if total > 0 { phase = .downloading(fraction: Double(received) / Double(total)) }
                try Task.checkCancellation()
            }
        }
        if !buffer.isEmpty { try handle.write(contentsOf: buffer) }
    }

    /// Atomic in-place replacement. Stages the new bundle next to the target
    /// (same volume) so `replaceItemAt` can swap atomically.
    private func swap(target: URL, with newApp: URL) throws {
        let parent = target.deletingLastPathComponent()
        let staging = parent.appendingPathComponent(".Parallel.app.new-\(UUID().uuidString)")
        do {
            try FileManager.default.moveItem(at: newApp, to: staging)
        } catch {
            // Cross-volume move can fail; fall back to copy.
            try FileManager.default.copyItem(at: newApp, to: staging)
        }
        do {
            _ = try FileManager.default.replaceItemAt(target, withItemAt: staging,
                                                      backupItemName: nil,
                                                      options: [.usingNewMetadataOnly])
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    /// Detached helper waits for this process to exit, then opens the new bundle.
    private func relaunch(bundleURL: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; open \"\(bundleURL.path)\""
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script]
        try? p.run()  // detached; do not wait
    }

    private func runProcess(_ launchPath: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw UpdaterError.message("\(launchPath) exited \(p.terminationStatus).")
        }
    }
```

- [ ] **Step 2: Verify it builds**

Run: `swift build 2>&1 | tail -20`
Expected: `Compiling`/`Build complete!` with no errors.

- [ ] **Step 3: Verify existing tests still pass**

Run: `swift test --filter UpdaterHelpersTests 2>&1 | tail -10`
Expected: PASS (helper tests unaffected by the pipeline addition).

- [ ] **Step 4: Commit**

```bash
git add Sources/Parallel/Services/Updater.swift
git commit -m "feat(updates): Updater pipeline — download, verify, in-place swap, relaunch (#5)"
```

---

### Task 5: Wire Update Now into the sheet + app environment

**Files:**
- Modify: `Sources/Parallel/ParallelApp.swift`
- Modify: `Sources/Parallel/Views/Sheets/UpdateAvailableSheet.swift`

- [ ] **Step 1: Own and inject `Updater` in `ParallelApp.swift`**

Add the state property next to the others (after `updateChecker`):

```swift
    @State private var updateChecker = UpdateChecker()
    @State private var updater = Updater()
```

Add the environment injection in the `.environment(...)` chain (after `.environment(updateChecker)`):

```swift
                .environment(updateChecker)
                .environment(updater)
```

- [ ] **Step 2: Replace the install-command block in `UpdateAvailableSheet.swift`**

Replace the whole file with:

```swift
import SwiftUI
import AppKit

struct UpdateAvailableSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(UpdateChecker.self) private var checker
    @Environment(Updater.self) private var updater
    let info: UpdateInfo

    private let installCommand = "curl -fsSL https://raw.githubusercontent.com/BottlePumpkin/Parallel/master/scripts/install.sh | bash"

    @State private var copied = false

    private var target: UpdateInstallTarget {
        UpdateInstallTarget.resolve(bundleURL: Bundle.main.bundleURL)
    }

    private var canUpdateInApp: Bool {
        if info.assetURL == nil { return false }
        if case .replaceable = target { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Update available").font(.title2).bold()
            Text("Parallel \(info.latestVersion.description) is out — you're on \(AppVersion.current.description).")
                .font(.subheadline).foregroundStyle(.secondary)

            Divider()

            Text("Release notes").font(.headline)
            ScrollView {
                Text(info.releaseNotes.isEmpty ? "(no notes)" : info.releaseNotes)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 180, maxHeight: 280)
            .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))

            progressOrFallback

            HStack {
                Button("Skip This Version") {
                    checker.skip(info.latestVersion)
                    dismiss()
                }
                Spacer()
                Button("Later") { dismiss() }
                if canUpdateInApp {
                    Button("Update Now") {
                        if case .replaceable(let url) = target {
                            updater.update(from: info, target: url)
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isBusy)
                } else {
                    Button("Open Release Page") {
                        NSWorkspace.shared.open(info.releaseURL)
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 540)
    }

    private var isBusy: Bool {
        switch updater.phase {
        case .idle, .failed: return false
        default: return true
        }
    }

    @ViewBuilder
    private var progressOrFallback: some View {
        switch updater.phase {
        case .downloading(let fraction):
            HStack {
                ProgressView(value: fraction).frame(maxWidth: .infinity)
                Button("Cancel") { updater.cancel() }
            }
        case .unpacking, .verifying, .installing, .relaunching:
            HStack { ProgressView(); Text(statusText).foregroundStyle(.secondary) }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 4) {
                Text(message).font(.callout).foregroundStyle(.red)
                manualFallback
            }
        case .idle:
            if !canUpdateInApp {
                VStack(alignment: .leading, spacing: 4) {
                    Text(fallbackReason).font(.callout).foregroundStyle(.secondary)
                    manualFallback
                }
            }
        }
    }

    private var statusText: String {
        switch updater.phase {
        case .unpacking: return "Unpacking…"
        case .verifying: return "Verifying…"
        case .installing: return "Installing…"
        case .relaunching: return "Relaunching…"
        default: return ""
        }
    }

    private var fallbackReason: String {
        if info.assetURL == nil { return "This release has no downloadable build — install manually:" }
        if case .unsupported(let reason) = target { return reason + " Install manually:" }
        return "Install manually:"
    }

    private var manualFallback: some View {
        HStack {
            Text(installCommand)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(copied ? "Copied" : "Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(installCommand, forType: .string)
                copied = true
            }
            Button("Open Release Page") { NSWorkspace.shared.open(info.releaseURL) }
        }
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if !Task.isCancelled { copied = false }
        }
    }
}
```

- [ ] **Step 3: Verify it builds**

Run: `swift build 2>&1 | tail -20`
Expected: `Build complete!` with no errors.

- [ ] **Step 4: Run the full unit suite**

Run: `swift test 2>&1 | tail -8`
Expected: all tests pass (existing + new Update* tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/Parallel/ParallelApp.swift Sources/Parallel/Views/Sheets/UpdateAvailableSheet.swift
git commit -m "feat(updates): Update Now button + progress UI + manual fallback (#5)"
```

---

## Manual Verification (after Task 5)

Side-effecting paths aren't unit-tested. Verify by hand once:

1. Build a deliberately low-versioned app: `./scripts/build-app.sh 0.0.1`, copy `build/Parallel.app` to `/Applications`, launch it.
2. `Parallel ▸ Check for Updates…` → the sheet shows the current real latest release with **Update Now** enabled.
3. Click **Update Now** → observe download progress → unpacking/verifying/installing/relaunching → app relaunches on the newer version (`Parallel ▸ About`/version reflects it).
4. Dev check: `swift run Parallel`, open the sheet → **Update Now** is replaced by the manual fallback ("development build" reason).

---

## Self-Review Notes

- **Spec coverage:** asset URL parsing (Task 1) ✓; native pipeline download→unpack→verify→swap→relaunch (Tasks 3-4) ✓; in-place target via `UpdateInstallTarget` (Task 2) ✓; HTTPS + version-sanity trust model (Task 4 verify step) ✓; Update Now + progress + Skip/Later/Open + manual fallback (Task 5) ✓; edge cases dev/translocation/non-writable/no-asset (Task 2 + sheet `canUpdateInApp`/`fallbackReason`) ✓; failure leaves app intact (Task 4 `swap` stages before replace, atomic) ✓; tests for the pure pieces (Tasks 1-3) ✓; manual verification for side effects ✓.
- **Type/name consistency:** `UpdateInfo.assetURL: URL?`, `UpdateChecker.selectMacZipAsset(from:)`, `UpdateInstallTarget.resolve(bundleURL:isWritable:)` → `.replaceable(URL)`/`.unsupported(String)`, `Updater.Phase`, `Updater.bundleShortVersion(at:)`, `Updater.update(from:target:session:)`, `Updater.cancel()`, `Updater.phase` — used consistently across tasks and the sheet.
- **Known soft spots:** byte-stream download is simple but not the fastest for multi-MB zips — acceptable for a one-time update; flagged here rather than over-engineering a download delegate. `relaunch` assumes `/bin/sh` + `open` (always present on macOS).
```
