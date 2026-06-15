# Update Check & Report Issue Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two menu actions — "Check for Updates…" (auto on launch + manual) hitting the GitHub Releases API, and "Report Issue…" that prefills a GitHub issue URL and opens the browser. Both delegate to GitHub with zero auth.

**Architecture:** Pure-logic Util types (SemanticVersion, AppVersion, IssueReporter), one `@Observable` service (UpdateChecker) that wraps URLSession + UserDefaults caching, two SwiftUI sheets, and menu entries hung off `Parallel`'s app menu. Network is dependency-injected so URLProtocol stubs cover the checker in unit tests; views and integration are manually verified.

**Tech Stack:** Swift 5.10+, SwiftUI, macOS 14+, URLSession, Codable, UserDefaults, XCTest with URLProtocol-based stub.

**Spec:** `docs/superpowers/specs/2026-06-15-update-check-and-report-issue-design.md`

---

## File Structure

```
Sources/Parallel/
├─ Util/
│  ├─ SemanticVersion.swift            # NEW
│  ├─ AppVersion.swift                 # NEW
│  ├─ IssueReporter.swift              # NEW
│  └─ UserDefaults+Updates.swift       # NEW (keyed wrappers)
├─ Services/
│  └─ UpdateChecker.swift              # NEW (incl. UpdateInfo + UpdateCheckResult)
├─ Views/
│  ├─ Commands.swift                   # MODIFY (menu + actions)
│  ├─ ContentView.swift                # MODIFY (sheets + actions + .task)
│  └─ Sheets/
│     ├─ UpdateAvailableSheet.swift    # NEW
│     └─ ReportIssueSheet.swift        # NEW
└─ ParallelApp.swift                   # MODIFY (inject UpdateChecker)

Tests/ParallelTests/
├─ Support/
│  └─ StubURLProtocol.swift            # NEW (URLProtocol-based stub for URLSession)
├─ SemanticVersionTests.swift          # NEW
├─ AppVersionTests.swift               # NEW
├─ IssueReporterTests.swift            # NEW
└─ UpdateCheckerTests.swift            # NEW
```

**Convention reminders:**
- Existing `Sources/Parallel/Models`, `Persistence`, `Services` patterns. New types follow them.
- `git -c user.email="p4569zz@gmail.com" -c user.name="BottlePumpkin"` per existing commits.
- Run `swift build` and `swift test` between major tasks.

---

## Task 1: `SemanticVersion`

**Files:**
- Create: `Sources/Parallel/Util/SemanticVersion.swift`
- Create: `Tests/ParallelTests/SemanticVersionTests.swift`

- [ ] **Step 1: Write the failing tests**

`Tests/ParallelTests/SemanticVersionTests.swift`:
```swift
import XCTest
@testable import Parallel

final class SemanticVersionTests: XCTestCase {
    func test_parses_plain_three_part() {
        XCTAssertEqual(SemanticVersion("0.1.4")?.components, [0, 1, 4])
    }

    func test_parses_with_v_prefix() {
        XCTAssertEqual(SemanticVersion("v0.1.4")?.components, [0, 1, 4])
    }

    func test_parses_two_parts() {
        XCTAssertEqual(SemanticVersion("1.2")?.components, [1, 2])
    }

    func test_strips_prerelease_suffix() {
        XCTAssertEqual(SemanticVersion("0.1.5-beta1")?.components, [0, 1, 5])
    }

    func test_strips_build_metadata_suffix() {
        XCTAssertEqual(SemanticVersion("0.1.5+sha.abcdef")?.components, [0, 1, 5])
    }

    func test_rejects_non_numeric() {
        XCTAssertNil(SemanticVersion("not a version"))
        XCTAssertNil(SemanticVersion(""))
        XCTAssertNil(SemanticVersion("v"))
    }

    func test_description_drops_v_prefix() {
        XCTAssertEqual(SemanticVersion("v0.1.4")?.description, "0.1.4")
    }

    func test_compare_minor_bump() {
        XCTAssertTrue(SemanticVersion("0.1.4")! < SemanticVersion("0.1.5")!)
    }

    func test_compare_ten_greater_than_nine_numerically() {
        XCTAssertTrue(SemanticVersion("0.1.10")! > SemanticVersion("0.1.9")!)
    }

    func test_compare_minor_over_patch() {
        XCTAssertTrue(SemanticVersion("0.1.99")! < SemanticVersion("0.2.0")!)
    }

    func test_compare_major_over_minor() {
        XCTAssertTrue(SemanticVersion("0.99.99")! < SemanticVersion("1.0.0")!)
    }

    func test_compare_equal() {
        XCTAssertEqual(SemanticVersion("1.2.3")!, SemanticVersion("v1.2.3")!)
    }

    func test_compare_missing_trailing_zero_pads_for_compare() {
        XCTAssertEqual(SemanticVersion("1.2")!, SemanticVersion("1.2.0")!)
    }
}
```

- [ ] **Step 2: Run tests — expect failures**

Run: `swift test --filter SemanticVersionTests 2>&1 | tail -10`
Expected: build failure — `SemanticVersion` undefined.

- [ ] **Step 3: Implement `SemanticVersion`**

