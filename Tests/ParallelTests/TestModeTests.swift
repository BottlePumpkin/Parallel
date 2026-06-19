import XCTest
import Foundation
@testable import Parallel

final class TestModeTests: XCTestCase {
    func testIsE2ETrueOnlyForFlagOne() {
        XCTAssertTrue(TestMode.isE2E(["PARALLEL_E2E": "1"]))
        XCTAssertFalse(TestMode.isE2E([:]))
        XCTAssertFalse(TestMode.isE2E(["PARALLEL_E2E": "0"]))
    }

    func testSupportDirectoryNilWhenUnsetOrEmpty() {
        XCTAssertNil(TestMode.supportDirectory([:]))
        XCTAssertNil(TestMode.supportDirectory(["PARALLEL_SUPPORT_DIR": ""]))
    }

    func testSupportDirectoryParsesPath() {
        let url = TestMode.supportDirectory(["PARALLEL_SUPPORT_DIR": "/tmp/parallel-x"])
        XCTAssertEqual(url?.path, "/tmp/parallel-x")
    }
}
