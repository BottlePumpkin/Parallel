import Foundation
import Observation

struct UpdateInfo: Equatable {
    let latestTag: String
    let latestVersion: SemanticVersion
    let releaseURL: URL
    let releaseNotes: String
    let publishedAt: Date
}

enum UpdateCheckResult {
    case upToDate(current: SemanticVersion)
    case available(UpdateInfo)
    case failed(Error)
}

enum UpdateCheckError: Error, LocalizedError {
    case http(Int)
    case unparseableTag(String)

    var errorDescription: String? {
        switch self {
        case .http(let code): return "GitHub returned HTTP \(code)."
        case .unparseableTag(let tag): return "Couldn't read tag \"\(tag)\" as a version."
        }
    }
}

/// Polls GitHub Releases for a newer published tag. Auto-paced on app
/// start (cache TTL 6h) and re-runnable on demand from the menu.
@Observable
@MainActor
final class UpdateChecker {
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/BottlePumpkin/Parallel/releases/latest")!
    static let cacheTTL: TimeInterval = 6 * 60 * 60

    /// Published only when the result is newer AND not skipped. Drives the
    /// startup sheet presentation.
    var updateAvailable: UpdateInfo?
    /// Last raw result regardless of skip state. Drives manual-check UI.
    var lastCheckResult: UpdateCheckResult?
    /// True while a network request is in flight; menu sheet binds to it
    /// to show a spinner.
    var isChecking = false

    private let session: URLSession
    private let defaults: UserDefaults
    private let currentVersionProvider: () -> SemanticVersion

    init(session: URLSession = .shared,
         defaults: UserDefaults = .standard,
         currentVersionProvider: @escaping () -> SemanticVersion = { AppVersion.current }) {
        self.session = session
        self.defaults = defaults
        self.currentVersionProvider = currentVersionProvider
    }

    /// Called from ContentView.task at launch. Skips when the last check
    /// was inside cacheTTL.
    func checkIfStale() async {
        if let last = defaults.lastUpdateCheckAt,
           Date().timeIntervalSince(last) < Self.cacheTTL {
            return
        }
        await check(force: false)
    }

    /// `force: true` bypasses both cache and skipped-version filter.
    func check(force: Bool) async {
        isChecking = true
        defer { isChecking = false }

        var request = URLRequest(url: Self.latestReleaseURL, timeoutInterval: 5)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            lastCheckResult = .failed(error)
            return
        }

        guard let http = response as? HTTPURLResponse else {
            lastCheckResult = .failed(UpdateCheckError.http(-1))
            return
        }
        guard http.statusCode == 200 else {
            lastCheckResult = .failed(UpdateCheckError.http(http.statusCode))
            return
        }

        defaults.lastUpdateCheckAt = Date()

        let payload: ReleasePayload
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            payload = try decoder.decode(ReleasePayload.self, from: data)
        } catch {
            lastCheckResult = .failed(error)
            return
        }

        guard let latest = SemanticVersion(payload.tagName) else {
            lastCheckResult = .failed(UpdateCheckError.unparseableTag(payload.tagName))
            return
        }

        let current = currentVersionProvider()
        if latest > current {
            let info = UpdateInfo(
                latestTag: payload.tagName,
                latestVersion: latest,
                releaseURL: payload.htmlUrl,
                releaseNotes: payload.body ?? "",
                publishedAt: payload.publishedAt
            )
            lastCheckResult = .available(info)
            if force || defaults.skippedUpdateVersion != latest.description {
                updateAvailable = info
            } else {
                updateAvailable = nil
            }
        } else {
            lastCheckResult = .upToDate(current: current)
            updateAvailable = nil
        }
    }

    func skip(_ version: SemanticVersion) {
        defaults.skippedUpdateVersion = version.description
        updateAvailable = nil
    }
}

private struct ReleasePayload: Decodable {
    let tagName: String
    let htmlUrl: URL
    let body: String?
    let publishedAt: Date
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
        case body
        case publishedAt = "published_at"
    }
}
