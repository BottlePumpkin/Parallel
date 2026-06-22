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
