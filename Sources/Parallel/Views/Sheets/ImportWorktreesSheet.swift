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
    @State private var selected: Set<URL> = []
    @State private var search: String = ""
    @State private var loading = true
    @State private var errorMessage: String?

    private let svc = WorktreeService()

    private var repo: Repo? { store.repos.first { $0.id == repoId } }

    private var filtered: [WorktreeService.Entry] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return candidates }
        return candidates.filter {
            $0.branch.lowercased().contains(q) || $0.path.path.lowercased().contains(q)
        }
    }

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
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Filter by branch or path", text: $search)
                        .textFieldStyle(.plain)
                    if !search.isEmpty {
                        Button {
                            search = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))

                HStack {
                    Button("Select All (\(filtered.count))") {
                        for e in filtered { selected.insert(e.path.standardizedFileURL) }
                    }
                    .disabled(filtered.isEmpty)
                    Button("Deselect All") {
                        for e in filtered { selected.remove(e.path.standardizedFileURL) }
                    }
                    .disabled(filtered.isEmpty)
                    Spacer()
                    Text("\(selected.count) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if filtered.isEmpty {
                    Text("No matches.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    List {
                        ForEach(filtered, id: \.path) { e in
                            Toggle(isOn: Binding(
                                get: { selected.contains(e.path.standardizedFileURL) },
                                set: { isOn in
                                    if isOn { selected.insert(e.path.standardizedFileURL) }
                                    else { selected.remove(e.path.standardizedFileURL) }
                                }
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
            }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Import") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(loading || candidates.isEmpty || selected.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear(perform: scan)
    }

    private func scan() {
        guard let repo else { errorMessage = "Repo not found"; loading = false; return }
        loading = true
        let registered = store.registeredPaths(for: repo.id)
        do {
            let entries = try svc.list(in: repo.root)
            let rootKey = repo.root.standardizedFileURL
            candidates = entries.filter { e in
                e.path.standardizedFileURL != rootKey
                    && !registered.contains(e.path.standardizedFileURL)
            }
            // Pre-select if only one candidate.
            if candidates.count == 1 {
                selected = [candidates[0].path.standardizedFileURL]
            } else {
                selected = []
            }
        } catch {
            errorMessage = "Failed to scan: \(error.localizedDescription)"
            candidates = []
            selected = []
        }
        loading = false
    }

    private func commit() {
        guard let repo else { return }
        for entry in candidates where selected.contains(entry.path.standardizedFileURL) {
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
