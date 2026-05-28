import SwiftUI

/// Confirmation sheet for worktree deletion.
/// Includes an opt-in toggle to also delete the underlying git branch.
struct DeleteWorktreeSheet: View {
    @Environment(\.dismiss) private var dismiss

    let worktree: Worktree
    let onConfirm: (_ alsoDeleteBranch: Bool) -> Void

    @State private var alsoDeleteBranch = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Delete worktree?").font(.title2).bold()

            VStack(alignment: .leading, spacing: 4) {
                Text(worktree.displayName).font(.headline)
                Text(worktree.path.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            Toggle("Also delete branch \(branchLabel)", isOn: $alsoDeleteBranch)
                .padding(.top, 4)

            Text(alsoDeleteBranch
                 ? "The worktree directory and the git branch will both be removed."
                 : "The worktree directory will be removed. The branch is preserved.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Delete", role: .destructive) {
                    onConfirm(alsoDeleteBranch)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private var branchLabel: String {
        "‘\(worktree.branch)’"
    }
}
