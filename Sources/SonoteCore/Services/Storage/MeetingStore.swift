import Foundation

public struct AudioStorageStats: Equatable, Sendable {
    public var fileCount: Int
    public var totalBytes: Int64

    public init(fileCount: Int = 0, totalBytes: Int64 = 0) {
        self.fileCount = fileCount
        self.totalBytes = totalBytes
    }

    public var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalBytes)
    }
}

public struct MeetingIndexEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var sourceAppName: String
    public var startedAt: Date
    public var endedAt: Date?
    public var duration: TimeInterval
    public var tags: [String]
    public var overviewPreview: String
    public var segmentCount: Int
    public var openActionItemCount: Int
    public var totalTokens: Int
    public var searchableText: String
    public var isPinned: Bool

    public init(from session: MeetingSession) {
        self.id = session.id
        self.title = session.title
        self.sourceAppName = session.sourceAppName
        self.startedAt = session.startedAt
        self.endedAt = session.endedAt
        self.duration = session.duration
        self.tags = session.tags
        let preview = session.minutes.overview.isEmpty
            ? (session.segments.first?.text ?? "")
            : session.minutes.overview
        self.overviewPreview = String(preview.prefix(180))
        self.segmentCount = session.segments.count
        self.openActionItemCount = session.minutes.actionItems.filter { !$0.isCompleted }.count
        self.totalTokens = session.tokenUsage.totalTokens
        self.isPinned = session.isPinned

        // Compact lowercased index string for fast offline search across hundreds of meetings
        var parts: [String] = [session.title, session.sourceAppName, session.minutes.overview]
        parts.append(contentsOf: session.tags)
        parts.append(contentsOf: session.minutes.decisions)
        parts.append(contentsOf: session.minutes.actionItems.map { "\($0.task) \($0.owner)" })
        parts.append(contentsOf: session.segments.prefix(40).map(\.text))
        self.searchableText = parts.joined(separator: " ").lowercased()
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        sourceAppName = try c.decodeIfPresent(String.self, forKey: .sourceAppName) ?? "手动记录"
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt)
        duration = try c.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        overviewPreview = try c.decodeIfPresent(String.self, forKey: .overviewPreview) ?? ""
        segmentCount = try c.decodeIfPresent(Int.self, forKey: .segmentCount) ?? 0
        openActionItemCount = try c.decodeIfPresent(Int.self, forKey: .openActionItemCount) ?? 0
        totalTokens = try c.decodeIfPresent(Int.self, forKey: .totalTokens) ?? 0
        searchableText = try c.decodeIfPresent(String.self, forKey: .searchableText) ?? ""
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }

    /// Creates a lightweight placeholder session from index metadata for instant Home startup
    /// before full transcript JSONs are hydrated on demand or in the background.
    public func toLightweightSession() -> MeetingSession {
        MeetingSession(
            id: id,
            title: title,
            sourceAppName: sourceAppName,
            startedAt: startedAt,
            endedAt: endedAt,
            duration: duration,
            status: .completed,
            minutes: SmartMinutes(overview: overviewPreview, isFinalized: true),
            tokenUsage: TokenUsage(inputTokens: totalTokens, outputTokens: 0, requestCount: totalTokens > 0 ? 1 : 0, isEstimated: true),
            tags: tags,
            isPinned: isPinned
        )
    }
}

public final class MeetingStore: @unchecked Sendable {
    public static let shared = MeetingStore()

    public let baseDirectory: URL
    public let meetingsDirectory: URL
    public let audioDirectory: URL
    public let settingsURL: URL
    public let tokenLedgerURL: URL
    public let meetingsIndexURL: URL

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let indexLock = NSLock()

    private static let migrationLock = NSLock()

