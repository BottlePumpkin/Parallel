import XCTest

extension XCTestCase {
    /// Poll until `url` exists or the timeout elapses.
    func waitForFile(_ url: URL, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: url.path) { return true }
            usleep(200_000)
        }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Poll an element's `.value` until it equals `expected`, then assert.
    func expectValue(_ element: XCUIElement, toEqual expected: String, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (element.value as? String) == expected { return }
            usleep(200_000)
        }
        XCTAssertEqual(element.value as? String, expected)
    }

    /// Wait until an element no longer exists.
    func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let exp = expectation(for: predicate, evaluatedWith: element)
        return XCTWaiter().wait(for: [exp], timeout: timeout) == .completed
    }
}
