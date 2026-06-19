import SwiftUI

struct NewWorktreeSheet: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.dismiss) private var dismiss

    let initialRepoId: UUID?

    @State private var selectedRepoId: UUID?
    @State private var branch = ""
    @State private var base = "main"
    @State private var createBranch = true
    @State private var setupCommands = ""
    @State private var displayName = ""
    @State private var errorMessage: String?
    @State private var availableBranches: WorktreeService.BranchList = .init(local: [], remotes: [])

    /// Cap on remote-tracking refs shown in the Base dropdown. Anything older
    /// is still selectable via direct typing.
    private let remoteDisplayCap = 15

    private let svc = WorktreeService()

    init(initialRepoId: UUID? = nil) {
        self.initialRepoId = initialRepoId
        self._selectedRepoId = State(initialValue: initialRepoId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New Worktree").font(.title2).bold()

            Picker("Repository", selection: $selectedRepoId) {
                Text("(select)").tag(UUID?.none)
                ForEach(store.repos) { r in
                    Text(r.displayName).tag(UUID?.some(r.id))
                }
            }
            .accessibilityIdentifier("sheet.newWorktree.repo")
            .onChange(of: selectedRepoId) { _, _ in
                prefillSetup()
                loadBranches()
            }

            HStack {
                TextField("Branch", text: $branch)
                    .accessibilityIdentifier("sheet.newWorktree.branch")
                    .onChange(of: branch) { _, _ in displayName = sanitizedName }
                Toggle("New branch", isOn: $createBranch)
            }

            HStack {
                TextField("Base", text: $base).disabled(!createBranch)
                Menu {
                    if availableBranches.local.isEmpty
                        && availableBranches.remotes.isEmpty
                        && recentBases.isEmpty {
                        Text("(no branches)").foregroundStyle(.secondary)
                    } else {
                        if !recentBases.isEmpty {
                            Section("Recent") {
                                ForEach(recentBases, id: \.self) { b in
                                    Button(b) { base = b }
                                }
                            }
                        }
                        if !availableBranches.local.isEmpty {
                            Section("Local") {
                                ForEach(availableBranches.local, id: \.self) { b in
                                    Button(b) { base = b }
                                }
                            }
                        }
                        if !availableBranches.remotes.isEmpty {
                            Section("Remotes") {
                                ForEach(availableBranches.remotes.prefix(remoteDisplayCap), id: \.self) { b in
                                    Button(b) { base = b }
                                }
                                if availableBranches.remotes.count > remoteDisplayCap {
                                    Text("…\(availableBranches.remotes.count - remoteDisplayCap) more")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(!createBranch)
                .help("Pick from existing branches")
            }
            TextField("Display name", text: $displayName)

            if let preview = pathPreview {
                Text("Path: \(preview)").font(.caption).foregroundStyle(.secondary)
            }

            TextField("Setup commands (one per line)",
                      text: $setupCommands, axis: .vertical)
                .lineLimit(3, reservesSpace: true)

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedRepoId == nil || branch.isEmpty)
                    .accessibilityIdentifier("sheet.newWorktree.create")
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            if initialRepoId != nil { prefillSetup() }
            loadBranches()
        }
    }

    private var recentBases: [String] {
        selectedRepo?.recentBases ?? []
    }

    private func loadBranches() {
        guard let repo = selectedRepo else {
            availableBranches = .init(local: [], remotes: [])
            return
        }
        availableBranches = (try? svc.listBranches(in: repo.root))
            ?? .init(local: [], remotes: [])
        // Base prefill priority: most-recently-used base → first local →
        // first remote → keep typed value. Only swap if the current value
        // wasn't deliberately typed (i.e., it's not in any known list).
        let known = Set(availableBranches.local + availableBranches.remotes + recentBases)
        if !known.isEmpty, !known.contains(base) {
            base = recentBases.first
                ?? availableBranches.local.first
                ?? availableBranches.remotes.first
                ?? base
        }
    }

    private var selectedRepo: Repo? {
        guard let id = selectedRepoId else { return nil }
        return store.repos.first { $0.id == id }
    }

    private var sanitizedName: String {
        PathSanitizer.sanitize(branch)
    }

    private var pathPreview: String? {
        guard let repo = selectedRepo else { return nil }
        let raw = repo.root.appendingPathComponent(repo.worktreeBaseDir)
            .appendingPathComponent(sanitizedName)
        return uniquePath(base: raw).path
    }

    private func prefillSetup() {
        if setupCommands.isEmpty, let repo = selectedRepo {
            setupCommands = repo.defaultSetupCommands.joined(separator: "\n")
        }
    }

    /// Append -2/-3/... if the target path already exists.
    private func uniquePath(base: URL) -> URL {
        if !FileManager.default.fileExists(atPath: base.path) { return base }
        var n = 2
        while true {
            let candidate = base.deletingLastPathComponent()
                .appendingPathComponent("\(base.lastPathComponent)-\(n)")
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }

    private func commit() {
        guard let repo = selectedRepo else { return }
        guard svc.isGitRepo(at: repo.root) else {
            errorMessage = "‘\(repo.displayName)’ isn't a git repository — its folder is missing a .git. Remove it from Parallel (right-click in the sidebar) and add a real repo."
            return
        }
        let raw = repo.root.appendingPathComponent(repo.worktreeBaseDir)
            .appendingPathComponent(sanitizedName)
        let path = uniquePath(base: raw)
        let lines = setupCommands.nonEmptyLines()
        do {
            try svc.add(repoRoot: repo.root, branch: branch, base: base,
                        path: path, createBranch: createBranch)
            let wt = Worktree(repoId: repo.id, path: path, branch: branch,
                              displayName: displayName.isEmpty ? sanitizedName : displayName,
                              setupCommands: lines)
            store.addWorktree(wt)
            store.recordBase(repoId: repo.id, base: base)
            sessionManager.ensureSession(for: wt, setupCommands: lines)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
