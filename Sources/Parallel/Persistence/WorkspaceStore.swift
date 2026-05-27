import Foundation
import Observation

@Observable
final class WorkspaceStore {
    var repos: [Repo] = []
    var worktrees: [Worktree] = []
    var lastSelectedWorktreeId: UUID?
    /// Ephemeral worktree status (not persisted). StatusWatcher populates this.
    var statuses: [UUID: WorktreeStatus] = [:]

    private let directory: URL
    private let fileName = "workspace.json"

    init(directory: URL) {
        self.directory = directory
    }

    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Parallel", isDirectory: true)
    }

    private struct Payload: Codable {
        var version: Int
        var repos: [Repo]
        var worktrees: [Worktree]
        var lastSelectedWorktreeId: UUID?
    }

    private var fileURL: URL { directory.appendingPathComponent(fileName) }

    func load() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let data = try Data(contentsOf: fileURL)
        do {
            let payload = try JSONDecoder.iso.decode(Payload.self, from: data)
            self.repos = payload.repos
            self.worktrees = payload.worktrees
            self.lastSelectedWorktreeId = payload.lastSelectedWorktreeId
            let merged = dedupe()
            if merged { try? save() }
        } catch {
            AppLogger.store.error("workspace.json corrupt: \(error.localizedDescription, privacy: .public)")
            let stamp = Int(Date().timeIntervalSince1970)
            let quarantine = directory.appendingPathComponent("workspace.json.corrupted-\(stamp)")
            try? FileManager.default.moveItem(at: fileURL, to: quarantine)
            self.repos = []
            self.worktrees = []
            self.lastSelectedWorktreeId = nil
        }
    }

    /// One-shot migration: merge duplicate Repos that share the same root path
    /// (caused by an earlier bug in AddRepoSheet), and drop duplicate worktree
    /// paths within a repo. Returns true if anything changed.
    @discardableResult
    private func dedupe() -> Bool {
        var changed = false

        // 1. Repos: keep the first Repo per standardized root URL; rewrite
        //    worktree.repoId to point at the kept repo, then drop duplicates.
        var keptRepoByPath: [URL: UUID] = [:]
        var repoIdRemap: [UUID: UUID] = [:]
        var dedupedRepos: [Repo] = []
        for repo in repos {
            let key = repo.root.standardizedFileURL
            if let keptId = keptRepoByPath[key] {
                repoIdRemap[repo.id] = keptId
                changed = true
            } else {
                keptRepoByPath[key] = repo.id
                dedupedRepos.append(repo)
            }
        }
        if changed {
            repos = dedupedRepos
            worktrees = worktrees.map { wt in
                guard let newId = repoIdRemap[wt.repoId] else { return wt }
                var copy = wt
                copy.repoId = newId
                return copy
            }
        }

        // 2. Worktrees: drop duplicates with the same standardized path within
        //    the same repo. Keep the first occurrence.
        var seen: Set<String> = []
        var dedupedWTs: [Worktree] = []
        for wt in worktrees {
            let key = "\(wt.repoId)::\(wt.path.standardizedFileURL.path)"
            if seen.contains(key) {
                changed = true
                continue
            }
            seen.insert(key)
            dedupedWTs.append(wt)
        }
        if dedupedWTs.count != worktrees.count {
            worktrees = dedupedWTs
        }

        // 3. Drop worktrees that point at a vanished repoId (shouldn't happen
        //    after step 1, but defensive).
        let validRepoIds = Set(repos.map { $0.id })
        let before = worktrees.count
        worktrees.removeAll { !validRepoIds.contains($0.repoId) }
        if worktrees.count != before { changed = true }

        return changed
    }

    func save() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let payload = Payload(version: 1, repos: repos, worktrees: worktrees,
                              lastSelectedWorktreeId: lastSelectedWorktreeId)
        let data = try JSONEncoder.iso.encode(payload)
        try data.write(to: fileURL, options: .atomic)
    }

    func addRepo(_ repo: Repo) {
        repos.append(repo)
        try? save()
    }

    func addWorktree(_ wt: Worktree) {
        worktrees.append(wt)
        try? save()
    }

    func removeWorktree(id: UUID) {
        worktrees.removeAll { $0.id == id }
        if lastSelectedWorktreeId == id { lastSelectedWorktreeId = nil }
        try? save()
    }

    func removeRepo(id: UUID) {
        worktrees.removeAll { $0.repoId == id }
        repos.removeAll { $0.id == id }
        try? save()
    }

    func worktree(id: UUID) -> Worktree? {
        worktrees.first { $0.id == id }
    }
}

private extension JSONEncoder {
    static var iso: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}

private extension JSONDecoder {
    static var iso: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