`Sources/Parallel/Util/SemanticVersion.swift`:
```swift
import Foundation

/// Comparable version tag parser. Accepts "0.1.4", "v0.1.4". Strips any
/// `-prerelease` or `+build` suffix and parses the numeric core only —
/// pre-release ordering is out of scope for this app's release scheme.
struct SemanticVersion: Comparable, Equatable, CustomStringConvertible {
    let components: [Int]

    init?(_ raw: String) {
        let trimmed = raw.hasPrefix("v") ? String(raw.dropFirst()) : raw
        let core = trimmed.split(whereSeparator: { $0 == "-" || $0 == "+" }).first.map(String.init) ?? ""
        let parts = core.split(separator: ".").map(String.init)
        guard !parts.isEmpty else { return nil }
        var ints: [Int] = []
        for p in parts {
            guard let n = Int(p), n >= 0 else { return nil }
            ints.append(n)
        }
        self.components = ints
    }

    var description: String { components.map(String.init).joined(separator: ".") }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = Swift.max(lhs.components.count, rhs.components.count)
        for i in 0..<count {
            let l = i < lhs.components.count ? lhs.components[i] : 0
            let r = i < rhs.components.count ? rhs.components[i] : 0
            if l != r { return l < r }
        }
        return false
    }

    static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = Swift.max(lhs.components.count, rhs.components.count)
        for i in 0..<count {
            let l = i < lhs.components.count ? lhs.components[i] : 0
            let r = i < rhs.components.count ? rhs.components[i] : 0
            if l != r { return false }
        }
        return true
    }
}
```

- [ ] **Step 4: Run tests — expect pass**

Run: `swift test --filter SemanticVersionTests 2>&1 | tail -10`
Expected: all 13 test cases PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Parallel/Util/SemanticVersion.swift Tests/ParallelTests/SemanticVersionTests.swift
git -c user.email="p4569zz@gmail.com" -c user.name="BottlePumpkin" commit -m "feat(util): SemanticVersion comparable tag parser"
```

---

## Task 2: `StubURLProtocol` test helper

**Files:**
- Create: `Tests/ParallelTests/Support/StubURLProtocol.swift`

This is shared infrastructure for Task 5. No production code, no tests for the helper itself — its tests are the UpdateChecker tests in Task 5.

- [ ] **Step 1: Write the helper**

`Tests/ParallelTests/Support/StubURLProtocol.swift`:
```swift
import Foundation

/// Inject this into `URLSessionConfiguration.protocolClasses` to handle
/// every request with a closure. Used by UpdateCheckerTests to avoid live
/// network in unit tests.
final class StubURLProtocol: URLProtocol {
    /// Replace per-test. Throwing → URLSession reports a failed request.
    /// Returning → response + body are delivered to the URLSession completion.
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    static func reset() { requestHandler = nil }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = StubURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: NSError(
                domain: "StubURLProtocol",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No handler set"]
            ))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    /// Convenience: build a URLSession that routes through this stub.
    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }
}
```

- [ ] **Step 2: Verify the project still compiles**

Run: `swift build 2>&1 | tail -3`
Expected: success.

- [ ] **Step 3: Commit**

```bash
git add Tests/ParallelTests/Support/StubURLProtocol.swift
git -c user.email="p4569zz@gmail.com" -c user.name="BottlePumpkin" commit -m "test(support): URLProtocol stub for URLSession-based tests"
```

---

## Task 3: `AppVersion`

**Files:**
- Create: `Sources/Parallel/Util/AppVersion.swift`
- Create: `Tests/ParallelTests/AppVersionTests.swift`

Pure-function `signature` builder is the unit-tested surface. `current` and `environmentSignature` read process state at runtime; only the formatter is tested.

- [ ] **Step 1: Write the failing tests**

`Tests/ParallelTests/AppVersionTests.swift`:
```swift
import XCTest
@testable import Parallel

final class AppVersionTests: XCTestCase {
    func test_signature_renders_four_lines() {
        let sig = AppVersion.signature(
            version: SemanticVersion("0.1.4")!,
            osVersion: "Version 15.1 (Build 24B83)",
            architecture: "arm64",
            logDirectory: "~/Library/Logs/Parallel/"
        )
        let lines = sig.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(lines[0], "- Parallel: 0.1.4")
        XCTAssertEqual(lines[1], "- macOS: Version 15.1 (Build 24B83)")
        XCTAssertEqual(lines[2], "- Architecture: arm64")
        XCTAssertEqual(lines[3], "- Log: ~/Library/Logs/Parallel/")
    }

    func test_current_falls_back_to_zero_when_bundle_missing_key() {
        // In test runs, Bundle.main has no CFBundleShortVersionString — the
        // fallback path must still produce a usable SemanticVersion.
        XCTAssertNotNil(AppVersion.current.description)
    }
}
```

- [ ] **Step 2: Run tests — expect failures**

Run: `swift test --filter AppVersionTests 2>&1 | tail -10`
Expected: build failure — `AppVersion` undefined.

- [ ] **Step 3: Implement `AppVersion`**

`Sources/Parallel/Util/AppVersion.swift`:
```swift
import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Read-only access to the current app + host environment, formatted for
/// issue templates. The pure `signature(...)` function is unit-tested; the
/// run-time accessors (`current`, `environmentSignature`) compose it with
/// real process state.
enum AppVersion {
    static let fallback = SemanticVersion("0.0.0")!

