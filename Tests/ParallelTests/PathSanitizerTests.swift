import XCTest
@testable import Parallel

final class PathSanitizerTests: XCTestCase {
    func test_replacesSlashesWithDash() {
        XCTAssertEqual(PathSanitizer.sanitize("feature/MNT-3625"), "feature-MNT-3625")
    }

    func test_collapsesWhitespace() {
        XCTAssertEqual(PathSanitizer.sanitize("feat  foo"), "feat-foo")
    }

    func test_stripsDangerousChars() {
        XCTAssertEqual(PathSanitizer.sanitize("feat:foo*bar?"), "feat-foo-bar")
    }

    func test_collapsesConsecutiveDashes() {
        XCTAssertEqual(PathSanitizer.sanitize("feat//bar"), "feat-bar")
    }

    func test_trimsLeadingTrailingDashes() {
        XCTAssertEqual(PathSanitizer.sanitize("/feat/"), "feat")
    }
}
