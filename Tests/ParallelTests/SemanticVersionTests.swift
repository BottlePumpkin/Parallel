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

    func test_rejects_double_dot() {
        XCTAssertNil(SemanticVersion("1..2"))
    }

    func test_rejects_trailing_dot() {
        XCTAssertNil(SemanticVersion("1.2."))
    }

    func test_rejects_leading_dot() {
        XCTAssertNil(SemanticVersion(".1.2"))
    }

    func test_hashable_equal_values_hash_equal() {
        var seen: Set<SemanticVersion> = []
        seen.insert(SemanticVersion("1.2")!)
        seen.insert(SemanticVersion("1.2.0")!)
        XCTAssertEqual(seen.count, 1)
    }

    func test_hashable_different_values_hash_different() {
        let s: Set<SemanticVersion> = [SemanticVersion("1.2")!, SemanticVersion("1.2.1")!]
        XCTAssertEqual(s.count, 2)
    }
}