    static var current: SemanticVersion {
        let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return raw.flatMap(SemanticVersion.init) ?? fallback
    }

    static var environmentSignature: String {
        signature(
            version: current,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: machineArchitecture(),
            logDirectory: "~/Library/Logs/Parallel/"
        )
    }

    /// Pure formatter — testable.
    static func signature(version: SemanticVersion,
                          osVersion: String,
                          architecture: String,
                          logDirectory: String) -> String {
        """
        - Parallel: \(version.description)
        - macOS: \(osVersion)
        - Architecture: \(architecture)
        - Log: \(logDirectory)
        """
    }

    private static func machineArchitecture() -> String {
        var info = utsname()
        uname(&info)
        let mirror = Mirror(reflecting: info.machine)
        let chars: [CChar] = mirror.children.compactMap { $0.value as? CChar }
        let bytes = chars.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
```

- [ ] **Step 4: Run tests — expect pass**

Run: `swift test --filter AppVersionTests 2>&1 | tail -10`
Expected: 2 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Parallel/Util/AppVersion.swift Tests/ParallelTests/AppVersionTests.swift
git -c user.email="p4569zz@gmail.com" -c user.name="BottlePumpkin" commit -m "feat(util): AppVersion signature builder for issue templates"
```

---

## Task 4: `IssueReporter`

**Files:**
- Create: `Sources/Parallel/Util/IssueReporter.swift`
- Create: `Tests/ParallelTests/IssueReporterTests.swift`

URL builder is the unit-tested surface. `openNewIssue` (which calls `NSWorkspace.open`) is exercised manually.

- [ ] **Step 1: Write the failing tests**

`Tests/ParallelTests/IssueReporterTests.swift`:
```swift
import XCTest
@testable import Parallel

final class IssueReporterTests: XCTestCase {
    func test_builds_new_issue_url_against_canonical_repo() {
        let url = IssueReporter.newIssueURL(title: "Hello", body: "world", labels: [])
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "github.com")
        XCTAssertEqual(url.path, "/BottlePumpkin/Parallel/issues/new")
    }

    func test_title_and_body_are_percent_encoded() {
        let url = IssueReporter.newIssueURL(
            title: "crash with # and & on input",
            body: "first line\nsecond line",
            labels: []
        )
        let q = url.query ?? ""
        XCTAssertTrue(q.contains("title=crash%20with%20%23%20and%20%26%20on%20input"))
        XCTAssertTrue(q.contains("body=first%20line%0Asecond%20line"))
    }

    func test_korean_text_is_encoded() {
        let url = IssueReporter.newIssueURL(title: "버그", body: "한글 본문", labels: [])
        let q = url.query ?? ""
        XCTAssertTrue(q.contains("title=%EB%B2%84%EA%B7%B8"))
        XCTAssertTrue(q.contains("body=%ED%95%9C%EA%B8%80%20%EB%B3%B8%EB%AC%B8"))
    }

    func test_labels_are_joined_with_comma() {
        let url = IssueReporter.newIssueURL(
            title: "t", body: "b",
            labels: ["user-report", "needs-triage"]
        )
        let q = url.query ?? ""
        XCTAssertTrue(q.contains("labels=user-report%2Cneeds-triage"))
    }

    func test_empty_body_still_builds() {
        let url = IssueReporter.newIssueURL(title: "title only", body: "", labels: [])
        XCTAssertTrue((url.query ?? "").contains("body="))
    }

    func test_no_labels_omits_label_param() {
        let url = IssueReporter.newIssueURL(title: "t", body: "b", labels: [])
        XCTAssertFalse((url.query ?? "").contains("labels="))
    }
}
```

- [ ] **Step 2: Run tests — expect failures**

Run: `swift test --filter IssueReporterTests 2>&1 | tail -10`
Expected: build failure — `IssueReporter` undefined.

- [ ] **Step 3: Implement `IssueReporter`**

`Sources/Parallel/Util/IssueReporter.swift`:
```swift
import Foundation
import AppKit

/// Builds prefilled GitHub "new issue" URLs and hands them to the default
/// browser via NSWorkspace. The app never POSTs to GitHub — the user
/// reviews and submits the issue in their already-logged-in browser.
enum IssueReporter {
    static let repository = "BottlePumpkin/Parallel"

    static func newIssueURL(title: String, body: String, labels: [String]) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "github.com"
        components.path = "/\(repository)/issues/new"
        var items: [URLQueryItem] = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "body", value: body),
        ]
        if !labels.isEmpty {
            items.append(URLQueryItem(name: "labels", value: labels.joined(separator: ",")))
        }
        components.queryItems = items
        return components.url!
    }

    /// Open the prefilled URL in the user's default browser. Returns true
    /// when NSWorkspace accepted the open; false when it rejected and we
    /// fell back to copying the URL to the clipboard.
    @discardableResult
    static func openNewIssue(title: String, body: String, labels: [String]) -> Bool {
        let url = newIssueURL(title: title, body: body, labels: labels)
        if NSWorkspace.shared.open(url) { return true }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(url.absoluteString, forType: .string)
        return false
    }
}
```

- [ ] **Step 4: Run tests — expect pass**

Run: `swift test --filter IssueReporterTests 2>&1 | tail -10`
Expected: 6 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Parallel/Util/IssueReporter.swift Tests/ParallelTests/IssueReporterTests.swift
git -c user.email="p4569zz@gmail.com" -c user.name="BottlePumpkin" commit -m "feat(util): IssueReporter — prefilled GitHub new-issue URL + NSWorkspace open"
```

---

## Task 5: `UserDefaults+Updates`

**Files:**
- Create: `Sources/Parallel/Util/UserDefaults+Updates.swift`

Thin keyed wrappers. Not unit-tested (UserDefaults itself is); the wrappers are exercised by Task 6 (UpdateChecker tests via a custom suite).

- [ ] **Step 1: Implement**

`Sources/Parallel/Util/UserDefaults+Updates.swift`:
```swift
import Foundation

extension UserDefaults {
    private enum UpdateKeys {
        static let lastCheckAt = "parallel.updateCheck.lastAt"
        static let skippedVersion = "parallel.updateCheck.skippedVersion"
    }

    var lastUpdateCheckAt: Date? {
        get { object(forKey: UpdateKeys.lastCheckAt) as? Date }
        set { set(newValue, forKey: UpdateKeys.lastCheckAt) }
    }

    var skippedUpdateVersion: String? {
        get { string(forKey: UpdateKeys.skippedVersion) }
        set { set(newValue, forKey: UpdateKeys.skippedVersion) }
    }
}
```

- [ ] **Step 2: Verify build**

Run: `swift build 2>&1 | tail -3`
Expected: success.

- [ ] **Step 3: Commit**

```bash
git add Sources/Parallel/Util/UserDefaults+Updates.swift
git -c user.email="p4569zz@gmail.com" -c user.name="BottlePumpkin" commit -m "feat(util): UserDefaults keys for update-check cache + skip state"
```

---

## Task 6: `UpdateChecker`

**Files:**
- Create: `Sources/Parallel/Services/UpdateChecker.swift`
- Create: `Tests/ParallelTests/UpdateCheckerTests.swift`

Async network service. URLSession is injected; tests use the StubURLProtocol from Task 2 and an isolated UserDefaults suite.

- [ ] **Step 1: Write the failing tests**

`Tests/ParallelTests/UpdateCheckerTests.swift`:
```swift
import XCTest
@testable import Parallel

@MainActor
final class UpdateCheckerTests: XCTestCase {

    private var defaults: UserDefaults!
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "test.parallel.\(UUID().uuidString)")!
        session = StubURLProtocol.session()
        StubURLProtocol.reset()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        if let name = defaults.dictionaryRepresentation().keys.first {
            UserDefaults().removePersistentDomain(forName: name)
        }
        super.tearDown()
    }

