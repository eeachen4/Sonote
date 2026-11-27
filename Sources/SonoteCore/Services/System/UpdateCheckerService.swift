import Foundation

public struct AppUpdateCheckResult: Equatable, Sendable {
    public var currentVersion: String
    public var latestVersion: String
    public var hasUpdate: Bool
    public var releaseURL: String
    public var releaseNotes: String

    public init(
        currentVersion: String,
        latestVersion: String,
        hasUpdate: Bool,
        releaseURL: String,
        releaseNotes: String = ""
    ) {
        self.currentVersion = currentVersion
        self.latestVersion = latestVersion
        self.hasUpdate = hasUpdate
        self.releaseURL = releaseURL
        self.releaseNotes = releaseNotes
    }
}

public enum UpdateCheckerError: LocalizedError {
    case invalidEndpoint
    case httpError(Int)
    case invalidPayload

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint: return SonoteLocale.t("无效的更新检查地址", "Invalid update check endpoint")
        case .httpError(let code): return SonoteLocale.t("检查更新失败 (HTTP \(code))", "Update check failed (HTTP \(code))")
        case .invalidPayload: return SonoteLocale.t("无法解析 GitHub Release 信息", "Could not parse GitHub Release payload")
        }
    }
}

/// Lightweight, zero-dependency GitHub Releases update checker for Sonote.
public enum UpdateCheckerService {
    public static let defaultRepoSlug = "eeachen4/Sonote"

    public static var installedVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.6.0"
    }

    public static func checkLatestRelease(
        currentVersion: String = installedVersion,
        repoSlug: String = defaultRepoSlug
    ) async throws -> AppUpdateCheckResult {
        let urlString = "https://api.github.com/repos/\(repoSlug)/releases/latest"
        guard let url = URL(string: urlString) else {
            throw UpdateCheckerError.invalidEndpoint
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Sonote/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UpdateCheckerError.invalidPayload
        }
        guard (200...299).contains(http.statusCode) else {
            throw UpdateCheckerError.httpError(http.statusCode)
        }
        guard let result = parseGitHubReleaseJSON(data, currentVersion: currentVersion, repoSlug: repoSlug) else {
            throw UpdateCheckerError.invalidPayload
        }
        return result
    }

    public static func parseGitHubReleaseJSON(
        _ data: Data,
        currentVersion: String,
        repoSlug: String = defaultRepoSlug
    ) -> AppUpdateCheckResult? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = (json["tag_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !tag.isEmpty else {
            return nil
        }
        let htmlURL = (json["html_url"] as? String) ?? "https://github.com/\(repoSlug)/releases"
        let body = (json["body"] as? String) ?? ""
        let normalizedCurrent = normalizeVersion(currentVersion)
        let normalizedLatest = normalizeVersion(tag)
        let hasUpdate = compareSemanticVersions(normalizedCurrent, normalizedLatest) == .orderedAscending
        return AppUpdateCheckResult(
            currentVersion: normalizedCurrent,
            latestVersion: normalizedLatest,
            hasUpdate: hasUpdate,
            releaseURL: htmlURL,
            releaseNotes: body
        )
    }

    public static func normalizeVersion(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("v") || s.hasPrefix("V") {
            s.removeFirst()
        }
        if let dash = s.firstIndex(of: "-") {
            s = String(s[..<dash])
        }
        return s
    }

    /// Compares dot-separated semantic versions (e.g. `"1.5.1"` vs `"1.6.0"`).
    public static func compareSemanticVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let a = normalizeVersion(lhs).split(separator: ".").map { Int($0) ?? 0 }
        let b = normalizeVersion(rhs).split(separator: ".").map { Int($0) ?? 0 }
        let count = max(a.count, b.count)
        for i in 0..<count {
            let va = i < a.count ? a[i] : 0
            let vb = i < b.count ? b[i] : 0
            if va < vb { return .orderedAscending }
            if va > vb { return .orderedDescending }
        }
        return .orderedSame
    }
}
