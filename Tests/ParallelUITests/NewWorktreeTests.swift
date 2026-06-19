import XCTest
import Carbon.HIToolbox

final class NewWorktreeTests: XCTestCase {
    func testNewWorktreeCreatesLiveSession() throws {
        let fx = try E2EFixture.make()
        defer { fx.cleanup() }
        let repo = try fx.makeRepo(named: "demo")
        try fx.writeSeed("""
        {"repos":[{"root":"\(repo.path)","displayName":"demo"}],"worktrees":[]}
        """)

        // The dev/CI host's keyboard input source is a Korean IME, which composes
        // synthesized `typeText` keystrokes into Hangul (e.g. "feature/y" →
        // "ㅇZeatuㅓre/"). Switch the system input source to an ASCII-capable
        // layout for the duration of the test so typed text lands verbatim.
        let previousInputSource = currentInputSource()
        XCTAssertTrue(selectASCIIKeyboard(), "an ASCII-capable keyboard layout must be available")
        defer { if let s = previousInputSource { TISSelectInputSource(s) } }

        let app = XCUIApplication()
        app.launchE2E(fixture: fx)

        // Open the New Worktree sheet. The SwiftUI toolbar wraps the button in a
        // second element carrying the same identifier, so target the first match.
        let newButton = app.buttons["toolbar.newWorktree"].firstMatch
        XCTAssertTrue(newButton.waitForExistence(timeout: 15))
        newButton.click()

        // Select the seeded repo in the picker (SwiftUI Picker → NSPopUpButton →
        // NSMenu; the menu item is matched by its title "demo").
        let repoPicker = app.popUpButtons["sheet.newWorktree.repo"]
        XCTAssertTrue(repoPicker.waitForExistence(timeout: 5))
        repoPicker.click()
        let repoItem = app.menuItems["demo"]
        XCTAssertTrue(repoItem.waitForExistence(timeout: 5))
        repoItem.click()
        XCTAssertTrue(waitForValue(repoPicker, equals: "demo", timeout: 5),
                      "repo picker should reflect the selected repo")

        // Type the branch name. `typeText` can drop a boundary keystroke right
        // after focusing, so type with a verify+retry loop until the field holds
        // the exact value.
        let branchField = app.textFields["sheet.newWorktree.branch"]
        XCTAssertTrue(branchField.waitForExistence(timeout: 5))
        XCTAssertTrue(setFieldText(branchField, to: "feature/y"),
                      "branch field should hold the exact typed value")

        // Create the worktree.
        let createButton = app.buttons["sheet.newWorktree.create"]
        XCTAssertTrue(createButton.isEnabled, "Create should be enabled once repo + branch are set")
        createButton.click()

        // The new row shows. Display name is sanitized ("feature-y"); the branch
        // ("feature/y") renders as a separate caption because the two differ.
        XCTAssertTrue(app.staticTexts["feature/y"].waitForExistence(timeout: 15),
                      "new worktree row should appear")

        // Exactly one running session now exists.
        let probe = app.staticTexts["e2e.runningSessionCount"]
        XCTAssertTrue(probe.waitForExistence(timeout: 5))
        expectValue(probe, toEqual: "1", timeout: 10)

        // Creating a worktree does not auto-select it, so the terminal pane is not
        // mounted yet. Select the new row to mount its live session's NSView.
        let row = app.staticTexts["feature-y"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.click()

        // Prove the PTY is a live, interactive shell: focus the terminal and type
        // a command that writes a sentinel file, then poll for it. SwiftTerm's
        // NSView doesn't surface the SwiftUI container id, so focus it by clicking
        // into the right-hand terminal region. typeText can drop a boundary key;
        // retry the round-trip until the sentinel lands (each echo is idempotent).
        var sentinelWritten = false
        for _ in 0..<5 {
            app.windows.firstMatch
                .coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.55)).click()
            usleep(700_000)
            app.typeText("echo PARALLEL_READY > \(fx.probeFile.path)\n")
            if waitForFile(fx.probeFile, timeout: 6) { sentinelWritten = true; break }
        }
        XCTAssertTrue(sentinelWritten,
                      "sentinel file should be written by the live shell")

        app.terminate()
    }

    // MARK: - Text entry

    /// Click a field, clear it, type `text`, and verify the value matches.
    /// Retries to absorb XCUITest's occasional first/last-keystroke drops.
    @discardableResult
    private func setFieldText(_ field: XCUIElement, to text: String) -> Bool {
        for _ in 0..<6 {
            field.click()
            usleep(300_000)
            field.typeKey(.rightArrow, modifierFlags: .command)   // cursor → end
            let cur = (field.value as? String) ?? ""
            for _ in 0..<(cur.count + 6) { field.typeKey(.delete, modifierFlags: []) }
            usleep(200_000)
            field.typeText(text)
            usleep(350_000)
            if (field.value as? String) == text { return true }
        }
        return (field.value as? String) == text
    }

    private func waitForValue(_ element: XCUIElement, equals expected: String,
                              timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (element.value as? String) == expected { return true }
            usleep(150_000)
        }
        return (element.value as? String) == expected
    }

    // MARK: - Keyboard input source (defeat the host IME)

    private func currentInputSource() -> TISInputSource? {
        TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
    }

    /// Select an ASCII-capable keyboard layout (preferring ABC / U.S.) so typed
    /// text is not composed by the host's Hangul IME. Returns false if none found.
    @discardableResult
    private func selectASCIIKeyboard() -> Bool {
        func candidates(includeAllInstalled: Bool) -> [TISInputSource] {
            guard let cf = TISCreateInputSourceList(nil, includeAllInstalled)?
                .takeRetainedValue() else { return [] }
            return (cf as NSArray).compactMap { ($0 as! TISInputSource) }
        }
        func isASCIIKeyboardLayout(_ src: TISInputSource) -> Bool {
            guard let catPtr = TISGetInputSourceProperty(src, kTISPropertyInputSourceCategory) else { return false }
            let cat = Unmanaged<CFString>.fromOpaque(catPtr).takeUnretainedValue() as String
            guard cat == (kTISCategoryKeyboardInputSource as String) else { return false }
            guard let aPtr = TISGetInputSourceProperty(src, kTISPropertyInputSourceIsASCIICapable) else { return false }
            return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(aPtr).takeUnretainedValue())
        }
        func sourceID(_ src: TISInputSource) -> String {
            guard let p = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) else { return "" }
            return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
        }
        func trySelect(from sources: [TISInputSource]) -> Bool {
            let layouts = sources.filter(isASCIIKeyboardLayout)
            let preferred = layouts.first { sourceID($0).contains("ABC") || sourceID($0).contains("keylayout.US") }
            guard let chosen = preferred ?? layouts.first else { return false }
            TISEnableInputSource(chosen)
            return TISSelectInputSource(chosen) == noErr
        }
        if trySelect(from: candidates(includeAllInstalled: false)) { return true }
        return trySelect(from: candidates(includeAllInstalled: true))
    }
}
