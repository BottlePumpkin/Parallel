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
