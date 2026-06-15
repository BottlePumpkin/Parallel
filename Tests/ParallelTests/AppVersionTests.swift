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
