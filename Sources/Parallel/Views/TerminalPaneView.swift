import SwiftUI

struct TerminalPaneView: View {
    let worktreeId: UUID?

    var body: some View {
        VStack {
            Spacer()
            Text(worktreeId == nil ? "Select a worktree" : "Terminal goes here")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
