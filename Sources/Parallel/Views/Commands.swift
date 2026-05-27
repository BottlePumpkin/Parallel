import SwiftUI

/// App-level menu commands. The actual actions are owned by ContentView and
/// exposed to the menu via FocusedValue. Menu items are disabled when no
/// ContentView is focused.
struct ParallelCommands: Commands {
    @FocusedValue(\.contentActions) var actions

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Worktree…") { actions?.newWorktree() }
                .keyboardShortcut("n", modifiers: .command)
            Button("Add Repository…") { actions?.addRepo() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
        }
        CommandMenu("Worktree") {
            ForEach(1...9, id: \.self) { idx in
                Button("Switch to Worktree \(idx)") { actions?.selectIndex(idx - 1) }
                    .keyboardShortcut(KeyEquivalent(Character("\(idx)")), modifiers: .command)
            }
            Divider()
            Button("Close Session") { actions?.closeCurrentSession() }
                .keyboardShortcut("w", modifiers: .command)
            Button("Delete Worktree") { actions?.deleteCurrentWorktree() }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
        }
    }
}

/// Bundle of action callbacks the menu invokes on the currently focused
/// ContentView.
struct ContentActions {
    var newWorktree: () -> Void = {}
    var addRepo: () -> Void = {}
    var selectIndex: (Int) -> Void = { _ in }
    var closeCurrentSession: () -> Void = {}
    var deleteCurrentWorktree: () -> Void = {}
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
