import Foundation
import Observation

@Observable
final class WorkspaceStore {
    var repos: [Repo] = []
    var worktrees: [Worktree] = []
    var lastSelectedWorktreeId: UUID?

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
        } catch {
            let stamp = Int(Date().timeIntervalSince1970)
            let quarantine = directory.appendingPathComponent("workspace.json.corrupted-\(stamp)")
            try? FileManager.default.moveItem(at: fileURL, to: quarantine)
            self.repos = []
            self.worktrees = []
            self.lastSelectedWorktreeId = nil
        }
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
