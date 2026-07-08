import XCTest
import AppKit
@testable import Parallel

/// Issue #19: ⌘W must close only the active shell tab, never the window/app.
/// SwiftUI's `WindowGroup` installs a standard File ▸ Close (`performClose:`)
/// bound to ⌘W that competes with the Worktree ▸ "Close Session" command; when
/// the terminal isn't focused the standard item wins and — Parallel being a
/// single-window app — tears down every session / quits the app. We neutralise
/// that item so ⌘W is owned solely by "Close Session". These tests pin the pure
/// predicate that decides which menu item to strip.
final class CloseWindowShortcutTests: XCTestCase {
    func test_strips_standard_performClose_cmdW() {
        XCTAssertTrue(AppMenuConfigurator.shouldStripCloseShortcut(
            action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
    }

    func test_keeps_performClose_without_cmdW() {
        // A performClose: item carrying no ⌘W (or a different equivalent) is not
        // the one we fight over — leave it alone.
        XCTAssertFalse(AppMenuConfigurator.shouldStripCloseShortcut(
            action: #selector(NSWindow.performClose(_:)), keyEquivalent: ""))
    }

    func test_keeps_other_action_bound_to_w() {
        // Our own "Close Session" item also carries ⌘W but a different action;
        // it must survive.
        XCTAssertFalse(AppMenuConfigurator.shouldStripCloseShortcut(
            action: #selector(NSApplication.terminate(_:)), keyEquivalent: "w"))
    }

    func test_keeps_item_with_nil_action() {
        XCTAssertFalse(AppMenuConfigurator.shouldStripCloseShortcut(
            action: nil, keyEquivalent: "w"))
    }

    /// The recursive stripper clears ⌘W on the standard Close item wherever it
    /// sits in the menu tree, and leaves a same-key item with a different action.
    func test_stripper_clears_only_the_standard_close_item() {
        let file = NSMenu(title: "File")
        let close = NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        file.addItem(close)

        let worktree = NSMenu(title: "Worktree")
        let closeSession = NSMenuItem(title: "Close Session", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "w")
        worktree.addItem(closeSession)

        let root = NSMenu(title: "MainMenu")
        let fileItem = NSMenuItem(); fileItem.submenu = file
        let worktreeItem = NSMenuItem(); worktreeItem.submenu = worktree
        root.addItem(fileItem); root.addItem(worktreeItem)

        AppMenuConfigurator.stripDefaultCloseShortcut(in: root)

        XCTAssertEqual(close.keyEquivalent, "", "standard Close should lose its ⌘W")
        XCTAssertEqual(closeSession.keyEquivalent, "w", "our Close Session must keep ⌘W")
    }
}
