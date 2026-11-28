import Foundation

/// Resolves clickable audio/transcript timestamp citations for structured minutes bullets,
/// supporting both explicit `[MM:SS]` / `[H:MM:SS]` markers from AI and automatic local
/// keyword/CJK-bigram fallback matching against `TranscriptSegment`s.
public enum MinutesTimestampMatcher {
    public struct Match: Equatable, Sendable {
        public let displayText: String
        public let timestamp: TimeInterval
        public let formattedTimestamp: String
        public let isExplicit: Bool

        public init(displayText: String, timestamp: TimeInterval, formattedTimestamp: String, isExplicit: Bool) {
            self.displayText = displayText
            self.timestamp = timestamp
            self.formattedTimestamp = formattedTimestamp
            self.isExplicit = isExplicit
        }
    }

    private static let explicitRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"\s*[\[\【](\d{1,2}):(\d{2})(?::(\d{2}))?[\]\】]"#,
        options: []
    )

    /// Strips all explicit `[MM:SS]` / `[H:MM:SS]` / `【MM:SS】` citation markers from text
    /// (used for static PNG exports, non-interactive views, and clean summaries).
    public static func strippingExplicitCitations(in text: String) -> String {
        guard let regex = explicitRegex else { return text }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let stripped = regex.stringByReplacingMatches(in: text, options: [], range: nsRange, withTemplate: "")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? text : stripped
    }

    /// Parses an explicit `[MM:SS]` or `[H:MM:SS]` citation embedded in a bullet string.
    public static func parseExplicitCitation(in text: String) -> Match? {
        guard let regex = explicitRegex else { return nil }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let m = regex.firstMatch(in: text, options: [], range: nsRange),
              let fullRange = Range(m.range, in: text),
              let r1 = Range(m.range(at: 1), in: text),
              let r2 = Range(m.range(at: 2), in: text),
              let v1 = Int(text[r1]),
              let v2 = Int(text[r2]) else {
            return nil
        }

        let seconds: TimeInterval
        if m.range(at: 3).location != NSNotFound,
           let r3 = Range(m.range(at: 3), in: text),
           let v3 = Int(text[r3]) {
            guard v2 < 60, v3 < 60 else { return nil }
            seconds = TimeInterval(v1 * 3600 + v2 * 60 + v3)
        } else {
            guard v2 < 60 else { return nil }
            seconds = TimeInterval(v1 * 60 + v2)
        }

        var cleaned = text
        cleaned.removeSubrange(fullRange)
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { cleaned = text }

        return Match(
            displayText: cleaned,
            timestamp: seconds,
            formattedTimestamp: formatTimestamp(seconds),
            isExplicit: true
        )
    }

    /// Resolves either an explicit `[MM:SS]` marker or a high-confidence transcript segment match.
    public static func resolve(for text: String, segments: [TranscriptSegment]) -> Match? {
        if let explicit = parseExplicitCitation(in: text) {
            return explicit
        }
        guard !segments.isEmpty else { return nil }

        let queryTokens = extractMatchTokens(from: text)
        guard queryTokens.count >= 2 else { return nil }

        var bestSegment: TranscriptSegment?
        var bestScore: Double = 0
        var bestOverlap: Int = 0

        for seg in segments {
            let segTokens = extractMatchTokens(from: seg.text)
            guard !segTokens.isEmpty else { continue }
            let overlap = queryTokens.intersection(segTokens).count
            guard overlap >= 2 else { continue }
            // Weighted recall biased toward meaningful token hits
            let score = Double(overlap) / Double(min(queryTokens.count, 18))
            if score > bestScore || (score == bestScore && overlap > bestOverlap) {
                bestScore = score
                bestOverlap = overlap
                bestSegment = seg
            }
        }

        guard let matched = bestSegment, bestScore >= 0.22 || bestOverlap >= 4 else {
            return nil
        }

        return Match(
            displayText: text,
            timestamp: matched.timestamp,
            formattedTimestamp: matched.formattedTimestamp,
            isExplicit: false
        )
    }

    public static func formatTimestamp(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    /// Extracts normalized Latin/alphanumeric words (>=2 chars) and CJK bigrams for fast local matching.
    private static func extractMatchTokens(from text: String) -> Set<String> {
        let lower = text.lowercased()
        var tokens: Set<String> = []
        var latinBuffer = ""
        var cjkChars: [Character] = []

        func flushLatin() {
            if latinBuffer.count >= 2 && !stopWords.contains(latinBuffer) {
                tokens.insert(latinBuffer)
            }
            latinBuffer.removeAll(keepingCapacity: true)
        }

        func flushCJK() {
            if cjkChars.count >= 2 {
                for i in 0..<(cjkChars.count - 1) {
                    let bigram = String([cjkChars[i], cjkChars[i + 1]])
                    if !cjkStopBigrams.contains(bigram) {
                        tokens.insert(bigram)
                    }
                }
            }
            cjkChars.removeAll(keepingCapacity: true)
        }

        for ch in lower {
            if isCJK(ch) {
                flushLatin()
                cjkChars.append(ch)
            } else if ch.isASCII && (ch.isLetter || ch.isNumber) {
                flushCJK()
                latinBuffer.append(ch)
            } else {
                flushLatin()
                flushCJK()
            }
        }
        flushLatin()
        flushCJK()
        return tokens
    }

    private static func isCJK(_ ch: Character) -> Bool {
        guard let scalar = ch.unicodeScalars.first else { return false }
        return (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value)
    }

    private static let stopWords: Set<String> = [
        "the", "and", "for", "with", "that", "this", "from", "will", "have", "are", "was", "were", "not", "but", "all", "can"
    ]

    private static let cjkStopBigrams: Set<String> = [
        "我们", "你们", "他们", "这个", "那个", "一个", "一下", "进行", "通过", "可以", "需要", "已经", "目前", "相关", "以及", "关于"
    ]
}
