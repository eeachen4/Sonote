import Foundation

// MARK: - SSE, Token Usage, Thinking-Tag & Structured SmartMinutes Parsers

extension GPTClient {

    public struct AnthropicSSEEvent: Equatable {
        public var delta: String?
        public var inputTokens: Int?
        public var outputTokens: Int?
        public var cachedTokens: Int?
        public var errorMessage: String?

        public init(delta: String? = nil, inputTokens: Int? = nil, outputTokens: Int? = nil, cachedTokens: Int? = nil, errorMessage: String? = nil) {
            self.delta = delta
            self.inputTokens = inputTokens
            self.outputTokens = outputTokens
            self.cachedTokens = cachedTokens
            self.errorMessage = errorMessage
        }
    }

    public static func parseAnthropicSSEDataLine(_ jsonString: String) -> AnthropicSSEEvent {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return AnthropicSSEEvent()
        }
        let type = json["type"] as? String ?? ""
        if type == "content_block_delta",
           let delta = json["delta"] as? [String: Any],
           let text = delta["text"] as? String {
            return AnthropicSSEEvent(delta: text)
        }
        if type == "message_start",
           let msg = json["message"] as? [String: Any],
           let usage = msg["usage"] as? [String: Any] {
            return AnthropicSSEEvent(
                inputTokens: usage["input_tokens"] as? Int,
                outputTokens: usage["output_tokens"] as? Int,
                cachedTokens: usage["cache_read_input_tokens"] as? Int
            )
        }
        if type == "message_delta",
           let usage = json["usage"] as? [String: Any] {
            return AnthropicSSEEvent(outputTokens: usage["output_tokens"] as? Int)
        }
        if type == "error",
           let err = json["error"] as? [String: Any],
           let msg = err["message"] as? String {
            return AnthropicSSEEvent(errorMessage: msg)
        }
        return AnthropicSSEEvent()
    }

    public static func parseGeminiSSEDataLine(_ jsonString: String) -> ChatCompletionsSSEChunk {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ChatCompletionsSSEChunk()
        }
        var textDelta: String? = nil
        if let candidates = json["candidates"] as? [[String: Any]],
           let content = candidates.first?["content"] as? [String: Any],
           let parts = content["parts"] as? [[String: Any]] {
            let joined = parts.compactMap { $0["text"] as? String }.joined()
            if !joined.isEmpty { textDelta = joined }
        }
        var usage: TokenUsage? = nil
        if let meta = json["usageMetadata"] as? [String: Any] {
            let prompt = meta["promptTokenCount"] as? Int ?? 0
            let cand = meta["candidatesTokenCount"] as? Int ?? 0
            let cached = meta["cachedContentTokenCount"] as? Int ?? 0
            let thoughts = meta["thoughtsTokenCount"] as? Int ?? 0
            if prompt > 0 || cand > 0 {
                usage = TokenUsage(
                    inputTokens: prompt,
                    outputTokens: cand,
                    cachedTokens: cached,
                    reasoningTokens: thoughts,
                    requestCount: 1,
                    isEstimated: false
                )
            }
        }
        return ChatCompletionsSSEChunk(delta: textDelta, usage: usage)
    }

    public struct CodexSSEEvent: Equatable {
        public var delta: String?
        public var completedText: String?
        public var errorMessage: String?
        public var usage: TokenUsage?

        public init(delta: String? = nil, completedText: String? = nil, errorMessage: String? = nil, usage: TokenUsage? = nil) {
            self.delta = delta
            self.completedText = completedText
            self.errorMessage = errorMessage
            self.usage = usage
        }
    }

    public struct ChatCompletionsSSEChunk: Equatable {
        public var delta: String?
        public var reasoningDelta: String?
        public var usage: TokenUsage?

        public init(delta: String? = nil, reasoningDelta: String? = nil, usage: TokenUsage? = nil) {
            self.delta = delta
            self.reasoningDelta = reasoningDelta
            self.usage = usage
        }
    }

    public static func parseCodexSSEDataLine(_ jsonString: String) -> CodexSSEEvent {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return CodexSSEEvent()
        }

        let eventType = json["type"] as? String ?? ""

        if eventType == "response.output_text.delta", let delta = json["delta"] as? String {
            return CodexSSEEvent(delta: delta)
        }

        if eventType == "response.output_text.done", let text = json["text"] as? String {
            return CodexSSEEvent(completedText: text)
        }

        if eventType == "response.completed",
           let responseObj = json["response"] as? [String: Any] {
            var texts: [String] = []
            if let output = responseObj["output"] as? [[String: Any]] {
                for item in output {
                    if let content = item["content"] as? [[String: Any]] {
                        for part in content {
                            if let text = part["text"] as? String {
                                texts.append(text)
                            }
                        }
                    }
                }
            }
            var usage: TokenUsage? = nil
            if let usageDict = responseObj["usage"] as? [String: Any] {
                usage = parseUsageDict(usageDict)
            }
            return CodexSSEEvent(
                completedText: texts.isEmpty ? nil : texts.joined(),
                usage: usage
            )
        }

        if eventType == "error" || eventType == "response.failed" {
            if let err = json["error"] as? [String: Any], let msg = err["message"] as? String {
                return CodexSSEEvent(errorMessage: msg)
            }
            if let resp = json["response"] as? [String: Any],
               let err = resp["error"] as? [String: Any],
               let msg = err["message"] as? String {
                return CodexSSEEvent(errorMessage: msg)
            }
            if let msg = json["message"] as? String {
                return CodexSSEEvent(errorMessage: msg)
            }
        }

        return CodexSSEEvent()
    }

    public static func parseChatCompletionsSSEDataLine(_ jsonString: String) -> String? {
        parseChatCompletionsSSEChunk(jsonString).delta
    }

    public static func parseChatCompletionsSSEChunk(_ jsonString: String) -> ChatCompletionsSSEChunk {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ChatCompletionsSSEChunk()
        }

        var deltaContent: String? = nil
        var reasoningContent: String? = nil
        if let choices = json["choices"] as? [[String: Any]],
           let delta = choices.first?["delta"] as? [String: Any] {
            if let content = delta["content"] as? String {
                deltaContent = content
            }
            if let reasoning = delta["reasoning_content"] as? String, !reasoning.isEmpty {
                reasoningContent = reasoning
            }
        }

        var usage: TokenUsage? = nil
        if let usageDict = json["usage"] as? [String: Any] {
            usage = parseUsageDict(usageDict)
        }

        return ChatCompletionsSSEChunk(delta: deltaContent, reasoningDelta: reasoningContent, usage: usage)
    }

    public static func parseUsageDict(_ dict: [String: Any]) -> TokenUsage? {
        let input = (dict["input_tokens"] as? Int) ?? (dict["prompt_tokens"] as? Int) ?? 0
        let output = (dict["output_tokens"] as? Int) ?? (dict["completion_tokens"] as? Int) ?? 0
        let total = (dict["total_tokens"] as? Int) ?? (input + output)
        guard input > 0 || output > 0 || total > 0 else { return nil }

        let inputDetails = (dict["input_tokens_details"] as? [String: Any])
            ?? (dict["prompt_tokens_details"] as? [String: Any])
        let outputDetails = (dict["output_tokens_details"] as? [String: Any])
            ?? (dict["completion_tokens_details"] as? [String: Any])

        // Support both OpenAI `prompt_tokens_details.cached_tokens` and DeepSeek's top-level `prompt_cache_hit_tokens`
        let cached = (inputDetails?["cached_tokens"] as? Int)
            ?? (dict["prompt_cache_hit_tokens"] as? Int)
            ?? 0
        let reasoning = (outputDetails?["reasoning_tokens"] as? Int) ?? 0

        let resolvedInput = input > 0 ? input : max(0, total - output)
        let resolvedOutput = output > 0 ? output : max(0, total - resolvedInput)

        return TokenUsage(
            inputTokens: resolvedInput,
            outputTokens: resolvedOutput,
            cachedTokens: cached,
            reasoningTokens: reasoning,
            requestCount: 1,
            isEstimated: false
        )
    }

    public static func parseSmartMinutes(from rawText: String, isFinal: Bool) -> SmartMinutes {
        let cleanedJSON = extractJSONObject(from: rawText)
        if let data = cleanedJSON.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let suggestedTitle = (dict["suggestedTitle"] as? String) ?? ""
            let overview = (dict["overview"] as? String) ?? ""
            let participants = (dict["participants"] as? [String]) ?? []
            let decisions = (dict["decisions"] as? [String]) ?? []
            let openQuestions = (dict["openQuestions"] as? [String]) ?? []

            var topics: [TopicSection] = []
            if let rawTopics = dict["topics"] as? [[String: Any]] {
                for t in rawTopics {
                    let title = (t["title"] as? String) ?? "讨论要点"
                    let points = (t["points"] as? [String]) ?? []
                    if !points.isEmpty || !title.isEmpty {
                        topics.append(TopicSection(title: title, points: points))
                    }
                }
            }

            var actionItems: [ActionItem] = []
            if let rawActions = dict["actionItems"] as? [[String: Any]] {
                for item in rawActions {
                    let task = (item["task"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    guard !task.isEmpty else { continue }
                    let owner = (item["owner"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let due = (item["dueDate"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    actionItems.append(ActionItem(
                        task: task,
                        owner: (owner?.isEmpty == false) ? owner! : "待定",
                        dueDate: due ?? ""
                    ))
                }
            }

            return SmartMinutes(
                suggestedTitle: suggestedTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                overview: overview.trimmingCharacters(in: .whitespacesAndNewlines),
                topics: topics,
                decisions: decisions.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
                actionItems: actionItems,
                openQuestions: openQuestions.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
                participants: participants.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
                lastUpdatedAt: Date(),
                isFinalized: isFinal,
                rawMarkdownFallback: nil
            )
        }

        return SmartMinutes(
            overview: "",
            lastUpdatedAt: Date(),
            isFinalized: isFinal,
            rawMarkdownFallback: stripThinkingTags(rawText)
        )
    }

    /// Removes inline `<think>...</think>` chain-of-thought blocks emitted by reasoning models
    /// (e.g. DeepSeek-R1 / Qwen3 / QwQ on third-party relays or Ollama) before JSON/Markdown parsing.
    public static func stripThinkingTags(_ text: String) -> String {
        var result = text
        while let start = result.range(of: "<think>", options: .caseInsensitive) {
            if let end = result.range(of: "</think>", options: .caseInsensitive, range: start.upperBound..<result.endIndex) {
                result.removeSubrange(start.lowerBound..<end.upperBound)
            } else {
                result.removeSubrange(start.lowerBound..<result.endIndex)
                break
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func extractJSONObject(from text: String) -> String {
        let trimmed = stripThinkingTags(text)
        if let firstBrace = trimmed.firstIndex(of: "{"),
           let lastBrace = trimmed.lastIndex(of: "}"),
           firstBrace <= lastBrace {
            return String(trimmed[firstBrace...lastBrace])
        }
        return trimmed
    }

    func buildTranscriptPayload(meeting: MeetingSession) -> String {
        let full = meeting.transcriptAsText
        if full.isEmpty {
            return "（暂无语音转写内容）"
        }
        // Keep up to ~48,000 characters so even 2+ hour meetings fit cleanly
        let maxChars = 48_000
        if full.count <= maxChars {
            return full
        }
        let head = full.prefix(8_000)
        let tail = full.suffix(maxChars - 8_200)
        return "\(head)\n\n[...中段已省略部分较早内容...]\n\n\(tail)"
    }
}
