import Foundation
import AppKit
import Observation

enum UpdaterError: Error {
    case message(String)
    var text: String {
        if case .message(let m) = self { return m }
        return "Update failed."
    }
}

/// Downloads a release zip, verifies it, atomically replaces the running bundle
/// in place, and relaunches. The pure `bundleShortVersion` helper is unit-tested;
/// the side-effecting pipeline (network, ditto, file swap, relaunch) is verified
/// manually, like SessionManager.
@MainActor
@Observable
final class Updater {
    enum Phase: Equatable {
        case idle
        case downloading(fraction: Double)
        case unpacking
        case verifying
        case installing
        case relaunching
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private var task: Task<Void, Never>?

    /// Reads `CFBundleShortVersionString` from a `.app` bundle URL. Pure.
    nonisolated static func bundleShortVersion(at bundleURL: URL) -> String? {
        let plist = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let obj = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = obj as? [String: Any] else { return nil }
        return dict["CFBundleShortVersionString"] as? String
    }

    func cancel() {
        task?.cancel()
        phase = .idle
    }

    func update(from info: UpdateInfo, target: URL, session: URLSession = .shared) {
        guard let assetURL = info.assetURL else {
            phase = .failed("This release has no downloadable build attached.")
            return
        }
        task = Task { [weak self] in
            await self?.run(assetURL: assetURL,
                            expectedVersion: info.latestVersion.description,
                            target: target,
                            session: session)
        }
    }

    private func run(assetURL: URL, expectedVersion: String, target: URL, session: URLSession) async {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ParallelUpdate-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            phase = .downloading(fraction: 0)
            let zipURL = tempDir.appendingPathComponent("Parallel.zip")
            try await download(assetURL, to: zipURL, session: session)
            try Task.checkCancellation()

            phase = .unpacking
            let unpackDir = tempDir.appendingPathComponent("unpacked", isDirectory: true)
            try FileManager.default.createDirectory(at: unpackDir, withIntermediateDirectories: true)
            try runProcess("/usr/bin/ditto", ["-x", "-k", zipURL.path, unpackDir.path])
            let newApp = unpackDir.appendingPathComponent("Parallel.app")
            guard FileManager.default.fileExists(atPath: newApp.path) else {
                throw UpdaterError.message("Downloaded archive didn't contain Parallel.app.")
            }

            phase = .verifying
            let got = Self.bundleShortVersion(at: newApp)
            guard got == expectedVersion else {
                throw UpdaterError.message("Version mismatch: expected \(expectedVersion), got \(got ?? "unknown").")
            }
            // Best-effort: a download may carry the quarantine xattr.
            try? runProcess("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])

            phase = .installing
            try swap(target: target, with: newApp)

            phase = .relaunching
            relaunch(bundleURL: target)
            NSApp.terminate(nil)
        } catch is CancellationError {
            phase = .idle
        } catch {
            phase = .failed((error as? UpdaterError)?.text ?? error.localizedDescription)
        }
    }

    /// Streams the asset to `dest`, publishing download fraction when the server
    /// reports a content length.
    private func download(_ url: URL, to dest: URL, session: URLSession) async throws {
        let (bytes, response) = try await session.bytes(from: url)
        let total = response.expectedContentLength
        FileManager.default.createFile(atPath: dest.path, contents: nil)
        let handle = try FileHandle(forWritingTo: dest)
        defer { try? handle.close() }
        var buffer = Data()
        buffer.reserveCapacity(262_144)
        var received: Int64 = 0
        for try await byte in bytes {
            buffer.append(byte)
            received += 1
            if buffer.count >= 262_144 {
                try handle.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
                if total > 0 { phase = .downloading(fraction: Double(received) / Double(total)) }
                try Task.checkCancellation()
            }
        }
        if !buffer.isEmpty { try handle.write(contentsOf: buffer) }
    }

    /// Atomic in-place replacement. Stages the new bundle next to the target
    /// (same volume) so `replaceItemAt` can swap atomically.
    private func swap(target: URL, with newApp: URL) throws {
        let parent = target.deletingLastPathComponent()
        let staging = parent.appendingPathComponent(".Parallel.app.new-\(UUID().uuidString)")
        do {
            try FileManager.default.moveItem(at: newApp, to: staging)
        } catch {
            // Cross-volume move can fail; fall back to copy.
            try FileManager.default.copyItem(at: newApp, to: staging)
        }
        do {
            _ = try FileManager.default.replaceItemAt(target, withItemAt: staging,
                                                      backupItemName: nil,
                                                      options: [.usingNewMetadataOnly])
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    /// Detached helper waits for this process to exit, then opens the new bundle.
    private func relaunch(bundleURL: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; open \"\(bundleURL.path)\""
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script]
        try? p.run()  // detached; do not wait
    }

    private func runProcess(_ launchPath: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw UpdaterError.message("\(launchPath) exited \(p.terminationStatus).")
        }
    }
}
