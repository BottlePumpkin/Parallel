import SwiftUI
import AppKit

struct AddRepoSheet: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedRoot: URL?
    @State private var displayName = ""
    @State private var worktreeBaseDir = ".claude/worktrees"
    @State private var defaultSetupCommands = ""
    @State private var discovered: [WorktreeService.Entry] = []
    @State private var importChoices: [Bool] = []
    @State private var errorMessage: String?

    private let svc = WorktreeService()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Repository").font(.title2).bold()

            HStack {
                Text(selectedRoot?.path ?? "(no folder)")
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Choose…") { pickFolder() }
            }

            TextField("Display name", text: $displayName)
            TextField("Worktree base dir (relative to repo root)", text: $worktreeBaseDir)
            TextField("Default setup commands (one per line)",
                      text: $defaultSetupCommands, axis: .vertical)
                .lineLimit(3, reservesSpace: true)

            if !discovered.isEmpty {
                Text("Existing worktrees (select to import):").font(.headline)
                List {
                    ForEach(Array(discovered.enumerated()), id: \.offset) { idx, e in
                        Toggle(isOn: Binding(
                            get: { importChoices[idx] },
                            set: { importChoices[idx] = $0 }
                        )) {
                            VStack(alignment: .leading) {
                                Text(e.branch).font(.body)
                                Text(e.path.path).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(minHeight: 120, maxHeight: 200)
            }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedRoot == nil || displayName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            selectedRoot = url
            if displayName.isEmpty { displayName = url.lastPathComponent }
            do {
                discovered = try svc.list(in: url)
                importChoices = Array(repeating: false, count: discovered.count)
            } catch {
                errorMessage = "Failed to scan worktrees: \(error.localizedDescription)"
            }
        }
    }

    private func commit() {
        guard let root = selectedRoot else { return }
        let setupLines = defaultSetupCommands
            .split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // If this repo root is already registered, merge into the existing Repo
        // instead of creating a duplicate group.
        let targetRepoId: UUID
        if let existing = store.repos.first(where: {
            $0.root.standardizedFileURL == root.standardizedFileURL
        }) {
            targetRepoId = existing.id
        } else {
            let repo = Repo(root: root, displayName: displayName,
                            worktreeBaseDir: worktreeBaseDir,
                            defaultSetupCommands: setupLines)
            store.addRepo(repo)
            targetRepoId = repo.id
        }

        // Existing worktree paths under this repo — avoid duplicates.
        let existingPaths = Set(
            store.worktrees
                .filter { $0.repoId == targetRepoId }
                .map { $0.path.standardizedFileURL }
        )

        for (idx, entry) in discovered.enumerated() where importChoices[idx] {
            // Skip the main worktree (= repo root itself) — that's the repo, not a worktree to track.
            if entry.path.standardizedFileURL == root.standardizedFileURL { continue }
            // Skip if already imported.
            if existingPaths.contains(entry.path.standardizedFileURL) { continue }
            let wt = Worktree(
                repoId: targetRepoId,
                path: entry.path,
                branch: entry.branch,
                displayName: entry.path.lastPathComponent,
                setupCommands: setupLines
            )
            store.addWorktree(wt)
            sessionManager.ensureSession(for: wt, setupCommands: setupLines)
        }
        dismiss()
    }
}
