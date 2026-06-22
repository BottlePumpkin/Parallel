import XCTest
@testable import Parallel

@MainActor
final class UpdateCheckerTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        suiteName = "test.parallel.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        session = StubURLProtocol.session()
        StubURLProtocol.reset()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        UserDefaults().removePersistentDomain(forName: suiteName)
        super.tearDown()
        suiteName = nil
        defaults = nil
        session = nil
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
            return (resp, self.payload(tag: "v0.1.5"))
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
}
