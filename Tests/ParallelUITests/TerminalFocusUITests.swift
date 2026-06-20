import XCTest

/// Issue #7: when a worktree/tab switch makes a terminal visible, keyboard focus
/// must move to it so the user can type immediately — without first clicking the
/// pane. This drives the real UI: it switches *back* to an already-mounted
/// terminal (the `MountedTerminalView.updateNSView` hidden→visible path that
/// previously failed to take focus) and asserts, via the e2e first-responder
/// probe, that a terminal actually holds keyboard focus afterward.
///
/// The probe is read (not typed into) on purpose: `XCUIApplication.typeText`
/// has no timeout and blocks indefinitely when nothing accepts the keystrokes,
/// which is exactly the pre-fix state — so a type-based assertion can hang the
/// CI job for hours. Reading first-responder state keeps every wait bounded.
final class TerminalFocusUITests: XCTestCase {
    func testSwitchingBackToWorktreeAutoFocusesTerminal() throws {
        let fx = try E2EFixture.make()
        defer { fx.cleanup() }
        let repo = try fx.makeRepo(named: "demo")
        let alpha = try fx.addWorktree(repo: repo, branch: "alpha", dirName: "alpha")
        let beta  = try fx.addWorktree(repo: repo, branch: "beta",  dirName: "beta")
        try fx.writeSeed("""
        {"repos":[{"root":"\(repo.path)","displayName":"demo"}],
         "worktrees":[
           {"repoIndex":0,"path":"\(alpha.path)","branch":"alpha","displayName":"alpha"},
           {"repoIndex":0,"path":"\(beta.path)","branch":"beta","displayName":"beta"}
         ]}
        """)

        let app = XCUIApplication()
        app.launchE2E(fixture: fx)

        let alphaRow = app.staticTexts["alpha"]
        let betaRow  = app.staticTexts["beta"]
        XCTAssertTrue(alphaRow.waitForExistence(timeout: 15), "seeded 'alpha' row should be visible")
        XCTAssertTrue(betaRow.waitForExistence(timeout: 15), "seeded 'beta' row should be visible")

        let count = app.staticTexts["e2e.runningSessionCount"]
        XCTAssertTrue(count.waitForExistence(timeout: 5))

        // Mount both live sessions (selecting a worktree ensures its session).
        alphaRow.click()
        expectValue(count, toEqual: "1", timeout: 15)
        betaRow.click()
        expectValue(count, toEqual: "2", timeout: 15)

        // Switch BACK to alpha: its terminal was hidden and becomes visible again
        // — the exact transition that used to leave focus behind. No click on the
        // pane: focus must move on its own.
        alphaRow.click()

        let terminalFocus = app.staticTexts["e2e.terminalHasFocus"]
        XCTAssertTrue(terminalFocus.waitForExistence(timeout: 5))
        expectValue(terminalFocus, toEqual: "1", timeout: 10)

        app.terminate()
    }
}
