import Foundation

public struct MarkdownInlineStyle: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let bold = MarkdownInlineStyle(rawValue: 1 << 0)
    public static let italic = MarkdownInlineStyle(rawValue: 1 << 1)
    public static let strikethrough = MarkdownInlineStyle(rawValue: 1 << 2)
    public static let code = MarkdownInlineStyle(rawValue: 1 << 3)
}

public struct MarkdownInlineSpan: Equatable, Sendable {
    public var text: String
    public var style: MarkdownInlineStyle
    public var linkURL: String?

    public init(text: String, style: MarkdownInlineStyle = [], linkURL: String? = nil) {
        self.text = text
        self.style = style
        self.linkURL = linkURL
    }
}

public struct MarkdownListItem: Equatable, Sendable {
    public var text: String
    public var indentLevel: Int
    public var isChecked: Bool?

    public init(text: String, indentLevel: Int = 0, isChecked: Bool? = nil) {
        self.text = text
        self.indentLevel = indentLevel
        self.isChecked = isChecked
    }
}

public struct MarkdownOrderedItem: Equatable, Sendable {
    public var number: String
    public var text: String
    public var indentLevel: Int

    public init(number: String, text: String, indentLevel: Int = 0) {
        self.number = number
        self.text = text
        self.indentLevel = indentLevel
    }
}

public enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bulletList([MarkdownListItem])
    case orderedList([MarkdownOrderedItem])
    case table(headers: [String], rows: [[String]])
    case codeBlock(language: String?, code: String)
    case blockquote(String)
    case divider
}

/// Lightweight, streaming-safe, CJK-friendly GitHub-Flavored Markdown block & inline parser.
/// Handles CJK punctuation adjacent to emphasis delimiters (e.g. `**云端编译：**正文`, `**（重要）**测试`)
/// where strict CommonMark flanking rules fail in Apple's `AttributedString(markdown:)`.
public enum MarkdownParser {

    // MARK: - Block Parser