    /// Resolves `~/Library/Application Support/Sonote` and transparently performs a one-time,
    /// non-destructive migration from legacy `~/Library/Application Support/TTMinutes` if present.
    public static func defaultBaseDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let sonoteDir = appSupport.appendingPathComponent("Sonote", isDirectory: true)
        let legacyDir = appSupport.appendingPathComponent("TTMinutes", isDirectory: true)
        migrateLegacyDirectoryIfNeeded(from: legacyDir, to: sonoteDir)
        return sonoteDir
    }

    /// Copies legacy app-support data into the new Sonote directory once (if destination does not exist)
    /// and rewrites stored `audioFilePath` links in migrated meeting JSON files so local playback keeps working.
    @discardableResult
    public static func migrateLegacyDirectoryIfNeeded(from legacyDir: URL, to newDir: URL) -> Bool {
        migrationLock.lock()
        defer { migrationLock.unlock() }

        let fm = FileManager.default
        guard !fm.fileExists(atPath: newDir.path),
              fm.fileExists(atPath: legacyDir.path) else {
            return false
        }

        do {
            try fm.createDirectory(at: newDir.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: legacyDir, to: newDir)
        } catch {
            return false
        }

        // Rewrite absolute audio paths inside migrated meeting JSONs from legacyDir -> newDir
        let meetingsDir = newDir.appendingPathComponent("meetings", isDirectory: true)
        let oldPrefix = legacyDir.standardizedFileURL.path
        let newPrefix = newDir.standardizedFileURL.path
        if let files = try? fm.contentsOfDirectory(at: meetingsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            enc.dateEncodingStrategy = .iso8601
            for url in files where url.pathExtension.lowercased() == "json" {
                guard let data = try? Data(contentsOf: url),
                      var session = try? dec.decode(MeetingSession.self, from: data),
                      let audioPath = session.audioFilePath,
                      audioPath.hasPrefix(oldPrefix) else { continue }
                let updated = newPrefix + audioPath.dropFirst(oldPrefix.count)
                if fm.fileExists(atPath: updated) {
                    session.audioFilePath = updated
                    if let out = try? enc.encode(session) {
                        try? out.write(to: url, options: .atomic)
                    }
                }
            }
        }
        return true
    }

    public init(baseDirectory: URL? = nil) {
        if let baseDirectory {
            self.baseDirectory = baseDirectory
        } else {
            self.baseDirectory = Self.defaultBaseDirectory()
        }
        self.meetingsDirectory = self.baseDirectory.appendingPathComponent("meetings", isDirectory: true)
        self.audioDirectory = self.baseDirectory.appendingPathComponent("audio", isDirectory: true)
        self.settingsURL = self.baseDirectory.appendingPathComponent("settings.json")
        self.tokenLedgerURL = self.baseDirectory.appendingPathComponent("token_ledger.json")
        self.meetingsIndexURL = self.baseDirectory.appendingPathComponent("meetings_index.json")

        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec

        ensureDirectories()
    }

    private func ensureDirectories() {
        let fm = FileManager.default
        try? fm.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try? fm.createDirectory(at: meetingsDirectory, withIntermediateDirectories: true)
        try? fm.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Settings Persistence (All Provider API Keys Stored Securely in macOS Keychain)

    private static let keychainAPIKeyAccount = "openai_api_key"
    private static let keychainDeepSeekKeyAccount = "deepseek_api_key"
    private static let keychainQwenKeyAccount = "dashscope_api_key"
    private static let keychainDomesticKeyAccount = "domestic_cloud_api_key"
    private static let keychainClaudeKeyAccount = "anthropic_api_key"
    private static let keychainGeminiKeyAccount = "google_gemini_api_key"
    private static let keychainWebhookSecretAccount = "webhook_signing_secret"

    public func loadSettings() -> AppSettings {
        var settings: AppSettings
        if let data = try? Data(contentsOf: settingsURL),
           let loaded = try? decoder.decode(AppSettings.self, from: data) {
            settings = loaded
        } else {
            settings = AppSettings()
        }

        // Migrate any legacy plaintext keys in settings.json into macOS Keychain
        var needsDiskSanitize = false
        func hydrateKey(_ current: inout String, account: String) {
            let plain = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !plain.isEmpty {
                _ = KeychainStore.shared.save(plain, account: account)
                needsDiskSanitize = true
            } else if let saved = KeychainStore.shared.read(account: account) {
                current = saved
            }
        }
        hydrateKey(&settings.apiKey, account: Self.keychainAPIKeyAccount)
        hydrateKey(&settings.deepSeekAPIKey, account: Self.keychainDeepSeekKeyAccount)
        hydrateKey(&settings.qwenAPIKey, account: Self.keychainQwenKeyAccount)
        hydrateKey(&settings.domesticAPIKey, account: Self.keychainDomesticKeyAccount)
        hydrateKey(&settings.claudeAPIKey, account: Self.keychainClaudeKeyAccount)
        hydrateKey(&settings.geminiAPIKey, account: Self.keychainGeminiKeyAccount)
        hydrateKey(&settings.webhookSecret, account: Self.keychainWebhookSecretAccount)

        if needsDiskSanitize {
            var sanitized = settings
            sanitized.apiKey = ""
            sanitized.deepSeekAPIKey = ""
            sanitized.qwenAPIKey = ""
            sanitized.domesticAPIKey = ""
            sanitized.claudeAPIKey = ""
            sanitized.geminiAPIKey = ""
            sanitized.webhookSecret = ""
            if let cleanData = try? encoder.encode(sanitized) {
                try? cleanData.write(to: settingsURL, options: .atomic)
            }
        }

        // Auto-populate local Codex default model if empty or stale
        let catalog = AuthManager.shared.discoverLocalCodexCatalog(authFilePath: settings.authFilePath)
        if settings.codexModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || (settings.codexModel == "gpt-5.4" && !catalog.availableModels.isEmpty && !catalog.availableModels.contains("gpt-5.4")) {
            if let detectedDefault = catalog.defaultModel {
                settings.codexModel = detectedDefault
            }
        }
        return settings
    }

    public func saveSettings(_ settings: AppSettings) {
        ensureDirectories()
        // Keep all provider API keys & webhook secrets in macOS Keychain, never write raw keys to settings.json on disk
        _ = KeychainStore.shared.save(settings.apiKey, account: Self.keychainAPIKeyAccount)
        _ = KeychainStore.shared.save(settings.deepSeekAPIKey, account: Self.keychainDeepSeekKeyAccount)
        _ = KeychainStore.shared.save(settings.qwenAPIKey, account: Self.keychainQwenKeyAccount)
        _ = KeychainStore.shared.save(settings.domesticAPIKey, account: Self.keychainDomesticKeyAccount)
        _ = KeychainStore.shared.save(settings.claudeAPIKey, account: Self.keychainClaudeKeyAccount)
        _ = KeychainStore.shared.save(settings.geminiAPIKey, account: Self.keychainGeminiKeyAccount)
        _ = KeychainStore.shared.save(settings.webhookSecret, account: Self.keychainWebhookSecretAccount)
        var diskSafe = settings
        diskSafe.apiKey = ""
        diskSafe.deepSeekAPIKey = ""
        diskSafe.qwenAPIKey = ""
        diskSafe.domesticAPIKey = ""
        diskSafe.claudeAPIKey = ""
        diskSafe.geminiAPIKey = ""
        diskSafe.webhookSecret = ""
        if let data = try? encoder.encode(diskSafe) {
            try? data.write(to: settingsURL, options: .atomic)
        }
    }

    // MARK: - Meetings Persistence

    public func audioBackupURL(for meetingID: UUID) -> URL {
        ensureDirectories()
        return audioDirectory.appendingPathComponent("\(meetingID.uuidString).m4a")
    }

    /// Detects meetings left in `.recording` or `.paused` state from an abnormal termination (crash/power loss).
    public func detectInterruptedMeetingIDs() -> [UUID] {
        ensureDirectories()
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: meetingsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var interrupted: [(id: UUID, startedAt: Date)] = []
        for url in urls where url.pathExtension.lowercased() == "json" {
            guard let data = try? Data(contentsOf: url),
                  let session = try? decoder.decode(MeetingSession.self, from: data) else { continue }
            if session.status == .recording || session.status == .paused {
                let hasData = !session.segments.isEmpty
                    || !session.manualNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || (session.audioFilePath != nil && FileManager.default.fileExists(atPath: session.audioFilePath!))
                if hasData {
                    interrupted.append((session.id, session.startedAt))
                }
            }
        }
        return interrupted.sorted { $0.startedAt > $1.startedAt }.map(\.id)
    }

    public func loadMeetings() -> [MeetingSession] {
        ensureDirectories()
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: meetingsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var sessions: [MeetingSession] = []
        for url in urls where url.pathExtension.lowercased() == "json" {
            guard let data = try? Data(contentsOf: url) else { continue }
            if var session = try? decoder.decode(MeetingSession.self, from: data) {
                // If app crashed mid-recording previously, mark cleanly as completed and persist once
                if session.status == .recording || session.status == .paused || session.status == .summarizing {
                    session.status = .completed
                    if let fixed = try? encoder.encode(session) {
                        try? fixed.write(to: url, options: .atomic)
                    }
                }
                sessions.append(session)
            }
        }
        let sorted = sessions.sorted { $0.startedAt > $1.startedAt }
        writeIndexEntries(sorted.map(MeetingIndexEntry.init(from:)))
        return sorted
    }

    /// Loads a single full `MeetingSession` by UUID on demand (O(1) file read).
    public func loadMeeting(id: UUID) -> MeetingSession? {
        let url = meetingsDirectory.appendingPathComponent("\(id.uuidString).json")
        guard let data = try? Data(contentsOf: url),
              var session = try? decoder.decode(MeetingSession.self, from: data) else {
            return nil
        }
        if session.status == .recording || session.status == .paused || session.status == .summarizing {
            session.status = .completed
        }
        return session
    }

    /// Fast O(1) metadata index read for instant startup and lightweight search across large meeting libraries.
    /// Automatically rebuilds from disk if missing or corrupted.
    public func loadMeetingIndex() -> [MeetingIndexEntry] {
        ensureDirectories()
        indexLock.lock()
        let cachedData = try? Data(contentsOf: meetingsIndexURL)
        indexLock.unlock()

        if let cachedData,
           let entries = try? decoder.decode([MeetingIndexEntry].self, from: cachedData) {
            return entries.sorted { $0.startedAt > $1.startedAt }
        }
        return rebuildMeetingIndex()
    }

    /// Rebuilds `meetings_index.json` by scanning valid meeting JSON files (safely skipping corrupted files).
    @discardableResult
    public func rebuildMeetingIndex() -> [MeetingIndexEntry] {
        let sessions = loadMeetings()
        return sessions.map(MeetingIndexEntry.init(from:))
    }

    /// Fast keyword search against the lightweight index without deserializing full transcripts.
    public func searchIndex(query: String, tag: String? = nil) -> [MeetingIndexEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return loadMeetingIndex().filter { entry in
            if let tag, !entry.tags.contains(tag) { return false }
            if q.isEmpty { return true }
            return entry.searchableText.contains(q)
        }
    }

    private func writeIndexEntries(_ entries: [MeetingIndexEntry]) {
        indexLock.lock()
        defer { indexLock.unlock() }
        let sorted = entries.sorted { $0.startedAt > $1.startedAt }
        if let data = try? encoder.encode(sorted) {
            try? data.write(to: meetingsIndexURL, options: .atomic)
        }
    }

    private func upsertIndexEntry(for meeting: MeetingSession) {
        indexLock.lock()
        var entries: [MeetingIndexEntry] = []
        if let data = try? Data(contentsOf: meetingsIndexURL),
           let decoded = try? decoder.decode([MeetingIndexEntry].self, from: data) {
            entries = decoded
        }
        let entry = MeetingIndexEntry(from: meeting)
        if let idx = entries.firstIndex(where: { $0.id == meeting.id }) {
            entries[idx] = entry
        } else {
            entries.insert(entry, at: 0)
        }
        entries.sort { $0.startedAt > $1.startedAt }
        if let data = try? encoder.encode(entries) {
            try? data.write(to: meetingsIndexURL, options: .atomic)
        }
        indexLock.unlock()
    }

    private func removeIndexEntry(id: UUID) {
        indexLock.lock()
        defer { indexLock.unlock() }
        guard let data = try? Data(contentsOf: meetingsIndexURL),
              var entries = try? decoder.decode([MeetingIndexEntry].self, from: data) else {
            return
        }
        entries.removeAll { $0.id == id }
        if let encoded = try? encoder.encode(entries) {
            try? encoded.write(to: meetingsIndexURL, options: .atomic)
        }
    }

    public func saveMeeting(_ meeting: MeetingSession) {
        ensureDirectories()
        let url = meetingsDirectory.appendingPathComponent("\(meeting.id.uuidString).json")
        if let data = try? encoder.encode(meeting) {
            try? data.write(to: url, options: .atomic)
        }
        upsertIndexEntry(for: meeting)
    }

    public func deleteMeeting(_ meeting: MeetingSession) {
        let jsonURL = meetingsDirectory.appendingPathComponent("\(meeting.id.uuidString).json")
        try? FileManager.default.removeItem(at: jsonURL)
        removeIndexEntry(id: meeting.id)
        if let audioPath = meeting.audioFilePath {
            try? FileManager.default.removeItem(atPath: audioPath)
        }
    }

    // MARK: - Daily Token Usage Ledger (Date-Accurate Accounting)

    public static func dayKey(for date: Date = Date(), calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comps.year ?? 1970, comps.month ?? 1, comps.day ?? 1)
    }

    public func loadTokenLedger(seedFrom meetings: [MeetingSession]? = nil) -> [String: TokenUsage] {
        ensureDirectories()
        if let data = try? Data(contentsOf: tokenLedgerURL),
           let ledger = try? decoder.decode([String: TokenUsage].self, from: data) {
            return ledger
        }
        // First-time migration: seed ledger from existing meetings grouped by startedAt date
        var seeded: [String: TokenUsage] = [:]
        if let meetings {
            for m in meetings where !m.tokenUsage.isEmpty {
                let key = Self.dayKey(for: m.startedAt)
                var current = seeded[key] ?? TokenUsage()
                current.add(m.tokenUsage)
                seeded[key] = current
            }
            if !seeded.isEmpty {
                saveTokenLedger(seeded)
            }
        }
        return seeded
    }

    public func saveTokenLedger(_ ledger: [String: TokenUsage]) {
        ensureDirectories()
        if let data = try? encoder.encode(ledger) {
            try? data.write(to: tokenLedgerURL, options: .atomic)
        }
    }

    @discardableResult
    public func recordTokenUsage(_ usage: TokenUsage, on date: Date = Date()) -> [String: TokenUsage] {
        var ledger = loadTokenLedger()
        guard !usage.isEmpty else { return ledger }
        let key = Self.dayKey(for: date)
        var dayUsage = ledger[key] ?? TokenUsage()
        dayUsage.add(usage)
        ledger[key] = dayUsage
        saveTokenLedger(ledger)
        return ledger
    }

    public func clearTokenLedger() {
        saveTokenLedger([:])
    }

    // MARK: - Audio Backup Storage Management

    public func audioStorageStats() -> AudioStorageStats {
        ensureDirectories()
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: audioDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return AudioStorageStats()
        }

        var count = 0
        var totalBytes: Int64 = 0
        for url in urls {
            let vals = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard vals?.isRegularFile == true else { continue }
            count += 1
            totalBytes += Int64(vals?.fileSize ?? 0)
        }
        return AudioStorageStats(fileCount: count, totalBytes: totalBytes)
    }

    /// Removes audio backup files older than `days` days (or all completed audio when `days == 0`),
    /// always preserving meeting transcripts/minutes and skipping any currently active recording.
    @discardableResult
    public func pruneAudioBackups(
        olderThanDays days: Int,
        activeMeetingID: UUID? = nil,
        meetings: inout [MeetingSession],
        now: Date = Date()
    ) -> (removedFiles: Int, freedBytes: Int64) {
        ensureDirectories()
        let fm = FileManager.default
        let cutoffDate = days <= 0 ? Date.distantFuture : now.addingTimeInterval(-TimeInterval(days) * 86_400)

        var removedFiles = 0
        var freedBytes: Int64 = 0
        var protectedPaths: Set<String> = []
        var referencedPaths: Set<String> = []

        for idx in meetings.indices {
            guard let audioPath = meetings[idx].audioFilePath else { continue }
            let standardized = URL(fileURLWithPath: audioPath).standardizedFileURL.path
            referencedPaths.insert(standardized)

            if meetings[idx].id == activeMeetingID || meetings[idx].status == .recording || meetings[idx].status == .paused {
                protectedPaths.insert(standardized)
                continue
            }

            let referenceDate = meetings[idx].endedAt ?? meetings[idx].startedAt
            let shouldRemove = (days <= 0) || (referenceDate < cutoffDate)
            guard shouldRemove else { continue }

            if fm.fileExists(atPath: standardized) {
                let size = (try? fm.attributesOfItem(atPath: standardized)[.size] as? NSNumber)?.int64Value ?? 0
                if (try? fm.removeItem(atPath: standardized)) != nil {
                    removedFiles += 1
                    freedBytes += size
                }
            }
            meetings[idx].audioFilePath = nil
            saveMeeting(meetings[idx])
        }

        // Also clean orphaned files inside audioDirectory not referenced by any meeting
        if let urls = try? fm.contentsOfDirectory(
            at: audioDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            for url in urls {
                let path = url.standardizedFileURL.path
                guard !protectedPaths.contains(path), !referencedPaths.contains(path) else { continue }
                let vals = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey])
                guard vals?.isRegularFile == true else { continue }
                let modDate = vals?.contentModificationDate ?? Date.distantPast
                if days <= 0 || modDate < cutoffDate {
                    let size = Int64(vals?.fileSize ?? 0)
                    if (try? fm.removeItem(at: url)) != nil {
                        removedFiles += 1
                        freedBytes += size
                    }
                }
            }
        }

        return (removedFiles, freedBytes)
    }

    // MARK: - Doubao-Style Markdown Export

    public static func exportMarkdown(for meeting: MeetingSession, includeTranscript: Bool = true) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"

        var md: [String] = []
        md.append("# \(meeting.title)")
        md.append("")
        md.append("- **时间**：\(df.string(from: meeting.startedAt))")
        md.append("- **时长**：\(meeting.formattedDuration)")
        md.append("- **来源**：\(meeting.sourceAppName)")
        if !meeting.minutes.participants.isEmpty {
            md.append("- **参会角色/人员**：\(meeting.minutes.participants.joined(separator: "、"))")
        }
        md.append("")

        if let fallback = meeting.minutes.rawMarkdownFallback, !fallback.isEmpty {
            md.append("## 智能纪要")
            md.append("")
            md.append(fallback)
            md.append("")
        } else {
            if !meeting.minutes.overview.isEmpty {
                md.append("## 一句话总览")
                md.append("")
                md.append(meeting.minutes.overview)
                md.append("")
            }

            if !meeting.minutes.topics.isEmpty {
                md.append("## 讨论议题与核心要点")
                md.append("")
                for (idx, topic) in meeting.minutes.topics.enumerated() {
                    md.append("### \(idx + 1). \(topic.title)")
                    for point in topic.points {
                        md.append("- \(point)")
                    }
                    md.append("")
                }
            }

            if !meeting.minutes.decisions.isEmpty {
                md.append("## 关键决议与共识")
                md.append("")
                for decision in meeting.minutes.decisions {
                    md.append("- ✅ \(decision)")
                }
                md.append("")
            }

            if !meeting.minutes.actionItems.isEmpty {
                md.append("## 待办清单 (Action Items)")
                md.append("")
                md.append("| 状态 | 待办事项 | 责任人 | 截止时间 |")
                md.append("| :---: | :--- | :--- | :--- |")
                for item in meeting.minutes.actionItems {
                    let check = item.isCompleted ? "☑" : "☐"
                    let due = item.dueDate.isEmpty ? "-" : item.dueDate
                    md.append("| \(check) | \(item.task) | \(item.owner) | \(due) |")
                }
                md.append("")
            }

            if !meeting.minutes.openQuestions.isEmpty {
                md.append("## 风险点与待确认问题")
                md.append("")
                for q in meeting.minutes.openQuestions {
                    md.append("- ❓ \(q)")
                }
                md.append("")
            }
        }

        if !meeting.manualNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            md.append("## 会中手动笔记")
            md.append("")
            md.append(meeting.manualNotes)
            md.append("")
        }

        if includeTranscript && !meeting.segments.isEmpty {
            md.append("## 会议逐字稿")
            md.append("")
            for seg in meeting.segments {
                let star = seg.isStarred ? "⭐ " : ""
                md.append("- `\(seg.formattedTimestamp)` **\(seg.resolvedSpeakerName)**：\(star)\(seg.text)")
            }
            md.append("")
        }

        return md.joined(separator: "\n")
    }

    /// Exports structured minutes as a Mermaid `mindmap` code block compatible with Feishu / Notion / GitHub.
    public static func exportMermaidMindMap(for meeting: MeetingSession) -> String {
        func safeNode(_ text: String) -> String {
            text.replacingOccurrences(of: "\"", with: "'")
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let rootTitle = safeNode(meeting.minutes.suggestedTitle.isEmpty ? meeting.title : meeting.minutes.suggestedTitle)
        var lines: [String] = [
            "```mermaid",
            "mindmap",
            "  root((\"\(rootTitle)\"))"
        ]

        if !meeting.minutes.overview.isEmpty {
            lines.append("    会议概览")
            lines.append("      \"\(safeNode(meeting.minutes.overview))\"")
        }

        for topic in meeting.minutes.topics {
            lines.append("    \"\(safeNode(topic.title))\"")
            for point in topic.points {
                lines.append("      \"\(safeNode(point))\"")
            }
        }

        if !meeting.minutes.decisions.isEmpty {
            lines.append("    关键决议")
            for decision in meeting.minutes.decisions {
                lines.append("      \"\(safeNode(decision))\"")
            }
        }

        if !meeting.minutes.actionItems.isEmpty {
            lines.append("    待办清单")
            for item in meeting.minutes.actionItems {
                let meta = [item.owner, item.dueDate].filter { !$0.isEmpty && $0 != "待定" }.joined(separator: " / ")
                let text = meta.isEmpty ? item.task : "\(item.task) (\(meta))"
                lines.append("      \"\(safeNode(text))\"")
            }
        }

        if !meeting.minutes.openQuestions.isEmpty {
            lines.append("    待确认问题")
            for q in meeting.minutes.openQuestions {
                lines.append("      \"\(safeNode(q))\"")
            }
        }

        lines.append("```")
        return lines.joined(separator: "\n")
    }

    /// Exports structured meeting minutes as clean styled HTML ready for rich-text clipboard pasting
    /// into Feishu Docs, Notion, Apple Mail, or Word with headings, bold text, bullets, and tables preserved.
    public static func exportHTML(for meeting: MeetingSession, includeTranscript: Bool = false) -> String {
        func escapeHTML(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
        }

        func inlineHTML(_ raw: String) -> String {
            let spans = MarkdownParser.parseInline(raw)
            return spans.map { span in
                var html = escapeHTML(span.text).replacingOccurrences(of: "\n", with: "<br/>")
                if span.style.contains(.code) {
                    html = "<code style=\"background:#f2f3f5;padding:1px 4px;border-radius:4px;font-family:Menlo,monospace;font-size:12px;\">\(html)</code>"
                }
                if span.style.contains(.bold) { html = "<strong>\(html)</strong>" }
                if span.style.contains(.italic) { html = "<em>\(html)</em>" }
                if span.style.contains(.strikethrough) { html = "<del>\(html)</del>" }
                if let link = span.linkURL {
                    html = "<a href=\"\(escapeHTML(link))\" style=\"color:#2468f2;\">\(html)</a>"
                }
                return html
            }.joined()
        }

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"

        var parts: [String] = [
            "<!DOCTYPE html><html><head><meta charset=\"utf-8\"></head>",
            "<body style=\"font-family:-apple-system,BlinkMacSystemFont,'PingFang SC','Helvetica Neue',sans-serif;font-size:14px;line-height:1.65;color:#1d2129;\">",
            "<h1 style=\"font-size:20px;margin:0 0 6px 0;\">\(escapeHTML(meeting.title))</h1>",
            "<p style=\"color:#86909c;font-size:12px;margin:0 0 16px 0;\">时间：\(df.string(from: meeting.startedAt)) · 来源：\(escapeHTML(meeting.sourceAppName)) · 时长：\(escapeHTML(meeting.chineseDurationText))</p>"
        ]

        if let fallback = meeting.minutes.rawMarkdownFallback, !fallback.isEmpty {
            for block in MarkdownParser.parse(fallback) {
                switch block {
                case .heading(let lvl, let txt):
                    let tag = "h\(min(4, max(2, lvl)))"
                    parts.append("<\(tag) style=\"margin:14px 0 6px 0;\">\(inlineHTML(txt))</\(tag)>")
                case .paragraph(let txt):
                    parts.append("<p style=\"margin:6px 0;\">\(inlineHTML(txt))</p>")
                case .bulletList(let items):
                    parts.append("<ul style=\"margin:6px 0;padding-left:20px;\">")
                    for item in items {
                        let prefix = item.isChecked == true ? "☑ " : (item.isChecked == false ? "☐ " : "")
                        parts.append("<li style=\"margin:3px 0;\">\(prefix)\(inlineHTML(item.text))</li>")
                    }
                    parts.append("</ul>")
                case .orderedList(let items):
                    parts.append("<ol style=\"margin:6px 0;padding-left:20px;\">")
                    for item in items {
                        parts.append("<li style=\"margin:3px 0;\">\(inlineHTML(item.text))</li>")
                    }
                    parts.append("</ol>")
                case .table(let headers, let rows):
                    parts.append("<table style=\"border-collapse:collapse;width:100%;margin:10px 0;font-size:13px;\"><thead><tr>")
                    for h in headers {
                        parts.append("<th style=\"border:1px solid #e5e6eb;background:#f2f7ff;padding:6px 10px;text-align:left;\">\(inlineHTML(h))</th>")
                    }
                    parts.append("</tr></thead><tbody>")
                    for r in rows {
                        parts.append("<tr>")
                        for cell in r {
                            parts.append("<td style=\"border:1px solid #e5e6eb;padding:6px 10px;\">\(inlineHTML(cell))</td>")
                        }
                        parts.append("</tr>")
                    }
                    parts.append("</tbody></table>")
                case .blockquote(let txt):
                    parts.append("<blockquote style=\"border-left:3px solid #2468f2;margin:8px 0;padding-left:10px;color:#4e5969;\">\(inlineHTML(txt))</blockquote>")
                case .codeBlock(_, let code):
                    parts.append("<pre style=\"background:#f7f8fa;border:1px solid #e5e6eb;padding:10px;border-radius:6px;font-family:Menlo,monospace;font-size:12px;\">\(escapeHTML(code))</pre>")
                case .divider:
                    parts.append("<hr style=\"border:none;border-top:1px solid #e5e6eb;margin:12px 0;\"/>")
                }
            }
        } else {
            if !meeting.minutes.overview.isEmpty {
                parts.append("<h2 style=\"font-size:15px;margin:14px 0 6px 0;\">摘要</h2>")
                parts.append("<p style=\"margin:4px 0 10px 0;\">\(inlineHTML(meeting.minutes.overview))</p>")
            }
            if !meeting.minutes.topics.isEmpty {
                parts.append("<h2 style=\"font-size:15px;margin:14px 0 6px 0;\">核心要点</h2>")
                for (idx, topic) in meeting.minutes.topics.enumerated() {
                    parts.append("<h3 style=\"font-size:14px;margin:10px 0 4px 0;\">\(idx + 1). \(inlineHTML(topic.title))</h3>")
                    parts.append("<ul style=\"margin:4px 0 8px 0;padding-left:20px;\">")
                    for pt in topic.points {
                        parts.append("<li style=\"margin:3px 0;\">\(inlineHTML(pt))</li>")
                    }
                    parts.append("</ul>")
                }
            }
            if !meeting.minutes.decisions.isEmpty {
                parts.append("<h2 style=\"font-size:15px;margin:14px 0 6px 0;\">会议决议</h2>")
                parts.append("<ul style=\"margin:4px 0 10px 0;padding-left:20px;\">")
                for d in meeting.minutes.decisions {
                    parts.append("<li style=\"margin:3px 0;\">✅ \(inlineHTML(d))</li>")
                }
                parts.append("</ul>")
            }
            if !meeting.minutes.actionItems.isEmpty {
                parts.append("<h2 style=\"font-size:15px;margin:14px 0 6px 0;\">待办事项</h2>")
                parts.append("<table style=\"border-collapse:collapse;width:100%;margin:6px 0 12px 0;font-size:13px;\"><thead><tr>")
                parts.append("<th style=\"border:1px solid #e5e6eb;background:#f2f7ff;padding:6px 10px;text-align:center;width:44px;\">状态</th>")
                parts.append("<th style=\"border:1px solid #e5e6eb;background:#f2f7ff;padding:6px 10px;text-align:left;\">待办内容</th>")
                parts.append("<th style=\"border:1px solid #e5e6eb;background:#f2f7ff;padding:6px 10px;text-align:left;width:96px;\">负责人</th>")
                parts.append("<th style=\"border:1px solid #e5e6eb;background:#f2f7ff;padding:6px 10px;text-align:left;width:96px;\">截止时间</th>")
                parts.append("</tr></thead><tbody>")
                for item in meeting.minutes.actionItems {
                    let check = item.isCompleted ? "☑" : "☐"
                    let due = item.dueDate.isEmpty ? "-" : escapeHTML(item.dueDate)
                    parts.append("<tr><td style=\"border:1px solid #e5e6eb;padding:6px 10px;text-align:center;\">\(check)</td><td style=\"border:1px solid #e5e6eb;padding:6px 10px;\">\(inlineHTML(item.task))</td><td style=\"border:1px solid #e5e6eb;padding:6px 10px;\">\(escapeHTML(item.owner))</td><td style=\"border:1px solid #e5e6eb;padding:6px 10px;\">\(due)</td></tr>")
                }
                parts.append("</tbody></table>")
            }
            if !meeting.minutes.openQuestions.isEmpty {
                parts.append("<h2 style=\"font-size:15px;margin:14px 0 6px 0;\">待确认问题</h2>")
                parts.append("<ul style=\"margin:4px 0 10px 0;padding-left:20px;\">")
                for q in meeting.minutes.openQuestions {
                    parts.append("<li style=\"margin:3px 0;\">❓ \(inlineHTML(q))</li>")
                }
                parts.append("</ul>")
            }
        }

        if !meeting.manualNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("<h2 style=\"font-size:15px;margin:14px 0 6px 0;\">会中随手记</h2>")
            parts.append("<p style=\"margin:4px 0;\">\(escapeHTML(meeting.manualNotes).replacingOccurrences(of: "\n", with: "<br/>"))</p>")
        }

        if includeTranscript && !meeting.segments.isEmpty {
            parts.append("<h2 style=\"font-size:15px;margin:14px 0 6px 0;\">会议逐字稿</h2>")
            parts.append("<ul style=\"margin:4px 0;padding-left:20px;\">")
            for seg in meeting.segments {
                let star = seg.isStarred ? "⭐ " : ""
                parts.append("<li style=\"margin:3px 0;\"><span style=\"color:#86909c;font-family:Menlo,monospace;font-size:12px;\">[\(seg.formattedTimestamp)]</span> <strong>\(escapeHTML(seg.resolvedSpeakerName))</strong>：\(star)\(escapeHTML(seg.text))</li>")
            }
            parts.append("</ul>")
        }

        parts.append("</body></html>")
        return parts.joined()
    }

    // MARK: - Subtitle Export (.srt & .vtt)

    /// Exports timestamped transcript segments as standard SubRip (`.srt`) subtitles.
    public static func exportSRT(for meeting: MeetingSession) -> String {
        let sorted = meeting.segments.sorted { $0.timestamp < $1.timestamp }
        guard !sorted.isEmpty else { return "" }

        var blocks: [String] = []
        blocks.reserveCapacity(sorted.count)
        for (idx, seg) in sorted.enumerated() {
            let start = max(0, seg.timestamp)
            let end = subtitleEndTime(for: seg, index: idx, all: sorted, meetingDuration: meeting.duration)
            let header = "\(idx + 1)"
            let timing = "\(formatSubtitleTime(start, decimalSeparator: ",")) --> \(formatSubtitleTime(end, decimalSeparator: ","))"
            let line = "[\(seg.resolvedSpeakerName)] \(seg.text.trimmingCharacters(in: .whitespacesAndNewlines))"
            blocks.append("\(header)\n\(timing)\n\(line)")
        }
        return blocks.joined(separator: "\n\n") + "\n"
    }

    /// Exports timestamped transcript segments as standard WebVTT (`.vtt`) subtitles.
    public static func exportVTT(for meeting: MeetingSession) -> String {
        let sorted = meeting.segments.sorted { $0.timestamp < $1.timestamp }
        guard !sorted.isEmpty else { return "WEBVTT\n" }

        var blocks: [String] = ["WEBVTT"]
        blocks.reserveCapacity(sorted.count + 1)
        for (idx, seg) in sorted.enumerated() {
            let start = max(0, seg.timestamp)
            let end = subtitleEndTime(for: seg, index: idx, all: sorted, meetingDuration: meeting.duration)
            let timing = "\(formatSubtitleTime(start, decimalSeparator: ".")) --> \(formatSubtitleTime(end, decimalSeparator: "."))"
            let line = "<v \(seg.resolvedSpeakerName)>\(seg.text.trimmingCharacters(in: .whitespacesAndNewlines))"
            blocks.append("\(timing)\n\(line)")
        }
        return blocks.joined(separator: "\n\n") + "\n"
    }

    private static func subtitleEndTime(
        for segment: TranscriptSegment,
        index: Int,
        all: [TranscriptSegment],
        meetingDuration: TimeInterval
    ) -> TimeInterval {
        let start = max(0, segment.timestamp)
        // Estimate reading duration ~0.16s per character, clamped between 2.0s and 8.0s
        let estimated = min(8.0, max(2.0, Double(segment.text.count) * 0.16))
        if index + 1 < all.count {
            let nextStart = max(start + 0.5, all[index + 1].timestamp - 0.08)
            return min(start + estimated, nextStart)
        }
        if meetingDuration > start + 0.5 {
            return min(start + estimated, meetingDuration)
        }
        return start + estimated
    }

    private static func formatSubtitleTime(_ seconds: TimeInterval, decimalSeparator: String) -> String {
        let totalMs = max(0, Int((seconds * 1000.0).rounded()))
        let h = totalMs / 3_600_000
        let m = (totalMs % 3_600_000) / 60_000
        let s = (totalMs % 60_000) / 1_000
        let ms = totalMs % 1_000
        return String(format: "%02d:%02d:%02d%@%03d", h, m, s, decimalSeparator, ms)
    }
}
