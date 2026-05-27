import XCTest
@testable import Parallel

final class PTYTests: XCTestCase {

    /// Fork /bin/sh, write a command, read output, verify the response contains
    /// the expected token. This is the smallest test that exercises forkpty
    /// + write + async read + termination.
    func test_forkShell_writesAndReads() throws {
        let tmp = FileManager.default.temporaryDirectory
        guard let pty = PTY(shell: "/bin/sh", cwd: tmp) else {
            XCTFail("forkpty failed")
            return
        }

        let received = NSMutableData()
        let lock = NSLock()
        let gotMarker = expectation(description: "got marker")
        gotMarker.assertForOverFulfill = false

        let source = pty.startReading(
            onData: { data in
                lock.lock()
                received.append(data)
                let text = String(data: received as Data, encoding: .utf8) ?? ""
                lock.unlock()
                if text.contains("PARALLEL_MARKER_42") {
                    gotMarker.fulfill()
                }
            },
            onEOF: {}
        )

        // Send a command that prints a marker
        let cmd = "echo PARALLEL_MARKER_42\n"
        pty.write(cmd.data(using: .utf8)!)

        wait(for: [gotMarker], timeout: 5.0)

        // Cleanup: send exit, terminate as belt-and-suspenders
        pty.write("exit\n".data(using: .utf8)!)
        Thread.sleep(forTimeInterval: 0.1)
        source.cancel()
        pty.terminate()
    }

    /// Smaller test: just verify that forking succeeds and terminate is safe.
    func test_forkAndTerminate_smoke() {
        let tmp = FileManager.default.temporaryDirectory
        guard let pty = PTY(shell: "/bin/sh", cwd: tmp) else {
            XCTFail("forkpty failed")
            return
        }
        XCTAssertGreaterThan(pty.pid, 0)
        XCTAssertGreaterThanOrEqual(pty.masterFD, 0)
        pty.terminate()
    }
}