    public static func parse(_ markdown: String) -> [MarkdownBlock] {
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        var blocks: [MarkdownBlock] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines
            if trimmed.isEmpty {
                i += 1
                continue
            }

            // 1. Fenced code block (``` or ~~~)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let fence = String(trimmed.prefix(3))
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count {
                    let cur = lines[i]
                    if cur.trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                        i += 1
                        break
                    }
                    codeLines.append(cur)
                    i += 1
                }
                blocks.append(.codeBlock(language: lang.isEmpty ? nil : lang, code: codeLines.joined(separator: "\n")))
                continue
            }

            // 2. Horizontal rule (---, ***, ___)
            if isHorizontalRule(trimmed) {
                blocks.append(.divider)
                i += 1
                continue
            }

            // 3. Heading (# ... ######)
            if let (level, text) = parseHeading(trimmed) {
                blocks.append(.heading(level: level, text: text))
                i += 1
                continue
            }

            // 4. GFM Table (header row + separator row like |---|---|)
            if i + 1 < lines.count,
               trimmed.contains("|"),
               isTableSeparator(lines[i + 1].trimmingCharacters(in: .whitespaces)) {
                let headers = parseTableRow(trimmed)
                i += 2
                var rows: [[String]] = []
                while i < lines.count {
                    let rowTrimmed = lines[i].trimmingCharacters(in: .whitespaces)
                    if rowTrimmed.isEmpty || !rowTrimmed.contains("|") {
                        break
                    }
                    var cells = parseTableRow(rowTrimmed)
                    while cells.count < headers.count { cells.append("") }
                    if cells.count > headers.count { cells = Array(cells.prefix(headers.count)) }
                    rows.append(cells)
                    i += 1
                }
                blocks.append(.table(headers: headers, rows: rows))
                continue
            }

            // 5. Blockquote (> ...)
            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while i < lines.count {
                    let qt = lines[i].trimmingCharacters(in: .whitespaces)
                    guard qt.hasPrefix(">") else { break }
                    var content = String(qt.dropFirst())
                    if content.hasPrefix(" ") { content = String(content.dropFirst()) }
                    quoteLines.append(content)
                    i += 1
                }
                blocks.append(.blockquote(quoteLines.joined(separator: "\n")))
                continue
            }

            // 6. Unordered / Task bullet list (- , * , + , • )
            if parseBulletItem(line) != nil {
                var items: [MarkdownListItem] = []
                while i < lines.count {
                    if let item = parseBulletItem(lines[i]) {
                        items.append(item)
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.bulletList(items))
                continue
            }

            // 7. Ordered list (1. , 2. , 1) )
            if parseOrderedItem(line) != nil {
                var items: [MarkdownOrderedItem] = []
                while i < lines.count {
                    if let item = parseOrderedItem(lines[i]) {
                        items.append(item)
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.orderedList(items))
                continue
            }

            // 8. Regular paragraph (merge consecutive non-special lines)
            var paraLines: [String] = [trimmed]
            i += 1
            while i < lines.count {
                let nextLine = lines[i]
                let nextTrimmed = nextLine.trimmingCharacters(in: .whitespaces)
                if nextTrimmed.isEmpty
                    || nextTrimmed.hasPrefix("```")
                    || nextTrimmed.hasPrefix("~~~")
                    || nextTrimmed.hasPrefix(">")
                    || isHorizontalRule(nextTrimmed)
                    || parseHeading(nextTrimmed) != nil
                    || parseBulletItem(nextLine) != nil
                    || parseOrderedItem(nextLine) != nil
                    || (i + 1 < lines.count && nextTrimmed.contains("|") && isTableSeparator(lines[i + 1].trimmingCharacters(in: .whitespaces))) {
                    break
                }
                paraLines.append(nextTrimmed)
                i += 1
            }
            blocks.append(.paragraph(paraLines.joined(separator: "\n")))
        }

        return blocks
    }

    // MARK: - CJK-Friendly Native Inline Parser

    /// Parses inline Markdown (`**bold**`, `*italic*`, `***both***`, `~~strike~~`, `` `code` ``,
    /// `[label](url)`, bare `https://` URLs, `<br>` line breaks, and backslash escapes)
    /// without suffering from CommonMark's CJK punctuation flanking restriction.
    public static func parseInline(_ raw: String) -> [MarkdownInlineSpan] {
        guard !raw.isEmpty else { return [] }
        let normalized = normalizeHTMLBreaks(raw)
        let spans = parseInlineChars(Array(normalized), inheritedStyle: [], inheritedLink: nil)
        return mergeAdjacentSpans(spans)
    }

    private static func normalizeHTMLBreaks(_ s: String) -> String {
        guard s.contains("<") else { return s }
        return s.replacingOccurrences(
            of: #"<br\s*/?>"#,
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    private static func parseInlineChars(
        _ chars: [Character],
        inheritedStyle: MarkdownInlineStyle,
        inheritedLink: String?
    ) -> [MarkdownInlineSpan] {
        var result: [MarkdownInlineSpan] = []
        var plain = ""
        let n = chars.count
        var i = 0

        func flushPlain() {
            if !plain.isEmpty {
                result.append(MarkdownInlineSpan(text: plain, style: inheritedStyle, linkURL: inheritedLink))
                plain.removeAll(keepingCapacity: true)
            }
        }

        while i < n {
            let ch = chars[i]

            // 1. Backslash escape for ASCII punctuation
            if ch == "\\", i + 1 < n, isEscapableASCII(chars[i + 1]) {
                plain.append(chars[i + 1])
                i += 2
                continue
            }

            // 2. Inline code (`code` or ``code``)
            if ch == "`" {
                var tickCount = 0
                while i + tickCount < n && chars[i + tickCount] == "`" {
                    tickCount += 1
                }
                if let closeIdx = findClosingBackticks(in: chars, from: i + tickCount, count: tickCount) {
                    flushPlain()
                    var codeStr = String(chars[(i + tickCount)..<closeIdx])
                    if codeStr.count >= 2 && codeStr.first == " " && codeStr.last == " " && codeStr.contains(where: { $0 != " " }) {
                        codeStr.removeFirst()
                        codeStr.removeLast()
                    }
                    result.append(MarkdownInlineSpan(
                        text: codeStr,
                        style: inheritedStyle.union(.code),
                        linkURL: inheritedLink
                    ))
                    i = closeIdx + tickCount
                    continue
                }
                plain.append(contentsOf: repeatElement("`", count: tickCount))
                i += tickCount
                continue
            }

            // 3. Markdown link [label](url)
            if ch == "[", inheritedLink == nil,
               let (labelChars, urlStr, nextIdx) = parseLink(in: chars, from: i) {
                flushPlain()
                let inner = parseInlineChars(labelChars, inheritedStyle: inheritedStyle, inheritedLink: urlStr)
                result.append(contentsOf: inner)
                i = nextIdx
                continue
            }

            // 4. Bare http:// or https:// autolink
            if ch == "h", inheritedLink == nil,
               let (urlStr, nextIdx) = parseAutolink(in: chars, from: i) {
                flushPlain()
                result.append(MarkdownInlineSpan(text: urlStr, style: inheritedStyle, linkURL: urlStr))
                i = nextIdx
                continue
            }

            // 5. Triple emphasis ***text*** or ___text___
            if (ch == "*" || ch == "_"),
               i + 2 < n, chars[i + 1] == ch, chars[i + 2] == ch,
               canOpenDelimiter(ch, in: chars, at: i, runLength: 3),
               let closeIdx = findClosingDelimiter(ch, runLength: 3, in: chars, from: i + 3) {
                flushPlain()
                let inner = Array(chars[(i + 3)..<closeIdx])
                result.append(contentsOf: parseInlineChars(
                    inner,
                    inheritedStyle: inheritedStyle.union([.bold, .italic]),
                    inheritedLink: inheritedLink
                ))
                i = closeIdx + 3
                continue
            }

            // 6. Bold **text** or __text__
            if (ch == "*" || ch == "_"),
               i + 1 < n, chars[i + 1] == ch,
               canOpenDelimiter(ch, in: chars, at: i, runLength: 2),
               let closeIdx = findClosingDelimiter(ch, runLength: 2, in: chars, from: i + 2) {
                flushPlain()
                let inner = Array(chars[(i + 2)..<closeIdx])
                result.append(contentsOf: parseInlineChars(
                    inner,
                    inheritedStyle: inheritedStyle.union(.bold),
                    inheritedLink: inheritedLink
                ))
                i = closeIdx + 2
                continue
            }

            // 7. Strikethrough ~~text~~
            if ch == "~",
               i + 1 < n, chars[i + 1] == "~",
               canOpenDelimiter("~", in: chars, at: i, runLength: 2),
               let closeIdx = findClosingDelimiter("~", runLength: 2, in: chars, from: i + 2) {
                flushPlain()
                let inner = Array(chars[(i + 2)..<closeIdx])
                result.append(contentsOf: parseInlineChars(
                    inner,
                    inheritedStyle: inheritedStyle.union(.strikethrough),
                    inheritedLink: inheritedLink
                ))
                i = closeIdx + 2
                continue
            }

            // 8. Italic *text* or _text_
            if (ch == "*" || ch == "_"),
               canOpenDelimiter(ch, in: chars, at: i, runLength: 1),
               let closeIdx = findClosingDelimiter(ch, runLength: 1, in: chars, from: i + 1) {
                flushPlain()
                let inner = Array(chars[(i + 1)..<closeIdx])
                result.append(contentsOf: parseInlineChars(
                    inner,
                    inheritedStyle: inheritedStyle.union(.italic),
                    inheritedLink: inheritedLink
                ))
                i = closeIdx + 1
                continue
            }

            plain.append(ch)
            i += 1
        }

        flushPlain()
        return result
    }

    private static func canOpenDelimiter(_ marker: Character, in chars: [Character], at index: Int, runLength: Int) -> Bool {
        let after = index + runLength
        guard after < chars.count else { return false }
        // Don't start emphasis with whitespace (prevents `2 * 3 * 4` or `- * item` misfires)
        if chars[after].isWhitespace { return false }
        // For underscore delimiters, avoid breaking snake_case identifiers like `foo_bar_baz`
        if marker == "_", index > 0, isASCIIWordChar(chars[index - 1]) {
            return false
        }
        return true
    }

    private static func findClosingDelimiter(
        _ marker: Character,
        runLength: Int,
        in chars: [Character],
        from start: Int
    ) -> Int? {
        let n = chars.count
        var j = start
        while j + runLength <= n {
            let c = chars[j]
            // Skip escaped chars
            if c == "\\", j + 1 < n {
                j += 2
                continue
            }
            // Skip inline code spans so delimiters inside `...` never close outer bold/italic
            if c == "`" {
                var ticks = 0
                while j + ticks < n && chars[j + ticks] == "`" { ticks += 1 }
                if let codeEnd = findClosingBackticks(in: chars, from: j + ticks, count: ticks) {
                    j = codeEnd + ticks
                    continue
                }
                j += ticks
                continue
            }

            if c == marker {
                // Count full run length at j
                var run = 0
                while j + run < n && chars[j + run] == marker { run += 1 }

                if run >= runLength && j > start {
                    // For single `*` / `_`, don't split a `**` / `__` run unless closing an inner span cleanly
                    if runLength == 1 && run == 2 {
                        j += run
                        continue
                    }

                    let candidatePos = (run > runLength) ? (j + run - runLength) : j
                    let prevChar = chars[candidatePos - 1]
                    let afterPos = candidatePos + runLength

                    // Closing delimiter must not immediately follow whitespace (unless inner has no non-space?)
                    let validBefore = !prevChar.isWhitespace
                    // Underscore closing must not be immediately followed by an ASCII word char
                    let validAfter = (marker != "_") || (afterPos >= n) || !isASCIIWordChar(chars[afterPos])

                    if validBefore && validAfter {
                        return candidatePos
                    }
                }
                j += run
                continue
            }

            j += 1
        }
        return nil
    }

    private static func findClosingBackticks(in chars: [Character], from start: Int, count: Int) -> Int? {
        let n = chars.count
        var j = start
        while j < n {
            if chars[j] == "`" {
                var run = 0
                while j + run < n && chars[j + run] == "`" { run += 1 }
                if run == count {
                    return j
                }
                j += run
            } else {
                j += 1
            }
        }
        return nil
    }

    private static func parseLink(in chars: [Character], from start: Int) -> ([Character], String, Int)? {
        let n = chars.count
        guard start < n, chars[start] == "[" else { return nil }
        var depth = 1
        var j = start + 1
        while j < n && depth > 0 {
            if chars[j] == "\\", j + 1 < n {
                j += 2
                continue
            }
            if chars[j] == "`" {
                var ticks = 0
                while j + ticks < n && chars[j + ticks] == "`" { ticks += 1 }
                if let close = findClosingBackticks(in: chars, from: j + ticks, count: ticks) {
                    j = close + ticks
                    continue
                }
                j += ticks
                continue
            }
            if chars[j] == "[" { depth += 1 }
            else if chars[j] == "]" { depth -= 1 }
            if depth == 0 { break }
            j += 1
        }
        guard depth == 0, j + 1 < n, chars[j + 1] == "(" else { return nil }
        let labelChars = Array(chars[(start + 1)..<j])

        var parenDepth = 1
        var k = j + 2
        while k < n && parenDepth > 0 {
            if chars[k] == "\n" { return nil }
            if chars[k] == "(" { parenDepth += 1 }
            else if chars[k] == ")" { parenDepth -= 1 }
            if parenDepth == 0 { break }
            k += 1
        }
        guard parenDepth == 0 else { return nil }
        let urlStr = String(chars[(j + 2)..<k]).trimmingCharacters(in: .whitespaces)
        guard !urlStr.isEmpty else { return nil }
        return (labelChars, urlStr, k + 1)
    }

    private static func parseAutolink(in chars: [Character], from start: Int) -> (String, Int)? {
        let n = chars.count
        let remaining = n - start
        let isHTTPS = remaining >= 8 && String(chars[start..<(start + 8)]) == "https://"
        let isHTTP = remaining >= 7 && String(chars[start..<(start + 7)]) == "http://"
        guard isHTTPS || isHTTP else { return nil }

        var j = start + (isHTTPS ? 8 : 7)
        while j < n {
            let c = chars[j]
            if c.isWhitespace || c == "<" || c == ">" || c == "\"" || c == "'" || isCJKOrFullWidthPunctuation(c) {
                break
            }
            j += 1
        }
        // Trim trailing ASCII sentence punctuation
        let trailingPunct: Set<Character> = [".", ",", ";", ":", "!", "?", ")", "]"]
        while j > start + 8 && trailingPunct.contains(chars[j - 1]) {
            j -= 1
        }
        let urlStr = String(chars[start..<j])
        guard urlStr.count > (isHTTPS ? 8 : 7) else { return nil }
        return (urlStr, j)
    }

    private static func isEscapableASCII(_ c: Character) -> Bool {
        let set: Set<Character> = ["\\", "`", "*", "_", "{", "}", "[", "]", "(", ")", "#", "+", "-", ".", "!", "~", "|"]
        return set.contains(c)
    }

    private static func isASCIIWordChar(_ c: Character) -> Bool {
        guard let scalar = c.unicodeScalars.first, c.unicodeScalars.count == 1 else { return false }
        let v = scalar.value
        return (0x30...0x39).contains(v) || (0x41...0x5A).contains(v) || (0x61...0x7A).contains(v)
    }

    private static func isCJKOrFullWidthPunctuation(_ c: Character) -> Bool {
        guard let scalar = c.unicodeScalars.first else { return false }
        let v = scalar.value
        return (0x3000...0x303F).contains(v) || (0x4E00...0x9FFF).contains(v) || (0xFF00...0xFFEF).contains(v)
    }

    private static func mergeAdjacentSpans(_ spans: [MarkdownInlineSpan]) -> [MarkdownInlineSpan] {
        var merged: [MarkdownInlineSpan] = []
        for span in spans where !span.text.isEmpty {
            if let last = merged.last, last.style == span.style, last.linkURL == span.linkURL {
                merged[merged.count - 1].text += span.text
            } else {
                merged.append(span)
            }
        }
        return merged
    }

    // MARK: - Line Matchers

    private static func isHorizontalRule(_ trimmed: String) -> Bool {
        let noSpaces = trimmed.replacingOccurrences(of: " ", with: "")
        guard noSpaces.count >= 3 else { return false }
        let chars = Set(noSpaces)
        return chars.count == 1 && (chars.contains("-") || chars.contains("*") || chars.contains("_"))
    }

    private static func parseHeading(_ trimmed: String) -> (Int, String)? {
        var count = 0
        for ch in trimmed {
            if ch == "#" { count += 1 } else { break }
        }
        guard (1...6).contains(count) else { return nil }
        let rest = trimmed.dropFirst(count)
        guard let first = rest.first, first == " " || first == "\t" || first == "\u{3000}" else { return nil }
        let text = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        return (count, text)
    }

    private static func parseBulletItem(_ rawLine: String) -> MarkdownListItem? {
        var leadingSpaces = 0
        for ch in rawLine {
            if ch == " " { leadingSpaces += 1 }
            else if ch == "\t" { leadingSpaces += 2 }
            else { break }
        }
        let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return nil }

        let markers = ["- ", "* ", "+ ", "• "]
        var body: String? = nil
        for marker in markers where trimmed.hasPrefix(marker) {
            body = String(trimmed.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
            break
        }
        guard var content = body else { return nil }

        var checked: Bool? = nil
        if content.hasPrefix("[ ] ") {
            checked = false
            content = String(content.dropFirst(4))
        } else if content.hasPrefix("[x] ") || content.hasPrefix("[X] ") {
            checked = true
            content = String(content.dropFirst(4))
        }

        let indent = min(3, leadingSpaces / 2)
        return MarkdownListItem(text: content, indentLevel: indent, isChecked: checked)
    }

    private static func parseOrderedItem(_ rawLine: String) -> MarkdownOrderedItem? {
        var leadingSpaces = 0
        for ch in rawLine {
            if ch == " " { leadingSpaces += 1 }
            else if ch == "\t" { leadingSpaces += 2 }
            else { break }
        }
        let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
        guard let delimIdx = trimmed.firstIndex(where: { $0 == "." || $0 == ")" }) else { return nil }
        let prefix = trimmed[..<delimIdx]
        guard !prefix.isEmpty, prefix.count <= 4, prefix.allSatisfy(\.isNumber) else { return nil }
        let afterDelim = trimmed.index(after: delimIdx)
        guard afterDelim < trimmed.endIndex, trimmed[afterDelim] == " " || trimmed[afterDelim] == "\t" else { return nil }
        let text = trimmed[trimmed.index(after: afterDelim)...].trimmingCharacters(in: .whitespaces)
        let indent = min(3, leadingSpaces / 2)
        return MarkdownOrderedItem(number: String(prefix), text: text, indentLevel: indent)
    }

    private static func isTableSeparator(_ trimmed: String) -> Bool {
        guard trimmed.contains("-") && trimmed.contains("|") else { return false }
        let allowed = CharacterSet(charactersIn: "|-: \t")
        return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func parseTableRow(_ trimmed: String) -> [String] {
        var s = trimmed
        if s.hasPrefix("|") { s.removeFirst() }
        if s.hasSuffix("|") && !s.hasSuffix("\\|") { s.removeLast() }

        // Split on unescaped `|` so cells with `\|` stay intact
        var cells: [String] = []
        var current = ""
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            if chars[i] == "\\", i + 1 < chars.count, chars[i + 1] == "|" {
                current.append("|")
                i += 2
            } else if chars[i] == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current.removeAll(keepingCapacity: true)
                i += 1
            } else {
                current.append(chars[i])
                i += 1
            }
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }
}
