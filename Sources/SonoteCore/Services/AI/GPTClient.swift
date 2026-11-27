import Foundation

public enum GPTClientError: LocalizedError {
    case invalidEndpoint(String)
    case httpError(Int, String)
    case emptyResponse
    case audioTranscriptionRequiresAPIKey

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint(let url): return SonoteLocale.t("无效的接口地址：\(url)", "Invalid API endpoint: \(url)")
        case .httpError(let code, let detail): return SonoteLocale.t("AI 接口请求失败 (HTTP \(code))：\(detail)", "AI request failed (HTTP \(code)): \(detail)")
        case .emptyResponse: return SonoteLocale.t("AI 未返回有效内容。", "AI returned an empty response.")
        case .audioTranscriptionRequiresAPIKey: return SonoteLocale.t("OpenAI 音频转写需要 OpenAI API Key；若使用本机 Codex Auth，请使用「Apple 本机实时识别」。", "OpenAI audio transcription requires an OpenAI API Key; use MLX Qwen3-ASR or Apple Speech otherwise.")
        }
    }
}

public struct GPTCompletionResult: Sendable {
    public var text: String
    public var usage: TokenUsage

    public init(text: String, usage: TokenUsage) {
        self.text = text
        self.usage = usage
    }
}

public struct GPTConnectionTestResult: Sendable {
    public var success: Bool
    public var backendDescription: String
    public var modelUsed: String
    public var latencyMs: Int
    public var message: String

    public init(success: Bool, backendDescription: String, modelUsed: String, latencyMs: Int, message: String) {
        self.success = success
        self.backendDescription = backendDescription
        self.modelUsed = modelUsed
        self.latencyMs = latencyMs
        self.message = message
    }
}

public final class GPTClient: @unchecked Sendable {
    public static let shared = GPTClient()

    private let authManager: AuthManager
    let session: URLSession

    public static let codexResponsesURL = "https://chatgpt.com/backend-api/codex/responses"

    public init(authManager: AuthManager = .shared, session: URLSession = .shared) {
        self.authManager = authManager
        self.session = session
    }

    // MARK: - Connection Test

    public func testConnection(settings: AppSettings) async -> GPTConnectionTestResult {
        let start = Date()
        do {
            let credential = try authManager.resolveCredential(settings: settings)
            let model = activeModel(for: credential, settings: settings)
            let reply = try await complete(
                instructions: "你是一个连接测试助手。请只回复简短的两个字：正常",
                userPrompt: "测试连接",
                settings: settings
            )
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
            return GPTConnectionTestResult(
                success: true,
                backendDescription: credential.displayBadge,
                modelUsed: model,
                latencyMs: elapsed,
                message: SonoteLocale.t(
                    "连接成功（回复：\(reply.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30))）",
                    "Connected (reply: \(reply.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30)))"
                )
            )
        } catch {
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
            return GPTConnectionTestResult(
                success: false,
                backendDescription: settings.authMode.displayName,
                modelUsed: settings.model,
                latencyMs: elapsed,
                message: error.localizedDescription
            )
        }
    }

