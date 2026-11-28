import Foundation

/// Detects newly corrected proper nouns or technical terms when a user manually fixes a transcript typo,
/// enabling one-click addition to `AppSettings.glossaryTerms` so future Qwen3-ASR runs recognize them accurately.
public enum GlossarySuggestionExtractor {
    private static let punctuationSet = CharacterSet.punctuationCharacters
        .union(.symbols)
        .union(.whitespacesAndNewlines)

    public static func extractCandidateTerms(
        original: String,
        edited: String,
        existingGlossary: [String]
    ) -> [String] {
        let origTrimmed = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let editTrimmed = edited.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !origTrimmed.isEmpty, !editTrimmed.isEmpty, origTrimmed != editTrimmed else {
            return []
        }

        let origChars = Array(origTrimmed)
        let editChars = Array(editTrimmed)

        // Find longest common prefix
        var prefixLen = 0
        while prefixLen < origChars.count && prefixLen < editChars.count && origChars[prefixLen] == editChars[prefixLen] {
            prefixLen += 1
        }

        // Find longest common suffix without overlapping prefix
        var origEnd = origChars.count
        var editEnd = editChars.count
        while origEnd > prefixLen && editEnd > prefixLen && origChars[origEnd - 1] == editChars[editEnd - 1] {
            origEnd -= 1
            editEnd -= 1
        }

        guard editEnd > prefixLen else { return [] }

        // Expand slightly to word/alphanumeric boundary if the edit occurred inside a Latin/mixed token (e.g. "MLx" -> "MLX")
        var start = prefixLen
        var end = editEnd
        while start > 0 && isLatinWordChar(editChars[start - 1]) && isLatinWordChar(editChars[start]) {
            start -= 1
        }
        while end < editChars.count && isLatinWordChar(editChars[end - 1]) && isLatinWordChar(editChars[end]) {
            end += 1
        }

        // If single-character CJK substitution happened inside a 2-4 char CJK noun (e.g., "新奇科技" -> "星驰科技" or "张希彤" -> "张熙彤"),
        // include 1 adjacent CJK character when the changed span is just 1 char.
        if (end - start) == 1 && isCJK(editChars[start]) {
            if start > 0 && isCJK(editChars[start - 1]) {
                start -= 1
            } else if end < editChars.count && isCJK(editChars[end]) {
                end += 1
            }
        }

        let rawSpan = String(editChars[start..<end])
            .trimmingCharacters(in: punctuationSet)
        guard !rawSpan.isEmpty else { return [] }

        // Split on clause punctuation if the user edited multiple clauses
        let pieces = rawSpan
            .components(separatedBy: CharacterSet(charactersIn: "，。！？、；：,.!?;:\n\t"))
            .map { $0.trimmingCharacters(in: punctuationSet) }
            .filter { isPlausibleGlossaryTerm($0) }

        let existingLower = Set(existingGlossary.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        var results: [String] = []
        for term in pieces {
            let key = term.lowercased()
            if !existingLower.contains(key) && !results.contains(where: { $0.caseInsensitiveCompare(term) == .orderedSame }) {
                results.append(term)
            }
            if results.count >= 2 { break }
        }
        return results
    }

    private static func isPlausibleGlossaryTerm(_ term: String) -> Bool {
        let len = term.count
        guard len >= 2 && len <= 20 else { return false }
        // Ignore pure digits/punctuation
        let hasLetter = term.unicodeScalars.contains { CharacterSet.letters.contains($0) || (0x4E00...0x9FFF).contains($0.value) }
        guard hasLetter else { return false }
        // Ignore long multi-word sentences (>3 spaces)
        if term.filter({ $0 == " " }).count > 2 { return false }
        return true
    }

    private static func isLatinWordChar(_ ch: Character) -> Bool {
        ch.isASCII && (ch.isLetter || ch.isNumber || ch == "-" || ch == "_")
    }

    private static func isCJK(_ ch: Character) -> Bool {
        guard let scalar = ch.unicodeScalars.first else { return false }
        return (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value)
    }
}