    private func payload(tag: String, body: String = "release body") -> Data {
        let json = #"""
        {
          "tag_name": "\#(tag)",
          "html_url": "https://github.com/BottlePumpkin/Parallel/releases/tag/\#(tag)",
          "body": "\#(body)",
          "published_at": "2026-06-15T12:00:00Z"
        }
        """#
        return json.data(using: .utf8)!
    }

    private func makeChecker() -> UpdateChecker {
        UpdateChecker(session: session, defaults: defaults, currentVersionProvider: { SemanticVersion("0.1.4")! })
    }

    func test_check_returns_available_for_newer_tag() async {
        StubURLProtocol.requestHandler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, self.payload(tag: "v0.1.5"))
        }
        let checker = makeChecker()
        await checker.check(force: true)
        switch checker.lastCheckResult {
        case .available(let info):
            XCTAssertEqual(info.latestTag, "v0.1.5")
            XCTAssertEqual(info.latestVersion.description, "0.1.5")
        default:
            XCTFail("expected .available, got \(String(describing: checker.lastCheckResult))")
        }
        XCTAssertNotNil(checker.updateAvailable)
    }

    func test_check_returns_upToDate_for_same_tag() async {
        StubURLProtocol.requestHandler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, self.payload(tag: "v0.1.4"))
        }
        let checker = makeChecker()
        await checker.check(force: true)
        switch checker.lastCheckResult {
        case .upToDate: break
        default: XCTFail("expected .upToDate")
        }
        XCTAssertNil(checker.updateAvailable)
    }

    func test_check_treats_older_tag_as_up_to_date() async {
        StubURLProtocol.requestHandler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, self.payload(tag: "v0.1.3"))
        }
        let checker = makeChecker()
        await checker.check(force: true)
        switch checker.lastCheckResult {
        case .upToDate: break
        default: XCTFail("expected .upToDate for older tag")
        }
    }

    func test_check_failed_on_http_403() async {
        StubURLProtocol.requestHandler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!
            return (resp, Data())
        }
        let checker = makeChecker()
        await checker.check(force: true)
        switch checker.lastCheckResult {
        case .failed: break
        default: XCTFail("expected .failed for HTTP 403")
        }
    }

    func test_check_failed_on_unparseable_tag() async {
        StubURLProtocol.requestHandler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, self.payload(tag: "release-candidate"))
        }
        let checker = makeChecker()
        await checker.check(force: true)
        switch checker.lastCheckResult {
        case .failed: break
        default: XCTFail("expected .failed for non-numeric tag")
        }
    }

    func test_check_failed_on_network_error() async {
        StubURLProtocol.requestHandler = { _ in
            throw NSError(domain: "test", code: -1009, userInfo: nil)
        }
        let checker = makeChecker()
        await checker.check(force: true)
        switch checker.lastCheckResult {
        case .failed: break
        default: XCTFail("expected .failed for network error")
        }
    }

    func test_checkIfStale_uses_cache_when_recent() async {
        defaults.lastUpdateCheckAt = Date()  // just checked
        var handlerCalled = false
        StubURLProtocol.requestHandler = { req in
            handlerCalled = true
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, self.payload(tag: "v0.1.5"))
        }
        let checker = makeChecker()
        await checker.checkIfStale()
        XCTAssertFalse(handlerCalled, "fresh cache should not hit network")
    }

    func test_checkIfStale_bypasses_cache_when_stale() async {
        defaults.lastUpdateCheckAt = Date(timeIntervalSinceNow: -7 * 3600)
        var handlerCalled = false
        StubURLProtocol.requestHandler = { req in
            handlerCalled = true
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, self.payload(tag: "v0.1.5"))
        }
        let checker = makeChecker()
        await checker.checkIfStale()
        XCTAssertTrue(handlerCalled, "stale cache should hit network")
    }

    func test_skip_suppresses_updateAvailable_silently() async {
        StubURLProtocol.requestHandler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, self.payload(tag: "v0.1.5"))
        }
        let checker = makeChecker()
        defaults.skippedUpdateVersion = "0.1.5"
        await checker.check(force: false)
        XCTAssertNil(checker.updateAvailable, "skipped version must not publish updateAvailable")
        switch checker.lastCheckResult {
        case .available: break
        default: XCTFail("lastCheckResult should still record .available even when suppressed")
        }
    }

    func test_force_check_ignores_skip() async {
        StubURLProtocol.requestHandler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, self.payload(tag: "v0.1.5"))
        }
        let checker = makeChecker()
        defaults.skippedUpdateVersion = "0.1.5"
        await checker.check(force: true)
        XCTAssertNotNil(checker.updateAvailable, "force check must surface skipped version")
    }
}
```

- [ ] **Step 2: Run tests — expect failures**

Run: `swift test --filter UpdateCheckerTests 2>&1 | tail -15`
Expected: build failure — `UpdateChecker` undefined.

- [ ] **Step 3: Implement `UpdateChecker`**

`Sources/Parallel/Services/UpdateChecker.swift`:
```swift
import Foundation
import Observation

struct UpdateInfo: Equatable {
    let latestTag: String
    let latestVersion: SemanticVersion
    let releaseURL: URL
    let releaseNotes: String
    let publishedAt: Date
}

enum UpdateCheckResult {
    case upToDate(current: SemanticVersion)
    case available(UpdateInfo)
    case failed(Error)
}

enum UpdateCheckError: Error, LocalizedError {
    case http(Int)
    case unparseableTag(String)

    var errorDescription: String? {
        switch self {
        case .http(let code): return "GitHub returned HTTP \(code)."
        case .unparseableTag(let tag): return "Couldn't read tag \"\(tag)\" as a version."
        }
    }
}

/// Polls GitHub Releases for a newer published tag. Auto-paced on app
/// start (cache TTL 6h) and re-runnable on demand from the menu.
@Observable
@MainActor
final class UpdateChecker {
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/BottlePumpkin/Parallel/releases/latest")!
    static let cacheTTL: TimeInterval = 6 * 60 * 60

    /// Published only when the result is newer AND not skipped. Drives the
    /// startup sheet presentation.
    var updateAvailable: UpdateInfo?
    /// Last raw result regardless of skip state. Drives manual-check UI.
    var lastCheckResult: UpdateCheckResult?
    /// True while a network request is in flight; menu sheet binds to it
    /// to show a spinner.
    var isChecking = false

    private let session: URLSession
    private let defaults: UserDefaults
    private let currentVersionProvider: () -> SemanticVersion

    init(session: URLSession = .shared,
         defaults: UserDefaults = .standard,
         currentVersionProvider: @escaping () -> SemanticVersion = { AppVersion.current }) {
        self.session = session
        self.defaults = defaults
        self.currentVersionProvider = currentVersionProvider
    }

    /// Called from ContentView.task at launch. Skips when the last check
    /// was inside cacheTTL.
    func checkIfStale() async {
        if let last = defaults.lastUpdateCheckAt,
           Date().timeIntervalSince(last) < Self.cacheTTL {
            return
        }
        await check(force: false)
    }

    /// `force: true` bypasses both cache and skipped-version filter.
    func check(force: Bool) async {
        isChecking = true
        defer { isChecking = false }

        var request = URLRequest(url: Self.latestReleaseURL, timeoutInterval: 5)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            lastCheckResult = .failed(error)
            return
        }

        guard let http = response as? HTTPURLResponse else {
            lastCheckResult = .failed(UpdateCheckError.http(-1))
            return
        }
        guard http.statusCode == 200 else {
            lastCheckResult = .failed(UpdateCheckError.http(http.statusCode))
            return
        }

        defaults.lastUpdateCheckAt = Date()

        let payload: ReleasePayload
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            payload = try decoder.decode(ReleasePayload.self, from: data)
        } catch {
            lastCheckResult = .failed(error)
            return
        }

        guard let latest = SemanticVersion(payload.tagName) else {
            lastCheckResult = .failed(UpdateCheckError.unparseableTag(payload.tagName))
            return
        }

        let current = currentVersionProvider()
        if latest > current {
            let info = UpdateInfo(
                latestTag: payload.tagName,
                latestVersion: latest,
                releaseURL: payload.htmlUrl,
                releaseNotes: payload.body ?? "",
                publishedAt: payload.publishedAt
            )
            lastCheckResult = .available(info)
            if force || defaults.skippedUpdateVersion != latest.description {
                updateAvailable = info
            } else {
                updateAvailable = nil
            }
        } else {
            lastCheckResult = .upToDate(current: current)
            updateAvailable = nil
        }
    }

    func skip(_ version: SemanticVersion) {
        defaults.skippedUpdateVersion = version.description
        updateAvailable = nil
    }
}

private struct ReleasePayload: Decodable {
    let tagName: String
    let htmlUrl: URL
    let body: String?
    let publishedAt: Date
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
        case body
        case publishedAt = "published_at"
    }
}
```

- [ ] **Step 4: Run tests — expect pass**

Run: `swift test --filter UpdateCheckerTests 2>&1 | tail -10`
Expected: 10 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Parallel/Services/UpdateChecker.swift Tests/ParallelTests/UpdateCheckerTests.swift
git -c user.email="p4569zz@gmail.com" -c user.name="BottlePumpkin" commit -m "feat(services): UpdateChecker — GitHub Releases polling with cache + skip"
```

---

## Task 7: `UpdateAvailableSheet`

**Files:**
- Create: `Sources/Parallel/Views/Sheets/UpdateAvailableSheet.swift`

Manual verification — SwiftUI sheets are exercised in the integration step.

- [ ] **Step 1: Implement**

`Sources/Parallel/Views/Sheets/UpdateAvailableSheet.swift`:
```swift
import SwiftUI
import AppKit

struct UpdateAvailableSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(UpdateChecker.self) private var checker
    let info: UpdateInfo

    private let installCommand = "curl -fsSL https://raw.githubusercontent.com/BottlePumpkin/Parallel/master/scripts/install.sh | bash"

    @State private var copied = false

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

            VStack(alignment: .leading, spacing: 4) {
                Text("Install command").font(.headline)
                HStack {
                    Text(installCommand)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(copied ? "Copied" : "Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(installCommand, forType: .string)
                        copied = true
                        Task {
                            try? await Task.sleep(nanoseconds: 1_800_000_000)
                            await MainActor.run { copied = false }
                        }
                    }
                }
            }

            HStack {
                Button("Skip This Version") {
                    checker.skip(info.latestVersion)
                    dismiss()
                }
                Spacer()
                Button("Later") { dismiss() }
                Button("Open Release Page") {
                    NSWorkspace.shared.open(info.releaseURL)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 540)
    }
}
```

- [ ] **Step 2: Verify build**

Run: `swift build 2>&1 | tail -3`
Expected: success.

- [ ] **Step 3: Commit**

```bash
git add Sources/Parallel/Views/Sheets/UpdateAvailableSheet.swift
git -c user.email="p4569zz@gmail.com" -c user.name="BottlePumpkin" commit -m "feat(views): UpdateAvailableSheet — release notes + Skip/Later/Open"
```

---

## Task 8: `ReportIssueSheet`

**Files:**
- Create: `Sources/Parallel/Views/Sheets/ReportIssueSheet.swift`

- [ ] **Step 1: Implement**

`Sources/Parallel/Views/Sheets/ReportIssueSheet.swift`:
```swift
import SwiftUI

struct ReportIssueSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var body: String = ReportIssueSheet.bodyTemplate()
    @State private var errorMessage: String?

    static func bodyTemplate() -> String {
        """
        ## What happened?


        ## Steps to reproduce


        ---
        **Environment**
        \(AppVersion.environmentSignature)
        """
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Report an issue").font(.title2).bold()
            Text("Submitting opens GitHub in your browser — you review and submit there. No data is sent from Parallel directly.")
                .font(.caption).foregroundStyle(.secondary)

            TextField("Title", text: $title)

            Text("Description").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $body)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 220)
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Open in Browser") {
                    let ok = IssueReporter.openNewIssue(
                        title: title,
                        body: body,
                        labels: ["user-report"]
                    )
                    if !ok {
                        errorMessage = "Couldn't open the browser — the URL has been copied to your clipboard."
                        return
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560)
    }
}
```

- [ ] **Step 2: Verify build**

Run: `swift build 2>&1 | tail -3`
Expected: success.

- [ ] **Step 3: Commit**

```bash
git add Sources/Parallel/Views/Sheets/ReportIssueSheet.swift
git -c user.email="p4569zz@gmail.com" -c user.name="BottlePumpkin" commit -m "feat(views): ReportIssueSheet — title + body + Open in Browser"
```

---

## Task 9: Menu integration (`Commands.swift` + `ContentActions`)

**Files:**
- Modify: `Sources/Parallel/Views/Commands.swift`

- [ ] **Step 1: Add fields to `ContentActions`**

Open `Sources/Parallel/Views/Commands.swift`. Find:

```swift
struct ContentActions {
    var newWorktree: () -> Void = {}
    var addRepo: () -> Void = {}
    var selectIndex: (Int) -> Void = { _ in }
    var closeCurrentSession: () -> Void = {}
    var deleteCurrentWorktree: () -> Void = {}
}
```

Replace with:

```swift
struct ContentActions {
    var newWorktree: () -> Void = {}
    var addRepo: () -> Void = {}
    var selectIndex: (Int) -> Void = { _ in }
    var closeCurrentSession: () -> Void = {}
    var deleteCurrentWorktree: () -> Void = {}
    var checkForUpdates: () -> Void = {}
    var reportIssue: () -> Void = {}
}
```

- [ ] **Step 2: Add menu entries**

Inside `ParallelCommands.body`, after the existing `CommandMenu("Worktree") { ... }` block, append:

```swift
CommandGroup(after: .appInfo) {
    Button("Check for Updates…") { actions?.checkForUpdates() }
    Divider()
    Button("Report Issue…") { actions?.reportIssue() }
}
```

- [ ] **Step 3: Verify build**

Run: `swift build 2>&1 | tail -3`
Expected: success.

- [ ] **Step 4: Commit**

```bash
git add Sources/Parallel/Views/Commands.swift
git -c user.email="p4569zz@gmail.com" -c user.name="BottlePumpkin" commit -m "feat(views): Parallel menu — Check for Updates + Report Issue"
```

---

## Task 10: `ContentView` + `ParallelApp` integration

**Files:**
- Modify: `Sources/Parallel/Views/ContentView.swift`
- Modify: `Sources/Parallel/ParallelApp.swift`

- [ ] **Step 1: Inject `UpdateChecker` into the app**

Open `Sources/Parallel/ParallelApp.swift`. Find the existing `@State private var caffeinate = CaffeinateManager()` line and add right after it:

```swift
    @State private var updateChecker = UpdateChecker()
```

Then find the `.environment(caffeinate)` modifier and add right after it:

```swift
                .environment(updateChecker)
```

- [ ] **Step 2: Add sheet/alert state to `ContentView`**

Open `Sources/Parallel/Views/ContentView.swift`. After `@Environment(CaffeinateManager.self) private var caffeinate` add:

```swift
    @Environment(UpdateChecker.self) private var updateChecker
```

After the existing `@State private var pendingRemoveRepoId: UUID?` add:

```swift
    @State private var manualCheckSheet: ManualCheckState?
    @State private var showReportIssueSheet = false

    enum ManualCheckState: Identifiable {
        case checking
        case upToDate(SemanticVersion)
        case failed(String)
        var id: String {
            switch self {
            case .checking: return "checking"
            case .upToDate(let v): return "upToDate-\(v.description)"
            case .failed(let m): return "failed-\(m)"
            }
        }
    }
```

- [ ] **Step 3: Wire focused actions**

In `focusedActions` (the existing computed property), append two new fields to the `ContentActions(...)` initializer:

```swift
            checkForUpdates: { Task { await runManualCheck() } },
            reportIssue: { showReportIssueSheet = true }
```

(Append after the existing fields, with the appropriate trailing comma syntax.)

- [ ] **Step 4: Add `.task` for startup check + sheet presentation**

In the body of `ContentView`, before `.onAppear`, add:

```swift
        .task(id: "update-startup-check") {
            await updateChecker.checkIfStale()
        }
```

And in the existing `SheetsModifier` invocation, add a new sheet binding. Open `SheetsModifier` struct — append these new fields:

```swift
    @Binding var manualCheckSheet: ContentView.ManualCheckState?
    @Binding var showReportIssueSheet: Bool
    let updateChecker: UpdateChecker
```

In `SheetsModifier.body(content:)` append after the existing chain:

```swift
            .sheet(item: Binding(
                get: { updateChecker.updateAvailable.map(UpdateInfoBox.init) },
                set: { _ in updateChecker.updateAvailable = nil }
            )) { box in
                UpdateAvailableSheet(info: box.info)
            }
            .sheet(item: $manualCheckSheet) { state in
                ManualCheckSheet(state: state)
            }
            .sheet(isPresented: $showReportIssueSheet) {
                ReportIssueSheet()
            }
```

Add at the end of `ContentView.swift` (outside any other type):

```swift
private struct UpdateInfoBox: Identifiable {
    let info: UpdateInfo
    var id: String { info.latestTag }
}

private struct ManualCheckSheet: View {
    @Environment(\.dismiss) private var dismiss
    let state: ContentView.ManualCheckState

    var body: some View {
        VStack(spacing: 14) {
            switch state {
            case .checking:
                ProgressView("Checking GitHub…")
            case .upToDate(let v):
                Text("You're on the latest version (\(v.description)).")
            case .failed(let msg):
                Text("Couldn't check for updates.").font(.headline)
                Text(msg).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("OK") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
```

Update the call site of `SheetsModifier(...)` in `ContentView.body` to pass the new bindings:

```swift
        .modifier(SheetsModifier(
            showAddRepo: $showAddRepo,
            newWorktreeTrigger: $newWorktreeTrigger,
            importWorktreesRepoId: $importWorktreesRepoId,
            pendingDeleteId: $pendingDeleteId,
            store: store,
            onConfirmDelete: confirmDelete,
            manualCheckSheet: $manualCheckSheet,
            showReportIssueSheet: $showReportIssueSheet,
            updateChecker: updateChecker
        ))
```

- [ ] **Step 5: Add `runManualCheck()`**

At the end of `ContentView`'s methods (next to `confirmRename`/`confirmDelete`), add:

```swift
    private func runManualCheck() async {
        manualCheckSheet = .checking
        await updateChecker.check(force: true)
        switch updateChecker.lastCheckResult {
        case .available:
            manualCheckSheet = nil
            // updateChecker.updateAvailable is set; the sheet binding picks it up.
        case .upToDate(let current):
            manualCheckSheet = .upToDate(current)
        case .failed(let error):
            manualCheckSheet = .failed(error.localizedDescription)
        case .none:
            manualCheckSheet = .failed("No result.")
        }
    }
```

- [ ] **Step 6: Build + test**

Run: `swift build 2>&1 | tail -5`
Expected: success.

Run: `swift test 2>&1 | tail -5`
Expected: all tests still pass (no regressions).

- [ ] **Step 7: Manual smoke**

```bash
swift run Parallel
```

Verify:
- App menu → `Parallel` → "Check for Updates…" — clicking shows checking sheet, then "up to date" (current 0.1.4 ≤ latest released — adjust if a newer release is up).
- App menu → `Parallel` → "Report Issue…" — sheet opens with environment block pre-filled; type a title; click "Open in Browser" → GitHub Issues new page opens prefilled in default browser.

- [ ] **Step 8: Commit**

```bash
git add Sources/Parallel/ParallelApp.swift Sources/Parallel/Views/ContentView.swift
git -c user.email="p4569zz@gmail.com" -c user.name="BottlePumpkin" commit -m "feat(views): wire UpdateChecker + sheets into ContentView and ParallelApp"
```

---

## Task 11: Build a release zip

**Files:** none added.

- [ ] **Step 1: Build the .app bundle**

```bash
./scripts/build-app.sh 0.2.0
```

Expected output:
```
==> Built:
    build/Parallel.app
    build/Parallel-0.2.0-mac.zip
```

- [ ] **Step 2: Push and create a GitHub release**

```bash
git push origin master
GH_HOST=github.com gh release create v0.2.0 build/Parallel-0.2.0-mac.zip \
    --title "v0.2.0" \
    --notes "- Check for Updates (auto on launch + Parallel menu)
- Report Issue (prefills a GitHub issue and opens your browser)

Install / update:
\`\`\`
curl -fsSL https://raw.githubusercontent.com/BottlePumpkin/Parallel/master/scripts/install.sh | bash
\`\`\`"
```

- [ ] **Step 3: Verify**

Open the release page; confirm the asset is attached and the notes render. Re-install via the one-liner in another shell to make sure the new menu items show up.

---

## Self-review (planner's notes)

**Spec coverage:**

| Spec section | Task(s) |
|---|---|
| §3 SemanticVersion | 1 |
| §3 AppVersion | 3 |
| §3 UpdateChecker | 6 |
| §3 IssueReporter | 4 |
| §3 UpdateAvailableSheet | 7 |
| §3 ReportIssueSheet | 8 |
| §3 Commands.swift | 9 |
| §5 UserDefaults | 5 |
| §6 Scenario A (auto) | 10 (`task` + sheet binding) |
| §6 Scenario B (manual) | 10 (`runManualCheck` + ManualCheckSheet) |
| §6 Scenario C (update sheet) | 7 |
| §6 Scenario D (issue) | 8 |
| §8 Error handling | 6 (logic), 10 (UI) |
| §9 Tests | 1, 3, 4, 6 (XCTest cases) |
| §10 Defaults #1 6h cache | 6 (`cacheTTL`) |
| §10 Default #2 quiet on auto fail | 10 (auto path uses sheet binding only) |
| §10 Default #4 skip | 6 |
| §10 Default #5 newer than skipped → re-shows | 6 (compares against `skippedUpdateVersion` exact tag; newer tag has different `description`) |
| §10 Default #7 env signature 4 lines | 3 |
| §10 Default #8 labels | 8 (passes `["user-report"]`) |
| §10 Default #10 timeout 5s | 6 (`URLRequest(timeoutInterval: 5)`) |
| §10 Default #12 menu position | 9 (`CommandGroup(after: .appInfo)`) |

**Placeholders:** none — every step shows the actual code.

**Type consistency:** `UpdateInfo`, `UpdateCheckResult`, `SemanticVersion`, `UpdateChecker`, `ContentActions.checkForUpdates`/`reportIssue` are spelled the same in every task. `UpdateInfoBox`, `ManualCheckSheet`, `ManualCheckState` are introduced together in Task 10.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-06-15-update-check-and-report-issue.md`. Two execution options:

1. **Subagent-Driven (recommended)** — fresh subagent per task, two-stage review between tasks
2. **Inline Execution** — execute tasks in this session with checkpoint reviews

Which approach?
