import SwiftUI
import AppKit

/// App-level menu commands. The actual actions are owned by ContentView and
/// exposed to the menu via FocusedValue. Menu items are disabled when no
/// ContentView is focused.
struct ParallelCommands: Commands {
    @FocusedValue(\.contentActions) var actions

    /// Dispatch a standard editing selector down the responder chain so the
    /// focused `TerminalView` (which implements `copy:` / `paste:` /
    /// `selectAll:`) handles it. The app shipped without an Edit menu, so these
    /// key equivalents were never routed — this wires them explicitly.
    private func sendToResponder(_ selector: Selector) {
        NSApp.sendAction(selector, to: nil, from: nil)
    }

    var body: some Commands {
        // ⌘C / ⌘V / ⌘A — copy / paste / select-all in the focused terminal.
        // Replaces the empty default pasteboard group so the items actually exist.
        CommandGroup(replacing: .pasteboard) {
            Button("Copy") { sendToResponder(#selector(NSText.copy(_:))) }
                .keyboardShortcut("c", modifiers: .command)
            Button("Paste") { sendToResponder(#selector(NSText.paste(_:))) }
                .keyboardShortcut("v", modifiers: .command)
            Button("Select All") { sendToResponder(#selector(NSText.selectAll(_:))) }
                .keyboardShortcut("a", modifiers: .command)
        }
        CommandGroup(replacing: .newItem) {
            Button("New Worktree…") { actions?.newWorktree() }
                .keyboardShortcut("n", modifiers: .command)
            Button("Add Repository…") { actions?.addRepo() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
        }
        CommandMenu("Worktree") {
            ForEach(1...9, id: \.self) { idx in
                Button("Switch to Worktree \(idx)") { actions?.selectWorktreeIndex(idx - 1) }
                    .keyboardShortcut(KeyEquivalent(Character("\(idx)")), modifiers: [.command, .option])
            }
            Divider()
            Button("Close Session") { actions?.closeCurrentSession() }
                .keyboardShortcut("w", modifiers: .command)
            Button("Delete Worktree…") { actions?.deleteCurrentWorktree() }
                .keyboardShortcut(.delete, modifiers: .command)
        }
        CommandMenu("Terminal") {
            Button("New Tab") { actions?.newTab() }
                .keyboardShortcut("t", modifiers: .command)
            Button("Clear") { actions?.clearTerminal() }
                .keyboardShortcut("k", modifiers: .command)
            Button("Find…") { actions?.findInTerminal() }
                .keyboardShortcut("f", modifiers: .command)
            Divider()
            Button("Increase Font Size") { actions?.increaseFontSize() }
                .keyboardShortcut("+", modifiers: .command)
            Button("Decrease Font Size") { actions?.decreaseFontSize() }
                .keyboardShortcut("-", modifiers: .command)
            Button("Reset Font Size") { actions?.resetFontSize() }
                .keyboardShortcut("0", modifiers: .command)
            Divider()
            Button("Next Tab") { actions?.nextTab() }
                .keyboardShortcut(.tab, modifiers: .control)
            Button("Previous Tab") { actions?.previousTab() }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
            Divider()
            ForEach(1...9, id: \.self) { idx in
                Button("Switch to Tab \(idx)") { actions?.selectTabIndex(idx - 1) }
                    .keyboardShortcut(KeyEquivalent(Character("\(idx)")), modifiers: .command)
            }
        }
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { actions?.checkForUpdates() }
            Divider()
            Button("Report Issue…") { actions?.reportIssue() }
        }
    }
}

/// Bundle of action callbacks the menu invokes on the currently focused
/// ContentView.
struct ContentActions {
    var newWorktree: () -> Void = {}
    var addRepo: () -> Void = {}
    var selectWorktreeIndex: (Int) -> Void = { _ in }
    var selectTabIndex: (Int) -> Void = { _ in }
    var nextTab: () -> Void = {}
    var previousTab: () -> Void = {}
    var newTab: () -> Void = {}
    var clearTerminal: () -> Void = {}
    var findInTerminal: () -> Void = {}
    var increaseFontSize: () -> Void = {}
    var decreaseFontSize: () -> Void = {}
    var resetFontSize: () -> Void = {}
    var closeCurrentSession: () -> Void = {}
    var deleteCurrentWorktree: () -> Void = {}
    var checkForUpdates: () -> Void = {}
    var reportIssue: () -> Void = {}
}

private struct ContentActionsKey: FocusedValueKey {
    typealias Value = ContentActions
}

extension FocusedValues {
    var contentActions: ContentActions? {
        get { self[ContentActionsKey.self] }
        set { self[ContentActionsKey.self] = newValue }
    }
}
