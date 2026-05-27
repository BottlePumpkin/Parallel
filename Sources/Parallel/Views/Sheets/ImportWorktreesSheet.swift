import SwiftUI

/// Import existing git worktrees of a known repo. Scans the repo with
/// `git worktree list --porcelain`, filters out already-registered paths
/// and the repo root itself, and lets the user pick which to add.
struct ImportWorktreesSheet: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.dismiss) private var dismiss

    let repoId: UUID

    @State private var candidates: [WorktreeService.Entry] = []
    @State private var importChoices: [Bool] = []
    @State private var loading = true
    @State private var errorMessage: String?

    private let svc = WorktreeService()

    private var repo: Repo? { store.repos.first { $0.id == repoId } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import Worktrees").font(.title2).bold()
            if let repo {
                Text(repo.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if loading {
                ProgressView("Scanning…").frame(maxWidth: .infinity)
            } else if candidates.isEmpty {
                Text("No unimported worktrees found.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                HStack {
                    Button("Select All") {
                        importChoices = Array(repeating: true, count: candidates.count)
                    }
                    Button("Deselect All") {
                        importChoices = Array(repeating: false, count: candidates.count)
                    }
                    Spacer()
                }
                List {
                    ForEach(Array(candidates.enumerated()), id: \.offset) { idx, e in
                        Toggle(isOn: Binding(
                            get: { importChoices[idx] },
                            set: { importChoices[idx] = $0 }
                        )) {
                            VStack(alignment: .leading) {
                                Text(e.branch).font(.body)
                                Text(e.path.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                }
                .frame(minHeight: 160, maxHeight: 320)
            }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Import") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(loading || candidates.isEmpty || !importChoices.contains(true))
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear(perform: scan)
    }

    private func scan() {
        guard let repo else { errorMessage = "Repo not found"; loading = false; return }
        loading = true
        let registered = Set(
            store.worktrees
                .filter { $0.repoId == repo.id }
                .map { $0.path.standardizedFileURL }
        )
        do {
            let entries = try svc.list(in: repo.root)
            // Exclude the repo root itself + anything already registered.
            let rootKey = repo.root.standardizedFileURL
            candidates = entries.filter { e in
                e.path.standardizedFileURL != rootKey
                    && !registered.contains(e.path.standardizedFileURL)
            }
            importChoices = Array(repeating: candidates.count == 1, count: candidates.count)
        } catch {
            errorMessage = "Failed to scan: \(error.localizedDescription)"
            candidates = []
            importChoices = []
        }
        loading = false
    }

    private func commit() {
        guard let repo else { return }
        for (idx, entry) in candidates.enumerated() where importChoices[idx] {
            let wt = Worktree(
                repoId: repo.id,
                path: entry.path,
                branch: entry.branch,
                displayName: entry.path.lastPathComponent,
                setupCommands: repo.defaultSetupCommands
            )
            store.addWorktree(wt)
            sessionManager.ensureSession(for: wt, setupCommands: repo.defaultSetupCommands)
        }
        dismiss()
    }
}
