import Foundation

public enum SpeakerSource: String, Codable, CaseIterable, Sendable {
    case me = "me"
    case remote = "remote"
    case mixed = "mixed"

    public var displayName: String {
        switch self {
        case .me: return SonoteLocale.t("我", "Me")
        case .remote: return SonoteLocale.t("对方 / 系统声音", "Remote / System Audio")
        case .mixed: return SonoteLocale.t("会议音频", "Meeting Audio")
        }
    }

    public var shortLabel: String {
        switch self {
        case .me: return SonoteLocale.t("我", "Me")
        case .remote: return SonoteLocale.t("远端", "Remote")
        case .mixed: return SonoteLocale.t("混合", "Mixed")
        }
    }
}

public struct TranscriptSegment: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var timestamp: TimeInterval // seconds since meeting start
    public var createdAt: Date
    public var speaker: SpeakerSource
    public var speakerLabel: String?   // Optional diarized / inferred speaker name (e.g. "发言人 1", "张三")
    public var text: String
    public var isStarred: Bool

    public init(
        id: UUID = UUID(),
        timestamp: TimeInterval,
        createdAt: Date = Date(),
        speaker: SpeakerSource,
        speakerLabel: String? = nil,
        text: String,
        isStarred: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.createdAt = createdAt
        self.speaker = speaker
        self.speakerLabel = speakerLabel
        self.text = text
        self.isStarred = isStarred
    }

    public var resolvedSpeakerName: String {
        if let label = speakerLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
            return label
        }
        return speaker == .me ? "我" : "发言人"
    }

    public var formattedTimestamp: String {
        let totalSeconds = max(0, Int(timestamp))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

public struct TopicSection: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var points: [String]

    public init(id: UUID = UUID(), title: String, points: [String]) {
        self.id = id
        self.title = title
        self.points = points
    }
}

public struct ActionItem: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var task: String
    public var owner: String
    public var dueDate: String
    public var isCompleted: Bool

    public init(
        id: UUID = UUID(),
        task: String,
        owner: String = "待定",
        dueDate: String = "",
        isCompleted: Bool = false
    ) {
        self.id = id
        self.task = task
        self.owner = owner
        self.dueDate = dueDate
        self.isCompleted = isCompleted
    }
}

public struct SmartMinutes: Codable, Equatable, Sendable {
    public var suggestedTitle: String
    public var overview: String
    public var topics: [TopicSection]
    public var decisions: [String]
    public var actionItems: [ActionItem]
    public var openQuestions: [String]
    public var participants: [String]
    public var lastUpdatedAt: Date
    public var isFinalized: Bool
    public var rawMarkdownFallback: String?

    public init(
        suggestedTitle: String = "",
        overview: String = "",
        topics: [TopicSection] = [],
        decisions: [String] = [],
        actionItems: [ActionItem] = [],
        openQuestions: [String] = [],
        participants: [String] = [],
        lastUpdatedAt: Date = Date(),
        isFinalized: Bool = false,
        rawMarkdownFallback: String? = nil
    ) {
        self.suggestedTitle = suggestedTitle
        self.overview = overview
        self.topics = topics
        self.decisions = decisions
        self.actionItems = actionItems
        self.openQuestions = openQuestions
        self.participants = participants
        self.lastUpdatedAt = lastUpdatedAt
        self.isFinalized = isFinalized
        self.rawMarkdownFallback = rawMarkdownFallback
    }