    /// Lightweight best-effort single-line translation for the live floating subtitle bar.
    public func translateSubtitleLine(_ text: String, settings: AppSettings) async -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else { return nil }
        let hasCJK = trimmed.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
        let targetLang = hasCJK ? "natural concise English" : "自然简洁的简体中文"
        do {
            let reply = try await complete(
                instructions: "You are a real-time meeting caption translator. Output ONLY the translated single line in \(targetLang), with no quotes, notes, or explanations.",
                userPrompt: trimmed,
                settings: settings
            )
            let cleaned = Self.stripThinkingTags(reply)
            return cleaned.isEmpty ? nil : cleaned
        } catch {
            return nil
        }
    }

    // MARK: - Smart Minutes Generation (Doubao Work Style)

    public func generateMinutes(
        for meeting: MeetingSession,
        settings: AppSettings,
        isFinal: Bool,
        onStreamDelta: (@Sendable (String) -> Void)? = nil
    ) async throws -> SmartMinutes {
        let (minutes, _) = try await generateMinutesWithUsage(
            for: meeting,
            settings: settings,
            isFinal: isFinal,
            onStreamDelta: onStreamDelta
        )
        return minutes
    }

    public func generateMinutesWithUsage(
        for meeting: MeetingSession,
        settings: AppSettings,
        isFinal: Bool,
        deltaSegmentsOnly: [TranscriptSegment]? = nil,
        onStreamDelta: (@Sendable (String) -> Void)? = nil
    ) async throws -> (SmartMinutes, TokenUsage) {
        let isIncremental = !isFinal && !meeting.minutes.isEmpty && deltaSegmentsOnly != nil && !(deltaSegmentsOnly?.isEmpty ?? true)

        // Long-meeting Map-Reduce when final summary exceeds ~32k characters
        if isFinal {
            let fullTranscript = meeting.transcriptAsText
            if fullTranscript.count > 32_000 {
                return try await generateLongMeetingMapReduce(
                    meeting: meeting,
                    fullTranscript: fullTranscript,
                    settings: settings,
                    onStreamDelta: onStreamDelta
                )
            }
        }

        let modeDescription: String
        if isFinal {
            modeDescription = "会议已结束，请基于完整转写逐字稿与手动笔记，输出一份专业、结构清晰、可直接发送给团队的最终版智能会议纪要。"
        } else if isIncremental {
            modeDescription = "会议正在进行中，请基于【上一版实时纪要】与【最新新增的转写片段】做增量合并：保留此前有效的议题、决议和待办，并补充或修正最新讨论的内容（切勿丢失已有要点）。"
        } else {
            modeDescription = "会议正在进行中，请基于截至目前的转写内容，快速提炼实时的会议纪要要点、已达成的决议、待办事项和待确认问题。"
        }

        let resolvedTemplate = Self.resolveTemplate(for: meeting, settings: settings)
        let customNote = settings.customMinutesPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let customDirective = customNote.isEmpty ? "" : "\n\n用户额外偏好要求：\n\(customNote)"

        let instructions = buildMinutesSystemInstructions(
            modeDescription: modeDescription,
            templateName: resolvedTemplate.name,
            templateGuidance: resolvedTemplate.guidance,
            outputLanguage: settings.minutesOutputLanguage,
            customDirective: customDirective
        )

        var userPrompt = """
        会议来源：\(meeting.sourceAppName)
        纪要模板：\(resolvedTemplate.name)
        当前标题：\(meeting.title)
        已进行时长：\(meeting.formattedDuration)
        """

        if !meeting.calendarAttendees.isEmpty {
            userPrompt += "\n日程参会人参考：\(meeting.calendarAttendees.joined(separator: "、"))"
        }
        let localName = settings.localUserName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !localName.isEmpty {
            userPrompt += "\n本机发言人姓名：\(localName)"
        }

        if !meeting.manualNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            userPrompt += "\n\n【用户会中手动笔记（高优先级）】\n\(meeting.manualNotes)"
        }

        if isIncremental, let deltaSegs = deltaSegmentsOnly {
            userPrompt += "\n\n【上一版实时纪要（请在此基础上增量合并更新）】\n\(Self.encodeCompactMinutesJSON(meeting.minutes))"
            let deltaText = deltaSegs.map { seg in
                "[\(seg.formattedTimestamp)] [\(seg.resolvedSpeakerName)] \(seg.text)"
            }.joined(separator: "\n")
            userPrompt += "\n\n【最新新增转写片段】\n\(deltaText)"
        } else {
            let transcriptText = buildTranscriptPayload(meeting: meeting)
            userPrompt += "\n\n【会议实时转写逐字稿】\n\(transcriptText)"
        }

        let completion = try await completeWithUsage(
            instructions: instructions,
            userPrompt: userPrompt,
            settings: settings,
            onDelta: onStreamDelta
        )

        return (Self.parseSmartMinutes(from: completion.text, isFinal: isFinal), completion.usage)
    }

    /// Two-stage Map-Reduce summarization for 2+ hour meetings (>32k chars) so zero middle context is lost.
    private func generateLongMeetingMapReduce(
        meeting: MeetingSession,
        fullTranscript: String,
        settings: AppSettings,
        onStreamDelta: (@Sendable (String) -> Void)?
    ) async throws -> (SmartMinutes, TokenUsage) {
        let chunks = Self.splitTranscriptIntoChunks(fullTranscript, maxChunkChars: 20_000)
        var accumulatedUsage = TokenUsage()
        var stageSummaries: [String] = []

        let mapInstructions = """
        你是一位专业会议速记员。请将下面这段会议逐字稿分段提炼为高信息密度的结构化要点笔记（保留所有人名、数字、方案名称、达成的决议、待办事项与负责人/截止时间、以及未决风险）。不要遗漏关键事实，用简洁中文 Markdown 列表输出。
        """

        for (index, chunk) in chunks.enumerated() {
            let mapPrompt = "这是整场会议（标题：\(meeting.title)）的第 \(index + 1)/\(chunks.count) 段逐字稿：\n\n\(chunk)"
            let mapResult = try await completeWithUsage(
                instructions: mapInstructions,
                userPrompt: mapPrompt,
                settings: settings,
                onDelta: nil
            )
            accumulatedUsage.add(mapResult.usage)
            stageSummaries.append("### 第 \(index + 1) 段核心纪要\n\(mapResult.text)")
        }

        let resolvedTemplate = Self.resolveTemplate(for: meeting, settings: settings)
        let customNote = settings.customMinutesPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let customDirective = customNote.isEmpty ? "" : "\n\n用户额外偏好要求：\n\(customNote)"
        let reduceInstructions = buildMinutesSystemInstructions(
            modeDescription: "这是一场超长会议的分段汇总结果，请将所有分段纪要与用户手动笔记融合、去重并整理为一份结构统一、逻辑连贯的最终版智能会议纪要。",
            templateName: resolvedTemplate.name,
            templateGuidance: resolvedTemplate.guidance,
            outputLanguage: settings.minutesOutputLanguage,
            customDirective: customDirective
        )

        var reducePrompt = """
        会议来源：\(meeting.sourceAppName)
        纪要模板：\(resolvedTemplate.name)
        当前标题：\(meeting.title)
        总时长：\(meeting.formattedDuration)
        """
        if !meeting.calendarAttendees.isEmpty {
            reducePrompt += "\n日程参会人参考：\(meeting.calendarAttendees.joined(separator: "、"))"
        }
        if !meeting.manualNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            reducePrompt += "\n\n【用户会中手动笔记（高优先级）】\n\(meeting.manualNotes)"
        }
        reducePrompt += "\n\n【全会议分段提炼结果】\n" + stageSummaries.joined(separator: "\n\n")

        let finalResult = try await completeWithUsage(
            instructions: reduceInstructions,
            userPrompt: reducePrompt,
            settings: settings,
            onDelta: onStreamDelta
        )
        accumulatedUsage.add(finalResult.usage)

        return (Self.parseSmartMinutes(from: finalResult.text, isFinal: true), accumulatedUsage)
    }

    public static func resolveTemplate(for meeting: MeetingSession, settings: AppSettings) -> (name: String, guidance: String) {
        if let customID = meeting.customTemplateID,
           let custom = settings.customTemplates.first(where: { $0.id == customID }) {
            return (custom.name, custom.promptGuidance)
        }
        return (meeting.template.displayName, meeting.template.promptGuidance)
    }

    public func buildMinutesSystemInstructions(
        modeDescription: String,
        templateName: String,
        templateGuidance: String,
        outputLanguage: MinutesOutputLanguage = .auto,
        customDirective: String
    ) -> String {
        """
        你是参考「豆包工作智能会议纪要」设计的专业会议记录专家。
        \(modeDescription)

        \(outputLanguage.promptDirective)

        场景模板指引（\(templateName)）：
        \(templateGuidance)

        工作原则：
        1. 去除口语废话、重复与语气词，将零散对话提炼为高信息密度的商务表达。
        2. 严格区分「讨论要点」与「已确认决议」，不要把尚未敲定的想法误写为最终决议。
        3. 精准提取「待办事项 (Action Items)」，尽量标明负责人和截止时间（未提及则填"待定"或空字符串）。
        4. 若有用户的「会中手动笔记」，将其视为高优先级重点融入纪要。
        5. 保留关键数字、项目名、时间节点与专有名词，严禁凭空编造会议中未出现的信息。
        6. 必须且仅返回一个合法的 JSON 对象（不要输出额外解释文字），字段结构严格如下：
        {
          "suggestedTitle": "简明准确的会议主题（10-20字）",
          "overview": "2-3句话高度概括本次会议的背景、核心讨论方向与当前进展",
          "participants": ["发言角色或提及的参会人姓名"],
          "topics": [
            {
              "title": "议题标题",
              "points": ["清晰、完整的核心观点或讨论结论1", "要点2"]
            }
          ],
          "decisions": ["已经明确达成共识的决议1"],
          "actionItems": [
            {
              "task": "具体可执行的任务内容",
              "owner": "责任人（未明确填待定）",
              "dueDate": "截止时间（未明确填具体空字符串）"
            }
          ],
          "openQuestions": ["尚未解决的分歧、风险点或需会后确认的问题"]
        }\(customDirective)
        """
    }

    public static func splitTranscriptIntoChunks(_ text: String, maxChunkChars: Int = 20_000) -> [String] {
        guard text.count > maxChunkChars else { return [text] }
        let lines = text.components(separatedBy: .newlines)
        var chunks: [String] = []
        var current = ""

        for line in lines {
            if !current.isEmpty && (current.count + line.count + 1) > maxChunkChars {
                chunks.append(current)
                current = line
            } else {
                current = current.isEmpty ? line : (current + "\n" + line)
            }
        }
        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks
    }

    public static func encodeCompactMinutesJSON(_ minutes: SmartMinutes) -> String {
        let dict: [String: Any] = [
            "suggestedTitle": minutes.suggestedTitle,
            "overview": minutes.overview,
            "participants": minutes.participants,
            "topics": minutes.topics.map { ["title": $0.title, "points": $0.points] },
            "decisions": minutes.decisions,
            "actionItems": minutes.actionItems.map { ["task": $0.task, "owner": $0.owner, "dueDate": $0.dueDate] },
            "openQuestions": minutes.openQuestions
        ]
        if let data = try? JSONSerialization.data(withJSONObject: dict),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return minutes.overview
    }

    // MARK: - Interactive Meeting Q&A / Downstream Docs

    public func askAboutMeeting(
        meeting: MeetingSession,
        question: String,
        settings: AppSettings,
        onStreamDelta: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        let (reply, _) = try await askAboutMeetingWithUsage(
            meeting: meeting,
            question: question,
            settings: settings,
            onStreamDelta: onStreamDelta
        )
        return reply
    }

    public func askAboutMeetingWithUsage(
        meeting: MeetingSession,
        question: String,
        settings: AppSettings,
        onStreamDelta: (@Sendable (String) -> Void)? = nil
    ) async throws -> (String, TokenUsage) {
        let instructions = """
        你是「Sonote 声记」AI 会议助手（极简高效风格）。
        请严格依据提供的会议逐字稿、当前会议纪要与手动笔记，回答用户的追问或按要求生成衍生工作文档（如会后同步邮件、周报、PRD 大纲、待办拆解等）。
        使用清晰美观的 Markdown 排版；如果会议中未提及某信息，请明确说明，切勿编造。
        """

        let transcript = buildTranscriptPayload(meeting: meeting)
        let summarySnippet = meeting.minutes.isEmpty ? "暂无" : """
        总览：\(meeting.minutes.overview)
        决议：\(meeting.minutes.decisions.joined(separator: "；"))
        待办：\(meeting.minutes.actionItems.map { "\($0.task)（\($0.owner)）" }.joined(separator: "；"))
        """

        var historyBlock = ""
        let recentChat = meeting.chatHistory.suffix(6)
        if !recentChat.isEmpty {
            historyBlock = "\n\n【近期对话上下文】\n" + recentChat.map { msg in
                "\(msg.role == .user ? "用户" : "助手")：\(msg.content)"
            }.joined(separator: "\n")
        }

        let userPrompt = """
        会议标题：\(meeting.title)
        会议来源：\(meeting.sourceAppName)

        【当前智能纪要】
        \(summarySnippet)

        【用户手动笔记】
        \(meeting.manualNotes.isEmpty ? "无" : meeting.manualNotes)

        【会议逐字稿】
        \(transcript)\(historyBlock)

        【用户提问 / 指令】
        \(question)
        """

        let completion = try await completeWithUsage(
            instructions: instructions,
            userPrompt: userPrompt,
            settings: settings,
            onDelta: onStreamDelta
        )
        return (completion.text, completion.usage)
    }

    // MARK: - Cross-Meeting AI Synthesis & Q&A

    /// Answers questions, summarizes progress, or compares blockers across multiple selected meetings.
    public func askAcrossMeetingsWithUsage(
        meetings: [MeetingSession],
        question: String,
        settings: AppSettings,
        onStreamDelta: (@Sendable (String) -> Void)? = nil
    ) async throws -> (String, TokenUsage) {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"

        let sorted = meetings.sorted { $0.startedAt < $1.startedAt }
        var contextBlocks: [String] = []
        let perMeetingBudget = max(1_800, 26_000 / max(1, sorted.count))

        for (idx, m) in sorted.enumerated() {
            var block = "## 会议 \(idx + 1)：\(m.title)（\(df.string(from: m.startedAt)) · \(m.sourceAppName)）"
            if !m.tags.isEmpty {
                block += "\n标签：\(m.tags.map { "#\($0)" }.joined(separator: " "))"
            }
            if !m.minutes.isEmpty {
                if !m.minutes.overview.isEmpty { block += "\n摘要：\(m.minutes.overview)" }
                for topic in m.minutes.topics {
                    block += "\n- \(topic.title)：\(topic.points.joined(separator: "；"))"
                }
                if !m.minutes.decisions.isEmpty {
                    block += "\n决议：\(m.minutes.decisions.joined(separator: "；"))"
                }
                if !m.minutes.actionItems.isEmpty {
                    let todos = m.minutes.actionItems.map { item in
                        "[\(item.isCompleted ? "已完成" : "待完成")] \(item.task)（负责人：\(item.owner)\(item.dueDate.isEmpty ? "" : "，截止：\(item.dueDate)")）"
                    }.joined(separator: "；")
                    block += "\n待办：\(todos)"
                }
                if !m.minutes.openQuestions.isEmpty {
                    block += "\n风险与待确认：\(m.minutes.openQuestions.joined(separator: "；"))"
                }
            } else if !m.segments.isEmpty {
                block += "\n逐字稿节选：\n" + String(m.transcriptAsText.prefix(perMeetingBudget))
            }
            if !m.manualNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                block += "\n手动笔记：\(m.manualNotes)"
            }
            contextBlocks.append(String(block.prefix(perMeetingBudget + 600)))
        }

        let instructions = """
        你是「Sonote 声记」跨会议分析助手。请严格依据用户选中的多场历史会议记录（按时间顺序排列），完成跨会议汇总、进展对比、阻塞项追踪或周报/月报提炼。
        请用结构清晰的 Markdown 输出（善用标题、要点与表格），标明关键信息来自哪场会议与具体负责人，切勿编造会议中未出现的内容。
        """

        let userPrompt = """
        共选中 \(sorted.count) 场会议：

        \(contextBlocks.joined(separator: "\n\n---\n\n"))

        【用户跨会议问题 / 指令】
        \(question)
        """

        let completion = try await completeWithUsage(
            instructions: instructions,
            userPrompt: userPrompt,
            settings: settings,
            onDelta: onStreamDelta
        )
        return (completion.text, completion.usage)
    }

    // MARK: - AI Contextual Speaker Name Inference

    /// Uses conversational clues (self-introductions, turn-taking addresses) + calendar/voiceprint candidate names
    /// to infer real names for generic labels like "发言人 1", "发言人 2".
    public func inferSpeakerNames(
        for meeting: MeetingSession,
        candidateNames: [String],
        settings: AppSettings
    ) async throws -> (mapping: [String: String], usage: TokenUsage) {
        let genericLabels = meeting.distinctSpeakerNames.filter { name in
            name == "发言人" || name.hasPrefix("发言人 ")
        }
        guard !genericLabels.isEmpty else {
            return ([:], TokenUsage())
        }

        let excerpt = meeting.segments.prefix(45).map { seg in
            "[\(seg.formattedTimestamp)] [\(seg.resolvedSpeakerName)] \(seg.text)"
        }.joined(separator: "\n")

        let instructions = """
        你是会议说话人身份分析助手。请根据会议逐字稿中的自我介绍、互相点名与对话承接关系，结合候选参会人名单，推断通用标签（如「发言人 1」「发言人 2」）对应的真实姓名。
        必须严格遵守：
        1. 仅输出纯 JSON，不要输出任何额外说明或 Markdown 代码块，格式为：
           {"mappings": {"发言人 1": "真实姓名"}}
        2. 只有在对话内容中有较明确线索时才写入 mappings；无法确定时宁可省略，切勿胡乱猜测。
        """

        var prompt = """
        待识别的通用说话人标签：\(genericLabels.joined(separator: "、"))
        """
        let cleanCandidates = Array(Set(candidateNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
        if !cleanCandidates.isEmpty {
            prompt += "\n已知候选参会人 / 团队成员名单：\(cleanCandidates.joined(separator: "、"))"
        }
        prompt += "\n\n【会议逐字稿节选】\n\(excerpt)"

        let result = try await completeWithUsage(
            instructions: instructions,
            userPrompt: prompt,
            settings: settings
        )
        let parsed = Self.parseSpeakerNameMapping(from: result.text)
            .filter { key, val in
                genericLabels.contains(key) && !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && val != key
            }
        return (parsed, result.usage)
    }

    public static func parseSpeakerNameMapping(from raw: String) -> [String: String] {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = cleaned.firstIndex(of: "{"), let end = cleaned.lastIndex(of: "}") {
            cleaned = String(cleaned[start...end])
        }
        guard let data = cleaned.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        if let mappings = obj["mappings"] as? [String: String] {
            return mappings
        }
        var flat: [String: String] = [:]
        for (k, v) in obj {
            if let s = v as? String {
                flat[k] = s
            }
        }
        return flat
    }

    // MARK: - OpenAI Audio Transcription API

    public func transcribeAudioWAV(
        wavData: Data,
        language: TranscriptionLanguage,
        settings: AppSettings
    ) async throws -> String {
        let credential = try authManager.resolveCredential(settings: settings)
        guard case .openAIAPIKey(let apiKey, let baseURL, _, _, let providerLabel) = credential,
              providerLabel == nil else {
            throw GPTClientError.audioTranscriptionRequiresAPIKey
        }

        guard let url = URL(string: "\(baseURL)/audio/transcriptions") else {
            throw GPTClientError.invalidEndpoint("\(baseURL)/audio/transcriptions")
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 45

        var body = Data()
        func appendField(name: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        appendField(name: "model", value: settings.openAITranscribeModel.isEmpty ? "gpt-4o-mini-transcribe" : settings.openAITranscribeModel)
        appendField(name: "language", value: language.iso639Code)
        appendField(name: "response_format", value: "json")

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"chunk.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wavData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GPTClientError.emptyResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let errText = String(data: data, encoding: .utf8) ?? ""
            throw GPTClientError.httpError(http.statusCode, String(errText.prefix(260)))
        }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = json["text"] as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // MARK: - Core Completion Router

    public func complete(
        instructions: String,
        userPrompt: String,
        settings: AppSettings,
        onDelta: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        try await completeWithUsage(
            instructions: instructions,
            userPrompt: userPrompt,
            settings: settings,
            onDelta: onDelta
        ).text
    }

    public func completeWithUsage(
        instructions: String,
        userPrompt: String,
        settings: AppSettings,
        onDelta: (@Sendable (String) -> Void)? = nil
    ) async throws -> GPTCompletionResult {
        let credential = try authManager.resolveCredential(settings: settings)
        switch credential {
        case .openAIAPIKey(let apiKey, let baseURL, _, let modelOverride, _):
            let rawModel = (modelOverride ?? settings.model).trimmingCharacters(in: .whitespacesAndNewlines)
            let chosen = rawModel.isEmpty ? "gpt-5.4" : rawModel
            do {
                return try await callOpenAIChatCompletions(
                    apiKey: apiKey,
                    baseURL: baseURL,
                    model: chosen,
                    instructions: instructions,
                    userPrompt: userPrompt,
                    includeStreamUsage: true,
                    onDelta: onDelta
                )
            } catch GPTClientError.httpError(let code, let detail)
                where (code == 400 || code == 422)
                    && (detail.localizedCaseInsensitiveContains("stream_options")
                        || detail.localizedCaseInsensitiveContains("include_usage")
                        || detail.localizedCaseInsensitiveContains("unknown")
                        || detail.localizedCaseInsensitiveContains("unrecognized")) {
                return try await callOpenAIChatCompletions(
                    apiKey: apiKey,
                    baseURL: baseURL,
                    model: chosen,
                    instructions: instructions,
                    userPrompt: userPrompt,
                    includeStreamUsage: false,
                    onDelta: onDelta
                )
            }

        case .codexOAuth(let oauth):
            let chosenModel = resolveCodexModel(settings: settings, authFilePath: oauth.authFilePath)
            do {
                return try await callCodexResponses(
                    oauth: oauth,
                    model: chosenModel,
                    instructions: instructions,
                    userPrompt: userPrompt,
                    onDelta: onDelta
                )
            } catch GPTClientError.httpError(401, _) {
                let refreshed = try await authManager.refreshCodexOAuth(oauth)
                return try await callCodexResponses(
                    oauth: refreshed,
                    model: chosenModel,
                    instructions: instructions,
                    userPrompt: userPrompt,
                    onDelta: onDelta
                )
            }

        case .anthropicAPIKey(let apiKey, let baseURL, _):
            let chosen = settings.claudeModel.trimmingCharacters(in: .whitespacesAndNewlines)
            return try await callAnthropicMessages(
                apiKey: apiKey,
                baseURL: baseURL,
                model: chosen.isEmpty ? "claude-sonnet-4-5" : chosen,
                instructions: instructions,
                userPrompt: userPrompt,
                onDelta: onDelta
            )

        case .geminiAPIKey(let apiKey, let baseURL, _):
            let chosen = settings.geminiModel.trimmingCharacters(in: .whitespacesAndNewlines)
            return try await callGoogleGemini(
                apiKey: apiKey,
                baseURL: baseURL,
                model: chosen.isEmpty ? "gemini-2.5-flash" : chosen,
                instructions: instructions,
                userPrompt: userPrompt,
                onDelta: onDelta
            )

        case .localMLX(let modelID):
            return try await LocalMLXLLMEngine.shared.complete(
                instructions: instructions,
                userPrompt: userPrompt,
                modelID: modelID,
                hfHost: settings.mlxHuggingFaceHost,
                onDelta: onDelta
            )
        }
    }

    public func resolveCodexModel(settings: AppSettings, authFilePath: String) -> String {
        let configured = settings.codexModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let catalog = authManager.discoverLocalCodexCatalog(authFilePath: authFilePath)
        if !configured.isEmpty {
            // If user hasn't picked a custom catalog model and the saved value isn't in the local Codex catalog, prefer local default
            if !catalog.availableModels.isEmpty && !catalog.availableModels.contains(configured) && configured == "gpt-5.4" {
                return catalog.defaultModel ?? catalog.availableModels.first ?? configured
            }
            return configured
        }
        return catalog.defaultModel ?? catalog.availableModels.first ?? "gpt-5.3-codex"
    }

    private func activeModel(for credential: ResolvedCredential, settings: AppSettings) -> String {
        switch credential {
        case .openAIAPIKey(_, _, _, let modelOverride, _):
            let m = (modelOverride ?? settings.model).trimmingCharacters(in: .whitespacesAndNewlines)
            return m.isEmpty ? "gpt-5.4" : m
        case .codexOAuth(let oauth):
            return resolveCodexModel(settings: settings, authFilePath: oauth.authFilePath)
        case .anthropicAPIKey:
            return settings.claudeModel.isEmpty ? "claude-sonnet-4-5" : settings.claudeModel
        case .geminiAPIKey:
            return settings.geminiModel.isEmpty ? "gemini-2.5-flash" : settings.geminiModel
        case .localMLX(let modelID):
            return modelID
        }
    }
}
