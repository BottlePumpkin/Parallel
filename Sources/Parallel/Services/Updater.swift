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
        guard assetURL.scheme == "https" else {
            phase = .failed("Refusing to download over an insecure (non-HTTPS) connection.")
            return
        }
        task?.cancel()
        task = Task { [weak self] in
            await self?.run(assetURL: assetURL,
                            expectedVersion: info.latestVersion,
                            target: target,
                            session: session)
        }
    }

    private func run(assetURL: URL, expectedVersion: SemanticVersion, target: URL, session: URLSession) async {
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
            try await Task.detached {
                try Updater.runProcess("/usr/bin/ditto", ["-x", "-k", zipURL.path, unpackDir.path])
            }.value
            let newApp = unpackDir.appendingPathComponent("Parallel.app")
            guard FileManager.default.fileExists(atPath: newApp.path) else {
                throw UpdaterError.message("Downloaded archive didn't contain Parallel.app.")
            }

            phase = .verifying
            guard let gotStr = Self.bundleShortVersion(at: newApp), let got = SemanticVersion(gotStr) else {
                throw UpdaterError.message("Couldn't read the downloaded build's version.")
            }
            guard got == expectedVersion else {
                throw UpdaterError.message("Version mismatch: expected \(expectedVersion.description), got \(gotStr).")
            }
            // Best-effort: a download may carry the quarantine xattr.
            try? await Task.detached {
                try Updater.runProcess("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])
            }.value

            phase = .installing
            try swap(target: target, with: newApp)

            phase = .relaunching
            try relaunch(bundleURL: target)
            NSApp.terminate(nil)
        } catch {
            // URLSession.download throws URLError.cancelled (not CancellationError)
            // when its Task is cancelled, so check both before reporting failure.
            if Task.isCancelled || (error as? URLError)?.code == .cancelled || error is CancellationError {
                phase = .idle
            } else {
                phase = .failed((error as? UpdaterError)?.text ?? error.localizedDescription)
            }
        }
    }

    /// Downloads `url` to `dest` using a download task so progress comes from
    /// Content-Length rather than per-byte iteration; respects Task cancellation.
    private func download(_ url: URL, to dest: URL, session: URLSession) async throws {
        let delegate = DownloadProgressDelegate { [weak self] fraction in
            Task { @MainActor in
                guard let self else { return }
                if case .downloading = self.phase { self.phase = .downloading(fraction: fraction) }
            }
        }
        let (tempURL, response) = try await session.download(from: url, delegate: delegate)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw UpdaterError.message("Download failed (HTTP \(http.statusCode)).")
        }
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: tempURL, to: dest)
    }

    /// Atomic in-place replacement. Stages the new bundle next to the target
    /// (same volume) so `replaceItemAt` can swap atomically. Cleans up staging
    /// on any failure.
    private func swap(target: URL, with newApp: URL) throws {
        let parent = target.deletingLastPathComponent()
        let staging = parent.appendingPathComponent(".Parallel.app.new-\(UUID().uuidString)")
        do {
            do {
                try FileManager.default.moveItem(at: newApp, to: staging)
            } catch {
                try FileManager.default.copyItem(at: newApp, to: staging)
            }
            _ = try FileManager.default.replaceItemAt(target, withItemAt: staging,
                                                      backupItemName: nil,
                                                      options: [.usingNewMetadataOnly])
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    /// Detached helper waits for this process to exit, then opens the new bundle.
    /// Throws if the helper can't be launched (caller must then NOT terminate).
    private func relaunch(bundleURL: URL) throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c",
                       "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; open \"$1\"",
                       "sh", bundleURL.path]
        do {
            try p.run()
        } catch {
            throw UpdaterError.message("Update installed — quit and reopen Parallel to finish.")
        }
    }

    nonisolated private static func runProcess(_ launchPath: String, _ args: [String]) throws {
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

/// Per-task download delegate that reports a 0...1 fraction.
private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: (Double) -> Void
    init(onProgress: @escaping (Double) -> Void) { self.onProgress = onProgress }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // The async download(from:delegate:) variant retains the file; nothing to do here.
    }
}
