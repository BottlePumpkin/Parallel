import XCTest

/// Verifies the explicit Copy / Paste / Select All wiring this issue adds. The
/// app previously shipped without an Edit menu, so ⌘C / ⌘V had no menu item to
/// route them through the responder chain. Asserting the items exist proves the
/// wiring is present and addressable; the clipboard *content* round-trip lives
/// inside SwiftTerm (selection + insertText), which it hides from the AX tree,
/// so that part is verified manually (see the PR notes).
final class EditMenuTests: XCTestCase {
    func testEditMenuExposesCopyPasteSelectAll() throws {
        let fx = try E2EFixture.make()
        defer { fx.cleanup() }
        let app = XCUIApplication()
        app.launchE2E(fixture: fx)
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))

        let editMenu = app.menuBars.menuBarItems["Edit"]
        XCTAssertTrue(editMenu.waitForExistence(timeout: 5), "Edit menu should exist")
        editMenu.click()

        for title in ["Copy", "Paste", "Select All"] {
            XCTAssertTrue(app.menuBars.menuItems[title].waitForExistence(timeout: 5),
                          "Edit menu should expose \(title)")
        }
        app.terminate()
    }
}
