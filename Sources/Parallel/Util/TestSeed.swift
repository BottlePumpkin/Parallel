import Foundation

/// Deterministic workspace seeding for e2e tests. When `PARALLEL_E2E_SEED`
/// names a JSON file, the described repos/worktrees are loaded into the store
/// at launch, bypassing the native folder picker. Plain string paths keep the
/// test-side schema simple.
enum TestSeed {
    struct Spec: Decodable {
        struct SeedRepo: Decodable {
            var root: String
            var displayName: String

            init(root: String, displayName: String) {
                self.root = root
                self.displayName = displayName
            }
        }
        struct SeedWorktree: Decodable {
            var repoIndex: Int
            var path: String
            var branch: String
            var displayName: String

            init(repoIndex: Int, path: String, branch: String, displayName: String) {
                self.repoIndex = repoIndex
                self.path = path
                self.branch = branch
                self.displayName = displayName
            }
        }
        var repos: [SeedRepo]
        var worktrees: [SeedWorktree]

        init(repos: [SeedRepo], worktrees: [SeedWorktree]) {
            self.repos = repos
            self.worktrees = worktrees
        }
    }

    /// Decode + apply the seed file named by `PARALLEL_E2E_SEED`, if present and
    /// the store is still empty.
    static func applyIfNeeded(
        to store: WorkspaceStore,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) {
        guard store.repos.isEmpty,
              let path = env["PARALLEL_E2E_SEED"], !path.isEmpty,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let spec = try? JSONDecoder().decode(Spec.self, from: data)
        else { return }
        apply(spec, to: store)
    }

    /// Build Repo/Worktree models from the spec and insert them.
    static func apply(_ spec: Spec, to store: WorkspaceStore) {
        var repoIds: [UUID] = []
        for r in spec.repos {
            let repo = Repo(root: URL(fileURLWithPath: r.root), displayName: r.displayName)
            store.addRepo(repo)
            repoIds.append(repo.id)
        }
        for w in spec.worktrees where w.repoIndex >= 0 && w.repoIndex < repoIds.count {
            let wt = Worktree(
                repoId: repoIds[w.repoIndex],
                path: URL(fileURLWithPath: w.path),
                branch: w.branch,
                displayName: w.displayName
            )
            store.addWorktree(wt)
        }
    }
}