    public var isEmpty: Bool {
        overview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && topics.isEmpty
            && decisions.isEmpty
            && actionItems.isEmpty
            && openQuestions.isEmpty
            && (rawMarkdownFallback?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    public var latestHighlight: String? {
        if let lastTopic = topics.last, let lastPoint = lastTopic.points.last {
            return "\(lastTopic.title)：\(lastPoint)"
        }
        if let lastDecision = decisions.last {
            return "决议：\(lastDecision)"
        }
        if !overview.isEmpty {
            return overview
        }
        return nil
    }

    /// Trims whitespace and removes empty placeholder entries created during manual editing.
    public func sanitizedForSave() -> SmartMinutes {
        var copy = self
        copy.suggestedTitle = suggestedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.overview = overview.trimmingCharacters(in: .whitespacesAndNewlines)

        copy.topics = topics.compactMap { topic in
            let title = topic.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let points = topic.points
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if title.isEmpty && points.isEmpty { return nil }
            return TopicSection(id: topic.id, title: title, points: points)
        }

        copy.decisions = decisions
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        copy.actionItems = actionItems.compactMap { item in
            let task = item.task.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !task.isEmpty else { return nil }
            var cleaned = item
            cleaned.task = task
            cleaned.owner = item.owner.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned.dueDate = item.dueDate.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned
        }

        copy.openQuestions = openQuestions
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let raw = rawMarkdownFallback {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            copy.rawMarkdownFallback = trimmed.isEmpty ? nil : trimmed
        }

        copy.lastUpdatedAt = Date()
        return copy
    }
}

public struct TokenUsage: Codable, Equatable, Sendable {
    public var inputTokens: Int
    public var outputTokens: Int
    public var cachedTokens: Int
    public var reasoningTokens: Int
    public var requestCount: Int
    public var isEstimated: Bool

    public init(
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cachedTokens: Int = 0,
        reasoningTokens: Int = 0,
        requestCount: Int = 0,
        isEstimated: Bool = false
    ) {
        self.inputTokens = max(0, inputTokens)
        self.outputTokens = max(0, outputTokens)
        self.cachedTokens = max(0, cachedTokens)
        self.reasoningTokens = max(0, reasoningTokens)
        self.requestCount = max(0, requestCount)
        self.isEstimated = isEstimated
    }

    public var totalTokens: Int {
        inputTokens + outputTokens
    }

    public var isEmpty: Bool {
        totalTokens == 0 && requestCount == 0
    }

    public mutating func add(_ other: TokenUsage) {
        inputTokens += other.inputTokens
        outputTokens += other.outputTokens
        cachedTokens += other.cachedTokens
        reasoningTokens += other.reasoningTokens
        requestCount += other.requestCount
        isEstimated = isEstimated || other.isEstimated
    }

    public var formattedCompact: String {
        let prefix = isEstimated ? "≈" : ""
        let t = totalTokens
        if t >= 1_000_000 {
            return String(format: "%@%.2fM", prefix, Double(t) / 1_000_000.0)
        } else if t >= 1_000 {
            return String(format: "%@%.1fk", prefix, Double(t) / 1_000.0)
        }
        return "\(prefix)\(t)"
    }

    public var detailedSummary: String {
        var parts = [
            SonoteLocale.t("输入 \(Self.formatNumber(inputTokens))", "In \(Self.formatNumber(inputTokens))"),
            SonoteLocale.t("输出 \(Self.formatNumber(outputTokens))", "Out \(Self.formatNumber(outputTokens))")
        ]
        if cachedTokens > 0 {
            parts.append(SonoteLocale.t("缓存 \(Self.formatNumber(cachedTokens))", "Cached \(Self.formatNumber(cachedTokens))"))
        }
        if reasoningTokens > 0 {
            parts.append(SonoteLocale.t("思考 \(Self.formatNumber(reasoningTokens))", "Reasoning \(Self.formatNumber(reasoningTokens))"))
        }
        if requestCount > 1 {
            parts.append(SonoteLocale.t("\(requestCount) 次调用", "\(requestCount) calls"))
        }
        if isEstimated {
            parts.append(SonoteLocale.t("估算值", "Est."))
        }
        return parts.joined(separator: " · ")
    }

    public static func formatNumber(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.2fM", Double(value) / 1_000_000.0)
        } else if value >= 10_000 {
            return String(format: "%.1fk", Double(value) / 1_000.0)
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    public static func estimate(prompt: String, completion: String) -> TokenUsage {
        func countTokens(_ s: String) -> Int {
            guard !s.isEmpty else { return 0 }
            var cjk = 0
            var other = 0
            for scalar in s.unicodeScalars {
                if (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value) {
                    cjk += 1
                } else {
                    other += 1
                }
            }
            return max(1, Int(Double(cjk) * 0.75 + Double(other) / 4.0))
        }
        return TokenUsage(
            inputTokens: countTokens(prompt),
            outputTokens: countTokens(completion),
            requestCount: 1,
            isEstimated: true
        )
    }
}

public struct MeetingChatMessage: Identifiable, Codable, Equatable, Sendable {
    public enum Role: String, Codable, Sendable {
        case user
        case assistant
    }

    public var id: UUID
    public var role: Role
    public var content: String
    public var createdAt: Date
    public var tokenUsage: TokenUsage?

    public init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        createdAt: Date = Date(),
        tokenUsage: TokenUsage? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.tokenUsage = tokenUsage
    }
}

public enum MeetingStatus: String, Codable, Sendable {
    case recording
    case paused
    case summarizing
    case completed

    public var displayName: String {
        switch self {
        case .recording: return "记录中"
        case .paused: return "已暂停"
        case .summarizing: return "生成纪要中"
        case .completed: return "已完成"
        }
    }
}

public struct DetectedMeetingApp: Identifiable, Codable, Equatable, Sendable {
    public var id: String { "\(bundleIdentifier):\(pid)" }
    public var bundleIdentifier: String
    public var appName: String
    public var pid: Int32
    public var isUsingMicrophone: Bool
    public var isPlayingAudio: Bool
    public var detectedAt: Date

    public init(
        bundleIdentifier: String,
        appName: String,
        pid: Int32,
        isUsingMicrophone: Bool,
        isPlayingAudio: Bool,
        detectedAt: Date = Date()
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.pid = pid
        self.isUsingMicrophone = isUsingMicrophone
        self.isPlayingAudio = isPlayingAudio
        self.detectedAt = detectedAt
    }
}

public struct SpeakerShareStat: Identifiable, Equatable, Sendable {
    public var id: String { speakerName }
    public var speakerName: String
    public var segmentCount: Int
    public var characterCount: Int
    public var share: Double

    public init(speakerName: String, segmentCount: Int, characterCount: Int, share: Double) {
        self.speakerName = speakerName
        self.segmentCount = segmentCount
        self.characterCount = characterCount
        self.share = share
    }

    public var percentageInt: Int {
        Int((share * 100.0).rounded())
    }
}

public struct MeetingSession: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var sourceAppName: String
    public var sourceBundleId: String?
    public var startedAt: Date
    public var endedAt: Date?
    public var duration: TimeInterval
    public var status: MeetingStatus
    public var segments: [TranscriptSegment]
    public var manualNotes: String
    public var minutes: SmartMinutes
    public var chatHistory: [MeetingChatMessage]
    public var audioFilePath: String?
    public var tokenUsage: TokenUsage
    public var template: MinutesTemplate
    public var customTemplateID: UUID?
    public var calendarAttendees: [String]
    public var tags: [String]
    public var isPinned: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        sourceAppName: String = "手动记录",
        sourceBundleId: String? = nil,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        duration: TimeInterval = 0,
        status: MeetingStatus = .recording,
        segments: [TranscriptSegment] = [],
        manualNotes: String = "",
        minutes: SmartMinutes = SmartMinutes(),
        chatHistory: [MeetingChatMessage] = [],
        audioFilePath: String? = nil,
        tokenUsage: TokenUsage = TokenUsage(),
        template: MinutesTemplate = .general,
        customTemplateID: UUID? = nil,
        calendarAttendees: [String] = [],
        tags: [String] = [],
        isPinned: Bool = false
    ) {
        self.id = id
        self.title = title
        self.sourceAppName = sourceAppName
        self.sourceBundleId = sourceBundleId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.duration = duration
        self.status = status
        self.segments = segments
        self.manualNotes = manualNotes
        self.minutes = minutes
        self.chatHistory = chatHistory
        self.audioFilePath = audioFilePath
        self.tokenUsage = tokenUsage
        self.template = template
        self.customTemplateID = customTemplateID
        self.calendarAttendees = calendarAttendees
        self.tags = tags
        self.isPinned = isPinned
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        sourceAppName = try c.decodeIfPresent(String.self, forKey: .sourceAppName) ?? "手动记录"
        sourceBundleId = try c.decodeIfPresent(String.self, forKey: .sourceBundleId)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt)
        duration = try c.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0
        status = try c.decodeIfPresent(MeetingStatus.self, forKey: .status) ?? .completed
        segments = try c.decodeIfPresent([TranscriptSegment].self, forKey: .segments) ?? []
        manualNotes = try c.decodeIfPresent(String.self, forKey: .manualNotes) ?? ""
        minutes = try c.decodeIfPresent(SmartMinutes.self, forKey: .minutes) ?? SmartMinutes()
        chatHistory = try c.decodeIfPresent([MeetingChatMessage].self, forKey: .chatHistory) ?? []
        audioFilePath = try c.decodeIfPresent(String.self, forKey: .audioFilePath)
        tokenUsage = try c.decodeIfPresent(TokenUsage.self, forKey: .tokenUsage) ?? TokenUsage()
        template = try c.decodeIfPresent(MinutesTemplate.self, forKey: .template) ?? .general
        customTemplateID = try c.decodeIfPresent(UUID.self, forKey: .customTemplateID)
        calendarAttendees = try c.decodeIfPresent([String].self, forKey: .calendarAttendees) ?? []
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }

    public var formattedDuration: String {
        let total = max(0, Int(duration))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%02d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    public var chineseDurationText: String {
        let total = max(0, Int(duration))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return "\(h)小时\(m)分\(s)秒"
        }
        return "\(m)分\(s)秒"
    }

    public var transcriptAsText: String {
        segments.map { seg in
            "[\(seg.formattedTimestamp)] [\(seg.resolvedSpeakerName)] \(seg.text)"
        }.joined(separator: "\n")
    }

    /// Unique speaker display names in order of first appearance.
    public var distinctSpeakerNames: [String] {
        var seen: Set<String> = []
        var names: [String] = []
        for seg in segments {
            let name = seg.resolvedSpeakerName
            if !seen.contains(name) {
                seen.insert(name)
                names.append(name)
            }
        }
        return names
    }

    /// Computes per-speaker speaking share (by character count) sorted descending.
    public var speakerShareStats: [SpeakerShareStat] {
        guard !segments.isEmpty else { return [] }
        var counts: [String: (segments: Int, chars: Int)] = [:]
        var totalChars = 0
        for seg in segments {
            let name = seg.resolvedSpeakerName
            let len = max(1, seg.text.trimmingCharacters(in: .whitespacesAndNewlines).count)
            let cur = counts[name] ?? (0, 0)
            counts[name] = (cur.segments + 1, cur.chars + len)
            totalChars += len
        }
        guard totalChars > 0 else { return [] }
        return counts
            .map { name, entry in
                SpeakerShareStat(
                    speakerName: name,
                    segmentCount: entry.segments,
                    characterCount: entry.chars,
                    share: Double(entry.chars) / Double(totalChars)
                )
            }
            .sorted { a, b in
                if a.characterCount != b.characterCount { return a.characterCount > b.characterCount }
                return a.speakerName < b.speakerName
            }
    }

    /// Renames a single segment's speaker or batch-renames all segments matching `oldName`,
    /// optionally syncing the new name across structured minutes fields too.
    public mutating func renameSpeaker(
        from oldName: String,
        to rawNewName: String,
        onlySegmentID: UUID? = nil,
        updateMinutes: Bool = true
    ) {
        let newName = rawNewName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, oldName != newName else { return }

        if let targetID = onlySegmentID {
            if let idx = segments.firstIndex(where: { $0.id == targetID }) {
                segments[idx].speakerLabel = newName
            }
            return
        }

        for idx in segments.indices where segments[idx].resolvedSpeakerName == oldName {
            segments[idx].speakerLabel = newName
        }

        guard updateMinutes, !oldName.isEmpty else { return }
        minutes.overview = minutes.overview.replacingOccurrences(of: oldName, with: newName)
        for tIdx in minutes.topics.indices {
            minutes.topics[tIdx].title = minutes.topics[tIdx].title.replacingOccurrences(of: oldName, with: newName)
            minutes.topics[tIdx].points = minutes.topics[tIdx].points.map {
                $0.replacingOccurrences(of: oldName, with: newName)
            }
        }
        minutes.decisions = minutes.decisions.map { $0.replacingOccurrences(of: oldName, with: newName) }
        minutes.openQuestions = minutes.openQuestions.map { $0.replacingOccurrences(of: oldName, with: newName) }
        minutes.participants = minutes.participants.map { $0 == oldName ? newName : $0 }
        for aIdx in minutes.actionItems.indices {
            minutes.actionItems[aIdx].task = minutes.actionItems[aIdx].task.replacingOccurrences(of: oldName, with: newName)
            minutes.actionItems[aIdx].owner = minutes.actionItems[aIdx].owner.replacingOccurrences(of: oldName, with: newName)
        }
        if let fallback = minutes.rawMarkdownFallback {
            minutes.rawMarkdownFallback = fallback.replacingOccurrences(of: oldName, with: newName)
        }
    }

    /// Replaces all occurrences of `find` with `replaceWith` across transcript segments.
    /// Returns the total number of replaced occurrences.
    @discardableResult
    public mutating func replaceInTranscript(
        find: String,
        replaceWith: String,
        caseSensitive: Bool = false
    ) -> Int {
        let needle = find.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty, needle != replaceWith else { return 0 }
        let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        var totalReplaced = 0

        for idx in segments.indices {
            var text = segments[idx].text
            var searchStart = text.startIndex
            var countInSeg = 0
            while searchStart < text.endIndex,
                  let range = text.range(of: needle, options: options, range: searchStart..<text.endIndex) {
                text.replaceSubrange(range, with: replaceWith)
                countInSeg += 1
                searchStart = text.index(range.lowerBound, offsetBy: replaceWith.count, limitedBy: text.endIndex) ?? text.endIndex
            }
            if countInSeg > 0 {
                segments[idx].text = text
                totalReplaced += countInSeg
            }
        }
        return totalReplaced
    }

    /// Merges consecutive transcript segments spoken by the same speaker within `maxGapSeconds`.
    /// Preserves the earliest timestamp and starred status. Returns the number of merged segments.
    @discardableResult
    public mutating func mergeAdjacentSameSpeakerSegments(maxGapSeconds: TimeInterval = 12.0) -> Int {
        guard segments.count > 1 else { return 0 }
        var merged: [TranscriptSegment] = []
        merged.reserveCapacity(segments.count)
        var mergedCount = 0

        for seg in segments {
            if var prev = merged.last,
               prev.speaker == seg.speaker,
               prev.resolvedSpeakerName == seg.resolvedSpeakerName,
               (seg.timestamp - prev.timestamp) <= maxGapSeconds,
               (prev.text.count + seg.text.count) <= 420 {
                let left = prev.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let right = seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let joiner: String
                if left.isEmpty || right.isEmpty {
                    joiner = ""
                } else if let lastScalar = left.unicodeScalars.last, (0x4E00...0x9FFF).contains(lastScalar.value) {
                    joiner = "，"
                } else if left.hasSuffix("。") || left.hasSuffix("，") || left.hasSuffix("！") || left.hasSuffix("？") {
                    joiner = ""
                } else {
                    joiner = " "
                }
                prev.text = "\(left)\(joiner)\(right)"
                prev.isStarred = prev.isStarred || seg.isStarred
                merged[merged.count - 1] = prev
                mergedCount += 1
            } else {
                merged.append(seg)
            }
        }

        if mergedCount > 0 {
            segments = merged
        }
        return mergedCount
    }

    /// Full-text search across title, app source, structured minutes, manual notes, and transcript segments.
    public func matchesSearchQuery(_ rawQuery: String) -> Bool {
        let q = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }

        if title.localizedCaseInsensitiveContains(q)
            || sourceAppName.localizedCaseInsensitiveContains(q)
            || minutes.overview.localizedCaseInsensitiveContains(q)
            || manualNotes.localizedCaseInsensitiveContains(q)
            || tags.contains(where: { $0.localizedCaseInsensitiveContains(q) }) {
            return true
        }
        if minutes.topics.contains(where: { $0.title.localizedCaseInsensitiveContains(q) || $0.points.contains(where: { $0.localizedCaseInsensitiveContains(q) }) }) {
            return true
        }
        if minutes.decisions.contains(where: { $0.localizedCaseInsensitiveContains(q) })
            || minutes.openQuestions.contains(where: { $0.localizedCaseInsensitiveContains(q) })
            || minutes.actionItems.contains(where: { $0.task.localizedCaseInsensitiveContains(q) || $0.owner.localizedCaseInsensitiveContains(q) }) {
            return true
        }
        if segments.contains(where: { $0.text.localizedCaseInsensitiveContains(q) || $0.resolvedSpeakerName.localizedCaseInsensitiveContains(q) }) {
            return true
        }
        return false
    }

    /// Returns a concise contextual match snippet when searching (highlighting transcript / action item / note hits).
    public func searchSnippet(for rawQuery: String) -> String? {
        let q = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }

        if let seg = segments.first(where: { $0.text.localizedCaseInsensitiveContains(q) }) {
            return "\(SonoteLocale.t("逐字稿", "Transcript")) \(seg.formattedTimestamp) · \(Self.extractExcerpt(from: seg.text, around: q))"
        }
        if let item = minutes.actionItems.first(where: { $0.task.localizedCaseInsensitiveContains(q) || $0.owner.localizedCaseInsensitiveContains(q) }) {
            return "\(SonoteLocale.t("待办", "Todo")) · \(item.task) (\(item.owner))"
        }
        if let topic = minutes.topics.first(where: { $0.title.localizedCaseInsensitiveContains(q) || $0.points.contains(where: { $0.localizedCaseInsensitiveContains(q) }) }) {
            if let pt = topic.points.first(where: { $0.localizedCaseInsensitiveContains(q) }) {
                return "\(SonoteLocale.t("要点", "Point")) · \(Self.extractExcerpt(from: pt, around: q))"
            }
            return "\(SonoteLocale.t("议题", "Topic")) · \(topic.title)"
        }
        if let decision = minutes.decisions.first(where: { $0.localizedCaseInsensitiveContains(q) }) {
            return "\(SonoteLocale.t("决议", "Decision")) · \(Self.extractExcerpt(from: decision, around: q))"
        }
        if manualNotes.localizedCaseInsensitiveContains(q) {
            return "\(SonoteLocale.t("随手记", "Notes")) · \(Self.extractExcerpt(from: manualNotes.replacingOccurrences(of: "\n", with: " "), around: q))"
        }
        if minutes.overview.localizedCaseInsensitiveContains(q) {
            return Self.extractExcerpt(from: minutes.overview, around: q)
        }
        return nil
    }

    private static func extractExcerpt(from text: String, around query: String, radius: Int = 26) -> String {
        guard let range = text.range(of: query, options: .caseInsensitive) else {
            return String(text.prefix(64))
        }
        let startIdx = text.index(range.lowerBound, offsetBy: -radius, limitedBy: text.startIndex) ?? text.startIndex
        let endIdx = text.index(range.upperBound, offsetBy: radius, limitedBy: text.endIndex) ?? text.endIndex
        let prefix = startIdx > text.startIndex ? "…" : ""
        let suffix = endIdx < text.endIndex ? "…" : ""
        return "\(prefix)\(text[startIdx..<endIdx])\(suffix)"
    }
}
