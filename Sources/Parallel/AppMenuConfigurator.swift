import AppKit

/// Neutralises AppKit's standard ⌘W window-close so that ⌘W is owned solely by
/// the Worktree ▸ "Close Session" command (issue #19).
///
/// SwiftUI's `WindowGroup` installs a File ▸ Close item bound to `performClose:`
/// / ⌘W. Parallel is a single-window app, so that item quits the app (tearing
/// down every worktree session) — and it competes with our own "Close Session"
/// ⌘W, winning whenever the terminal isn't the first responder. We clear its key
/// equivalent after launch, leaving the item present (still clickable, and via
/// the Window menu) but no longer stealing ⌘W.
enum AppMenuConfigurator {
    /// Pure predicate: does this menu item's (action, keyEquivalent) identify the
    /// standard ⌘W window-close we want to neutralise? Matches on the action so a
    /// same-key item with a different action (our "Close Session") is untouched.
    /// Kept separate from the menu walk so it is unit-testable without a live
    /// menu bar.
    static func shouldStripCloseShortcut(action: Selector?, keyEquivalent: String) -> Bool {
        action == #selector(NSWindow.performClose(_:)) && keyEquivalent == "w"
    }

    /// Recursively clear the key equivalent on every standard performClose:-⌘W
    /// item in `menu`. Idempotent — safe to run more than once.
    static func stripDefaultCloseShortcut(in menu: NSMenu?) {
        guard let menu else { return }
        for item in menu.items {
            if shouldStripCloseShortcut(action: item.action, keyEquivalent: item.keyEquivalent) {
                item.keyEquivalent = ""
            }
            stripDefaultCloseShortcut(in: item.submenu)
        }
    }
}
