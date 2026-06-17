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

    /// Output produced while reading is paused must not be lost — it stays in
    /// the kernel pipe and is delivered after resume.
    func test_pauseThenResume_deliversAllOutput() throws {
        let tmp = FileManager.default.temporaryDirectory
        guard let pty = PTY(shell: "/bin/sh", cwd: tmp) else {
            XCTFail("forkpty failed")
            return
        }
        let received = NSMutableData()
        let lock = NSLock()
        let gotMarker = expectation(description: "got END marker")
        gotMarker.assertForOverFulfill = false

        let source = pty.startReading(
            onData: { data in
                lock.lock()
                received.append(data)
                let text = String(data: received as Data, encoding: .utf8) ?? ""
                lock.unlock()
                if text.contains("END_MARKER_99") { gotMarker.fulfill() }
            },
            onEOF: {}
        )

        // Pause first, then generate a few KB of output. It accumulates in the
        // pipe; nothing is read until we resume.
        pty.pauseReading()
        pty.write("printf 'A%.0s' $(seq 1 5000); echo END_MARKER_99\n".data(using: .utf8)!)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            pty.resumeReading()
        }

        wait(for: [gotMarker], timeout: 5.0)

        pty.write("exit\n".data(using: .utf8)!)
        Thread.sleep(forTimeInterval: 0.1)
        source.cancel()
        pty.terminate()
    }

    /// Redundant pause/resume calls are guarded so the dispatch source's
    /// suspend count stays balanced and terminate() never crashes.
    func test_pauseResume_redundantCallsAreBalanced() {
        let tmp = FileManager.default.temporaryDirectory
        guard let pty = PTY(shell: "/bin/sh", cwd: tmp) else {
            XCTFail("forkpty failed")
            return
        }
        let source = pty.startReading(onData: { _ in }, onEOF: {})
        pty.pauseReading()
        pty.pauseReading()   // redundant — must be a no-op
        pty.resumeReading()
        pty.resumeReading()  // redundant — must be a no-op
        source.cancel()
        pty.terminate()      // must not crash
    }
}
