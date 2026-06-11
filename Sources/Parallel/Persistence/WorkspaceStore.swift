import Foundation
import Observation

@Observable
final class WorkspaceStore {
    var repos: [Repo] = []
    var worktrees: [Worktree] = []
    var lastSelectedWorktreeId: UUID?
    /// Per-worktree persisted tab strip: how many shells and what labels.
    /// Restored by SessionManager.ensureSession on first visit after restart.
    var tabSpecsByWorktree: [UUID: [TabSpec]] = [:]
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
        /// String-keyed because JSON dict keys must be strings.
        /// Backward-compatible: nil when loading old workspace.json.
        var tabSpecsByWorktree: [String: [TabSpec]]?
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
            self.tabSpecsByWorktree = Dictionary(
                uniqueKeysWithValues: (payload.tabSpecsByWorktree ?? [:])
                    .compactMap { (key, value) in
                        UUID(uuidString: key).map { ($0, value) }
                    }
            )
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
        let tabSpecsJSON = Dictionary(uniqueKeysWithValues:
            tabSpecsByWorktree.map { ($0.key.uuidString, $0.value) }
        )
        let payload = Payload(version: 1, repos: repos, worktrees: worktrees,
                              lastSelectedWorktreeId: lastSelectedWorktreeId,
                              tabSpecsByWorktree: tabSpecsJSON.isEmpty ? nil : tabSpecsJSON)
        let data = try JSONEncoder.iso.encode(payload)
        try data.write(to: fileURL, options: .atomic)
    }

    func addRepo(_ repo: Repo) {
        AppLogger.store.info("addRepo \(repo.displayName, privacy: .public)")
        repos.append(repo)
        try? save()
    }

    func addWorktree(_ wt: Worktree) {
        AppLogger.store.info("addWorktree \(wt.displayName, privacy: .public) branch=\(wt.branch, privacy: .public)")
        worktrees.append(wt)
        try? save()
    }

    func removeWorktree(id: UUID) {
        AppLogger.store.info("removeWorktree id=\(id, privacy: .public)")
        worktrees.removeAll { $0.id == id }
        tabSpecsByWorktree.removeValue(forKey: id)
        if lastSelectedWorktreeId == id { lastSelectedWorktreeId = nil }
        try? save()
    }

    func removeRepo(id: UUID) {
        AppLogger.store.info("removeRepo id=\(id, privacy: .public)")
        let goneWorktreeIds = worktrees.filter { $0.repoId == id }.map(\.id)
        worktrees.removeAll { $0.repoId == id }
        for wid in goneWorktreeIds { tabSpecsByWorktree.removeValue(forKey: wid) }
        repos.removeAll { $0.id == id }
        try? save()
    }

    // MARK: - Tab spec mutations (called by SessionManager)

    func tabSpecs(for worktreeId: UUID) -> [TabSpec] {
        tabSpecsByWorktree[worktreeId] ?? []
    }

    func appendTabSpec(worktreeId: UUID, label: String? = nil) {
        var list = tabSpecsByWorktree[worktreeId] ?? []
        list.append(TabSpec(label: label))
        tabSpecsByWorktree[worktreeId] = list
        try? save()
    }

    func removeTabSpec(worktreeId: UUID, at index: Int) {
        guard var list = tabSpecsByWorktree[worktreeId],
              index >= 0, index < list.count else { return }
        list.remove(at: index)
        if list.isEmpty {
            tabSpecsByWorktree.removeValue(forKey: worktreeId)
        } else {
            tabSpecsByWorktree[worktreeId] = list
        }
        try? save()
    }

    func updateTabSpec(worktreeId: UUID, at index: Int, label: String?) {
        guard var list = tabSpecsByWorktree[worktreeId],
              index >= 0, index < list.count else { return }
        guard list[index].label != label else { return }
        list[index].label = label
        tabSpecsByWorktree[worktreeId] = list
        try? save()
    }

    func worktree(id: UUID) -> Worktree? {
        worktrees.first { $0.id == id }
    }

    /// Standardized paths of worktrees already tracked under `repoId`, for
    /// dedup checks when importing or adding worktrees.
    func registeredPaths(for repoId: UUID) -> Set<URL> {
        Set(
            worktrees
                .filter { $0.repoId == repoId }
                .map { $0.path.standardizedFileURL }
        )
    }

    /// Push `base` to the front of the repo's MRU base list (dedup, capped at 5).
    func recordBase(repoId: UUID, base: String) {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = repos.firstIndex(where: { $0.id == repoId }) else { return }
        var bases = repos[idx].recentBases
        bases.removeAll { $0 == trimmed }
        bases.insert(trimmed, at: 0)
        if bases.count > 5 { bases = Array(bases.prefix(5)) }
        guard repos[idx].recentBases != bases else { return }
        repos[idx].recentBases = bases
        try? save()
    }

    /// Reorder repo groups in the sidebar.
    func moveRepos(from offsets: IndexSet, to destination: Int) {
        repos.move(fromOffsets: offsets, toOffset: destination)
        try? save()
    }

    /// Reorder worktrees belonging to `repoId`. Indices are in the section's
    /// filtered view (as ForEach.onMove passes them); they're translated into
    /// the full `worktrees` array here so other repos' ordering is preserved.
    func moveWorktrees(in repoId: UUID, from offsets: IndexSet, to destination: Int) {
        let repoIndices = worktrees.enumerated()
            .filter { $0.element.repoId == repoId }
            .map { $0.offset }
        guard !repoIndices.isEmpty else { return }
        let sourceFullIndices = offsets.map { repoIndices[$0] }
        let destFullIndex = destination < repoIndices.count
            ? repoIndices[destination]
            : (repoIndices.last.map { $0 + 1 } ?? worktrees.count)
        worktrees.move(fromOffsets: IndexSet(sourceFullIndices), toOffset: destFullIndex)
        try? save()
    }

    func rename(worktreeId: UUID, to displayName: String) {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = worktrees.firstIndex(where: { $0.id == worktreeId }),
              worktrees[idx].displayName != trimmed
        else { return }
        worktrees[idx].displayName = trimmed
        try? save()
    }
}

private extension JSONEncoder {
    static let iso: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}

private extension JSONDecoder {
    static let iso: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
