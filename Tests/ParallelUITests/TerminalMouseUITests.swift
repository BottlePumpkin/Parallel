import XCTest

/// Visual/E2E coverage for the terminal mouse behaviors. Drives the real app
/// with real gestures over the terminal while it is in any-event SGR mouse
/// tracking (as Claude Code runs it), and asserts the outcome via the e2e probe
/// — proving the gesture→behavior path, not just the pure policies.
///
/// The terminal is put into mouse mode by the app itself under
/// `PARALLEL_E2E_MOUSE` (no real Claude needed), so the tests are deterministic.
/// Gestures target window coordinates: the terminal fills the detail pane, so
/// the window's centre/right lands inside it (SwiftTerm's NSView is not exposed
/// as its own queryable element).
///
/// Note: scroll-wheel forwarding is *not* covered here — XCUITest has no HID
/// wheel-injection API (`XCUIElement.scroll` routes through accessibility, which
/// the terminal never sees), so it is covered by `TerminalWheelEncodingTests`
/// (real SwiftTerm encode→wire) instead.
final class TerminalMouseUITests: XCTestCase {

    /// Launch with one worktree and a live, mouse-tracking terminal mounted.
    private func launchWithMouseTerminal() throws -> (XCUIApplication, E2EFixture) {
        let fx = try E2EFixture.make()
        let repo = try fx.makeRepo(named: "demo")
        let alpha = try fx.addWorktree(repo: repo, branch: "alpha", dirName: "alpha")
        try fx.writeSeed("""
        {"repos":[{"root":"\(repo.path)","displayName":"demo"}],
         "worktrees":[{"repoIndex":0,"path":"\(alpha.path)","branch":"alpha","displayName":"alpha"}]}
        """)

        let app = XCUIApplication()
        app.launchE2E(fixture: fx, mouseMode: true)

        let alphaRow = app.staticTexts["alpha"]
        XCTAssertTrue(alphaRow.waitForExistence(timeout: 15), "seeded worktree row should appear")
        let count = app.staticTexts["e2e.runningSessionCount"]
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        alphaRow.click()
        expectValue(count, toEqual: "1", timeout: 15)
        return (app, fx)
    }

    private func terminalPoint(_ app: XCUIApplication, dx: CGFloat, dy: CGFloat) -> XCUICoordinate {
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: dy))
    }

    /// A single click (no drag) is forwarded to the mouse-tracking program, so
    /// Claude's own clickable UI keeps working. This guards that drag-to-select
    /// didn't over-suppress and swallow plain clicks too.
    func testClickIsForwardedToProgram() throws {
        let (app, fx) = try launchWithMouseTerminal()
        defer { fx.cleanup() }

        terminalPoint(app, dx: 0.55, dy: 0.6).click()

        let reports = app.staticTexts["e2e.mouseReports"]
        XCTAssertTrue(reports.waitForExistence(timeout: 5))
        // SGR left-button report is "[<0;…". Its presence proves the click
        // reached the program rather than being consumed locally.
        expectValue(reports, toContain: "[<0", timeout: 10)

        app.terminate()
    }

    /// Dragging over the terminal selects text natively (issue #21) instead of
    /// being forwarded to the program — so ⌘C has something to copy.
    func testDragSelectsText() throws {
        let (app, fx) = try launchWithMouseTerminal()
        defer { fx.cleanup() }

        app.activate()
        // A deliberate, slow, wide drag with a hold — XCUITest can otherwise
        // register a fast move as a click and never start a selection. The slow
        // velocity emits enough intermediate drag events for SwiftTerm to begin
        // selecting.
        let start = terminalPoint(app, dx: 0.35, dy: 0.55)
        let end = terminalPoint(app, dx: 0.9, dy: 0.55)
        start.press(forDuration: 0.3, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.4)

        let selection = app.staticTexts["e2e.selectionActive"]
        XCTAssertTrue(selection.waitForExistence(timeout: 5))
        expectValue(selection, toEqual: "1", timeout: 10)

        app.terminate()
    }
}
