import XCTest
@testable import Parallel

/// Issue #12: raw terminal bells are noisy (bursts). A per-session leading-edge
/// debouncer fires on the first bell, then suppresses further bells until the
/// cooldown elapses. Time is injected (monotonic seconds) for determinism.
final class BellDebouncerTests: XCTestCase {
    func test_firesOnFirstBell() {
        var d = BellDebouncer(cooldown: 2.0)
        XCTAssertTrue(d.shouldFire(now: 100.0))
    }

    func test_suppressesWithinCooldown() {
        var d = BellDebouncer(cooldown: 2.0)
        _ = d.shouldFire(now: 100.0)
        XCTAssertFalse(d.shouldFire(now: 101.9))
    }

    func test_firesAgainAfterCooldown() {
        var d = BellDebouncer(cooldown: 2.0)
        _ = d.shouldFire(now: 100.0)
        XCTAssertTrue(d.shouldFire(now: 102.0))
    }

    func test_burstCollapsesToOne() {
        var d = BellDebouncer(cooldown: 2.0)
        let results = [100.0, 100.1, 100.5, 101.0].map { d.shouldFire(now: $0) }
        XCTAssertEqual(results, [true, false, false, false])
    }
}
