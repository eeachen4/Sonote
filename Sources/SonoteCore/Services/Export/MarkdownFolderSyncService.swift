import Foundation

public struct MarkdownFolderSyncResult: Equatable, Sendable {
    public var syncedCount: Int
    public var lastFileURL: URL?
    public var errorMessage: String?

    public var isSuccess: Bool { errorMessage == nil }

    public init(syncedCount: Int = 0, lastFileURL: URL? = nil, errorMessage: String? = nil) {
        self.syncedCount = syncedCount
        self.lastFileURL = lastFileURL
        self.errorMessage = errorMessage
    }
}

/// Automatically exports meeting minutes as Obsidian / Logseq-compatible Markdown files
/// with structured YAML frontmatter (`title`, `date`, `duration`, `tags`, `participants`, `meeting_id`).
public final class MarkdownFolderSyncService: @unchecked Sendable {
    public static let shared = MarkdownFolderSyncService()
    private init() {}

    /// Builds a complete Obsidian / Logseq-friendly Markdown document with YAML frontmatter.
    public func renderObsidianMarkdown(for meeting: MeetingSession) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        let cleanTitle = meeting.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleValue = cleanTitle.isEmpty ? "Untitled Meeting" : cleanTitle

        var frontmatter: [String] = [
            "---",
            "title: \"\(escapeYAML(titleValue))\"",
            "date: \(iso.string(from: meeting.startedAt))",
            "duration: \"\(escapeYAML(meeting.formattedDuration))\"",
            "source: \"\(escapeYAML(meeting.sourceAppName))\"",
            "template: \"\(escapeYAML(meeting.template.rawValue))\"",
            "meeting_id: \"\(meeting.id.uuidString)\""
        ]

        let allTags = Array(Set(meeting.tags + ["sonote", "meeting-minutes"])).sorted()
        frontmatter.append("tags:")
        for tag in allTags {
            let safeTag = tag.replacingOccurrences(of: " ", with: "-")
            frontmatter.append("  - \(safeTag)")
        }

        let participants = Array(Set(meeting.minutes.participants + meeting.calendarAttendees + meeting.distinctSpeakerNames))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "发言人" && !$0.hasPrefix("发言人 ") }
            .sorted()
        if !participants.isEmpty {
            frontmatter.append("participants:")
            for p in participants {
                frontmatter.append("  - \"\(escapeYAML(p))\"")
            }
        }
        frontmatter.append("---")
        frontmatter.append("")

        let body = MeetingStore.exportMarkdown(for: meeting, includeTranscript: true)
        return frontmatter.joined(separator: "\n") + body
    }

    /// Writes or updates a single meeting's `.md` note inside `folderPath`.
    /// If an existing `.md` in the folder contains the same `meeting_id:` frontmatter, updates it in-place.
    @discardableResult
    public func sync(meeting: MeetingSession, toFolder folderPath: String) -> MarkdownFolderSyncResult {
        let expanded = (folderPath as NSString).expandingTildeInPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expanded.isEmpty else {
            return MarkdownFolderSyncResult(syncedCount: 0, errorMessage: "Folder path is empty")
        }

        let folderURL = URL(fileURLWithPath: expanded, isDirectory: true)
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)
        } catch {
            return MarkdownFolderSyncResult(syncedCount: 0, errorMessage: error.localizedDescription)
        }

        let targetURL = existingFileURL(for: meeting.id, in: folderURL) ?? defaultFileURL(for: meeting, in: folderURL)
        let content = renderObsidianMarkdown(for: meeting)

        do {
            try content.write(to: targetURL, atomically: true, encoding: .utf8)
            return MarkdownFolderSyncResult(syncedCount: 1, lastFileURL: targetURL)
        } catch {
            return MarkdownFolderSyncResult(syncedCount: 0, errorMessage: error.localizedDescription)
        }
    }

    /// Exports all completed meetings to `folderPath`.
    @discardableResult
    public func syncAll(meetings: [MeetingSession], toFolder folderPath: String) -> MarkdownFolderSyncResult {
        let expanded = (folderPath as NSString).expandingTildeInPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expanded.isEmpty else {
            return MarkdownFolderSyncResult(syncedCount: 0, errorMessage: "Folder path is empty")
        }

        var count = 0
        var lastURL: URL?
        for meeting in meetings where !meeting.minutes.isEmpty || !meeting.segments.isEmpty {
            let res = sync(meeting: meeting, toFolder: expanded)
            if let err = res.errorMessage {
                return MarkdownFolderSyncResult(syncedCount: count, lastFileURL: lastURL, errorMessage: err)
            }
            count += res.syncedCount
            if let url = res.lastFileURL {
                lastURL = url
            }
        }
        return MarkdownFolderSyncResult(syncedCount: count, lastFileURL: lastURL)
    }

    // MARK: - Helpers

    private func existingFileURL(for meetingID: UUID, in folderURL: URL) -> URL? {
        let marker = "meeting_id: \"\(meetingID.uuidString)\""
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        for url in urls where url.pathExtension.lowercased() == "md" {
            if let head = try? String(contentsOf: url, encoding: .utf8).prefix(1024),
               head.contains(marker) {
                return url
            }
        }
        return nil
    }

    public func defaultFileURL(for meeting: MeetingSession, in folderURL: URL) -> URL {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let datePrefix = df.string(from: meeting.startedAt)
        let safeTitle = sanitizeFileName(meeting.title)
        let shortID = String(meeting.id.uuidString.prefix(6)).lowercased()
        let baseName = "\(datePrefix) \(safeTitle)"
        let primary = folderURL.appendingPathComponent("\(baseName).md")
        if !FileManager.default.fileExists(atPath: primary.path) {
            return primary
        }
        return folderURL.appendingPathComponent("\(baseName)-\(shortID).md")
    }

    private func sanitizeFileName(_ raw: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = raw
            .components(separatedBy: invalid)
            .joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return "Meeting Minutes" }
        return String(cleaned.prefix(64))
    }

    private func escapeYAML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
