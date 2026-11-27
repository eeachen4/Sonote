import XCTest
import Speech
import AVFoundation
import MLXAudioVAD
import SonoteCore

final class SonoteTests: XCTestCase {

    // MARK: - AuthManager Tests

    func testParseCodexOAuthAuthJSON() throws {
        // Construct a mock JWT payload {"email":"demo@example.com","exp":2000000000,"https://api.openai.com/auth":{"chatgpt_plan_type":"plus","chatgpt_account_id":"acc-123"}}
        let payloadJSON = #"{"email":"demo@example.com","exp":2000000000,"https://api.openai.com/auth":{"chatgpt_plan_type":"plus","chatgpt_account_id":"acc-123"}}"#
        let encodedPayload = Data(payloadJSON.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let fakeJWT = "eyJhbGciOiJSUzI1NiJ9.\(encodedPayload).signature"

        let authJSON = """
        {
          "auth_mode": "chatgpt",
          "OPENAI_API_KEY": null,
          "tokens": {
            "id_token": "\(fakeJWT)",
            "access_token": "\(fakeJWT)",
            "refresh_token": "rt_dummy_token",
            "account_id": "acc-123",
            "oauth_provenance": {
              "issuer": "https://auth.openai.com",
              "client_id": "app_custom_client"
            }
          },
          "last_refresh": "2026-11-27T04:00:00Z"
        }
        """

        let cred = try AuthManager.shared.parseAuthData(Data(authJSON.utf8), filePath: "/tmp/auth.json")
        guard case .codexOAuth(let oauth) = cred else {
            return XCTFail("Expected codexOAuth credential")
        }
        XCTAssertEqual(oauth.accountID, "acc-123")
        XCTAssertEqual(oauth.clientID, "app_custom_client")
        XCTAssertEqual(oauth.email, "demo@example.com")
        XCTAssertEqual(oauth.planType, "plus")
        XCTAssertFalse(oauth.isExpired)
    }

    func testParseAPIKeyFromJSONAndEnv() throws {
        let jsonStr = #"{"OPENAI_API_KEY": "sk-test-1234567890abcdef123456", "OPENAI_BASE_URL": "https://proxy.example.com/v1/"}"#
        let cred1 = try AuthManager.shared.parseAuthData(Data(jsonStr.utf8), filePath: "/tmp/openai.json")
        guard case .openAIAPIKey(let key1, let baseURL1, _, _, _) = cred1 else {
            return XCTFail("Expected openAIAPIKey")
        }
        XCTAssertEqual(key1, "sk-test-1234567890abcdef123456")
        XCTAssertEqual(baseURL1, "https://proxy.example.com/v1")

        let envStr = """
        # OpenAI config
        export OPENAI_API_KEY="sk-env-9876543210fedcba987654"
        """
        let cred2 = try AuthManager.shared.parseAuthData(Data(envStr.utf8), filePath: "/tmp/.env")
        guard case .openAIAPIKey(let key2, _, _, _, _) = cred2 else {
            return XCTFail("Expected openAIAPIKey from .env")
        }
        XCTAssertEqual(key2, "sk-env-9876543210fedcba987654")
    }

    // MARK: - GPTClient Parser Tests

    func testCodexAndChatCompletionsSSEParsing() {
        let deltaLine = #"{"type":"response.output_text.delta","delta":"你好"}"#
        let event1 = GPTClient.parseCodexSSEDataLine(deltaLine)
        XCTAssertEqual(event1.delta, "你好")

        let completedLine = #"{"type":"response.completed","response":{"output":[{"content":[{"type":"output_text","text":"完整结果"}]}],"usage":{"input_tokens":1250,"output_tokens":340,"total_tokens":1590,"input_tokens_details":{"cached_tokens":512},"output_tokens_details":{"reasoning_tokens":80}}}}"#
        let event2 = GPTClient.parseCodexSSEDataLine(completedLine)
        XCTAssertEqual(event2.completedText, "完整结果")
        XCTAssertEqual(event2.usage?.inputTokens, 1250)
        XCTAssertEqual(event2.usage?.outputTokens, 340)
        XCTAssertEqual(event2.usage?.cachedTokens, 512)
        XCTAssertEqual(event2.usage?.reasoningTokens, 80)
        XCTAssertEqual(event2.usage?.formattedCompact, "1.6k")

        let errorLine = #"{"type":"error","error":{"message":"invalid model"}}"#
        let event3 = GPTClient.parseCodexSSEDataLine(errorLine)
        XCTAssertEqual(event3.errorMessage, "invalid model")

        let chatLine = #"{"choices":[{"delta":{"content":"会议要点"}}],"usage":{"prompt_tokens":420,"completion_tokens":180,"total_tokens":600}}"#
        let chatChunk = GPTClient.parseChatCompletionsSSEChunk(chatLine)
        XCTAssertEqual(chatChunk.delta, "会议要点")
        XCTAssertEqual(chatChunk.usage?.totalTokens, 600)
        XCTAssertEqual(chatChunk.usage?.formattedCompact, "600")
        XCTAssertEqual(GPTClient.parseChatCompletionsSSEDataLine(chatLine), "会议要点")
    }

    func testParseSmartMinutesJSONWithCodeFence() {
        let raw = """
        ```json
        {
          "suggestedTitle": "产品迭代周会",
          "overview": "明确了 Q4 发布排期与接口负责分工。",
          "participants": ["张三", "李四"],
          "topics": [
            {"title": "接口排期", "points": ["周五完成联调", "下周一提测"]}
          ],
          "decisions": ["统一采用 Swift 原生方案"],
          "actionItems": [
            {"task": "提交接口文档", "owner": "张三", "dueDate": "周四"}
          ],
          "openQuestions": ["是否需要支持英文双语字幕？"]
        }
        ```
        """
        let minutes = GPTClient.parseSmartMinutes(from: raw, isFinal: true)
        XCTAssertEqual(minutes.suggestedTitle, "产品迭代周会")
        XCTAssertEqual(minutes.topics.count, 1)
        XCTAssertEqual(minutes.topics.first?.points.count, 2)
        XCTAssertEqual(minutes.decisions, ["统一采用 Swift 原生方案"])
        XCTAssertEqual(minutes.actionItems.first?.owner, "张三")
        XCTAssertEqual(minutes.actionItems.first?.dueDate, "周四")
        XCTAssertTrue(minutes.isFinalized)
        XCTAssertNil(minutes.rawMarkdownFallback)
    }

    // MARK: - MeetingDetector Classification Tests

    func testMeetingDetectorClassifiesTencentAndChromeHelperAndMutedZoom() {
        let settings = AppSettings()

        // 1. Tencent Meeting actively using mic
        let tencent = [
            AudioProcessSnapshot(pid: 101, bundleID: "com.tencent.meeting", appName: "腾讯会议", isRunningInput: true, isRunningOutput: true)
        ]
        let detected1 = MeetingDetector.classifyActiveMeeting(processes: tencent, settings: settings, sustainedOutputDurations: [:])
        XCTAssertEqual(detected1?.appName, "腾讯会议")
        XCTAssertEqual(detected1?.isUsingMicrophone, true)

        // 2. Chrome Helper renderer using mic (e.g. Google Meet / Feishu Web)
        let chromeHelper = [
            AudioProcessSnapshot(pid: 202, bundleID: "com.google.Chrome.helper.renderer", appName: "Google Chrome Helper", isRunningInput: true, isRunningOutput: false)
        ]
        let detected2 = MeetingDetector.classifyActiveMeeting(processes: chromeHelper, settings: settings, sustainedOutputDurations: [:])
        XCTAssertEqual(detected2?.bundleIdentifier, "com.google.Chrome")
        XCTAssertEqual(detected2?.appName, "Chrome 网页会议")

        // 3. Muted user listening in Zoom for >= 4s
        let zoomMuted = [
            AudioProcessSnapshot(pid: 303, bundleID: "us.zoom.xos", appName: "zoom.us", isRunningInput: false, isRunningOutput: true)
        ]
        XCTAssertNil(MeetingDetector.classifyActiveMeeting(processes: zoomMuted, settings: settings, sustainedOutputDurations: ["us.zoom.xos": 2.0]))
        let detected3 = MeetingDetector.classifyActiveMeeting(processes: zoomMuted, settings: settings, sustainedOutputDurations: ["us.zoom.xos": 5.0])
        XCTAssertEqual(detected3?.appName, "Zoom")

        // 4. Chrome merely playing YouTube music (output only, no mic) should NOT trigger meeting prompt
        let youtube = [
            AudioProcessSnapshot(pid: 404, bundleID: "com.google.Chrome.helper", appName: "Chrome", isRunningInput: false, isRunningOutput: true)
        ]
        XCTAssertNil(MeetingDetector.classifyActiveMeeting(processes: youtube, settings: settings, sustainedOutputDurations: ["com.google.Chrome": 60.0]))
    }

    // MARK: - MeetingStore & WAVEncoder Tests

    func testMeetingStorePersistenceAndMarkdownExport() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("SonoteTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = MeetingStore(baseDirectory: tempDir)
        let session = MeetingSession(
            title: "技术架构评审",
            sourceAppName: "飞书",
            duration: 325,
            status: .completed,
            segments: [
                TranscriptSegment(timestamp: 15, speaker: .remote, text: "系统声音采集采用 Process Tap 方案。"),
                TranscriptSegment(timestamp: 42, speaker: .me, text: "好的，我来负责落地并补齐单元测试。", isStarred: true)
            ],
            minutes: SmartMinutes(
                overview: "确定使用 CoreAudio Process Tap。",
                topics: [TopicSection(title: "音频方案", points: ["支持双轨采集"])],
                decisions: ["采用 Process Tap"],
                actionItems: [ActionItem(task: "实现音频模块", owner: "我", dueDate: "明天")]
            )
        )

        store.saveMeeting(session)
        let loaded = store.loadMeetings()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.title, "技术架构评审")

        let md = MeetingStore.exportMarkdown(for: session)
        XCTAssertTrue(md.contains("# 技术架构评审"))
        XCTAssertTrue(md.contains("实现音频模块"))
        XCTAssertTrue(md.contains("⭐ 好的，我来负责落地并补齐单元测试。"))
    }

    func testWAVEncoderProducesValidRIFFHeader() {
        let samples = Array(repeating: Float(0.25), count: 1600) // 0.1s at 16kHz
        let wav = WAVEncoder.encodeMono16kWAV(samples: samples, sampleRate: 16_000)
        XCTAssertEqual(wav.count, 44 + 1600 * 2)
        XCTAssertEqual(String(data: wav.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: wav.subdata(in: 8..<12), encoding: .ascii), "WAVE")
    }

    func testMLXQwen3CleanTranscriptAndSettingsMigration() throws {
        XCTAssertEqual(MLXQwen3ASREngine.cleanTranscriptText("  <asr_text> 今天我们 review 一下 API  "), "今天我们 review 一下 API")
        XCTAssertEqual(MLXQwen3ASREngine.cleanTranscriptText("   ...  "), "")

        // Ensure legacy settings.json without MLX keys decodes cleanly with MLX defaults
        let legacyJSON = #"{"authMode":"localAuthFile","authFilePath":"~/.codex/auth.json","model":"gpt-5.4"}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(decoded.transcriptionEngine, .mlxQwen3ASR)
        XCTAssertEqual(decoded.mlxQwen3ModelID, "mlx-community/Qwen3-ASR-1.7B-8bit")
        XCTAssertTrue(decoded.mlxAutoUnloadAfterMeeting)
    }

    func testMarkdownParserHandlesHeadingsListsTablesAndCode() {
        let md = """
        ## 本周周报 | 现有参数复用与回退验证

        ### 本周进展
        - **埋点与参数**：方案以复用现有埋点为主
        - [x] 已明确启动条件

        ### 后续计划
        | 待办 | 负责人 |
        |---|---|
        | 同步问题到群里 | 我 |
        | 确认全量时间 | 待定 |

        > 风险提示：需关注排期

        ```swift
        print("hello")
        ```
        """
        let blocks = MarkdownParser.parse(md)
        XCTAssertEqual(blocks.count, 7)
        XCTAssertEqual(blocks[0], .heading(level: 2, text: "本周周报 | 现有参数复用与回退验证"))
        XCTAssertEqual(blocks[1], .heading(level: 3, text: "本周进展"))
        if case .bulletList(let items) = blocks[2] {
            XCTAssertEqual(items.count, 2)
            XCTAssertNil(items[0].isChecked)
            XCTAssertEqual(items[1].isChecked, true)
        } else {
            XCTFail("Expected bulletList")
        }
        XCTAssertEqual(blocks[3], .heading(level: 3, text: "后续计划"))
        if case .table(let headers, let rows) = blocks[4] {
            XCTAssertEqual(headers, ["待办", "负责人"])
            XCTAssertEqual(rows.count, 2)
            XCTAssertEqual(rows[0], ["同步问题到群里", "我"])
        } else {
            XCTFail("Expected GFM table")
        }
        XCTAssertEqual(blocks[5], .blockquote("风险提示：需关注排期"))
        XCTAssertEqual(blocks[6], .codeBlock(language: "swift", code: "print(\"hello\")"))

        // CJK punctuation adjacent to bold/italic/strike delimiters (CommonMark flanking regression)
        let cjk1 = MarkdownParser.parseInline("**云端编译：**云端环境引发的代码编译问题由林致远跟进。")
        XCTAssertEqual(cjk1, [
            MarkdownInlineSpan(text: "云端编译：", style: .bold),
            MarkdownInlineSpan(text: "云端环境引发的代码编译问题由林致远跟进。", style: [])
        ])

        let cjk2 = MarkdownParser.parseInline("**Agent 辅助审查，研发负责复核：**不能仅凭 `Agent` 的结论判定通过。")
        XCTAssertEqual(cjk2, [
            MarkdownInlineSpan(text: "Agent 辅助审查，研发负责复核：", style: .bold),
            MarkdownInlineSpan(text: "不能仅凭 ", style: []),
            MarkdownInlineSpan(text: "Agent", style: .code),
            MarkdownInlineSpan(text: " 的结论判定通过。", style: [])
        ])

        let cjk3 = MarkdownParser.parseInline("正文**（重要）**测试与~~旧方案：~~新方案，以及 foo_bar_baz 和 2 * 3 * 4")
        XCTAssertEqual(cjk3, [
            MarkdownInlineSpan(text: "正文", style: []),
            MarkdownInlineSpan(text: "（重要）", style: .bold),
            MarkdownInlineSpan(text: "测试与", style: []),
            MarkdownInlineSpan(text: "旧方案：", style: .strikethrough),
            MarkdownInlineSpan(text: "新方案，以及 foo_bar_baz 和 2 * 3 * 4", style: [])
        ])

        let linkSpans = MarkdownParser.parseInline("查看 [飞书文档](https://open.feishu.cn) 或 https://example.com/a，详见说明<br>第二行")
        XCTAssertTrue(linkSpans.contains(MarkdownInlineSpan(text: "飞书文档", style: [], linkURL: "https://open.feishu.cn")))
        XCTAssertTrue(linkSpans.contains(MarkdownInlineSpan(text: "https://example.com/a", style: [], linkURL: "https://example.com/a")))
        XCTAssertTrue(linkSpans.last?.text.contains("\n第二行") == true)

        // Unclosed streaming bold must not drop text
        let streaming = MarkdownParser.parseInline("**正在流式生成中")
        XCTAssertEqual(streaming, [MarkdownInlineSpan(text: "**正在流式生成中", style: [])])
    }

    func testP0P1P2MixerEchoDedupBlacklistMermaidMapReduceAndDiarization() {
        // 1. DualChannelAudioMixer blends system + mic smoothly without clipping
        let mixer = DualChannelAudioMixer()
        mixer.configure(systemActive: true, micActive: true)
        mixer.pushSystem([0.5, 0.5, 0.5, 0.5])
        mixer.pushMic([0.5, -0.5, 0.9, 0.0])
        let mixed = mixer.drainMixed(flushAll: true)
        XCTAssertEqual(mixed.count, 4)
        XCTAssertTrue(mixed.allSatisfy { abs($0) <= 1.0 })
        XCTAssertLessThan(abs(mixed[1]), 0.01) // 0.5 + (-0.5) cancels out

        // 2. EchoDeduplicator drops loudspeaker bleed across channels within 4.5s window
        let dedup = EchoDeduplicator()
        let remoteSeg = TranscriptSegment(timestamp: 10.0, speaker: .remote, text: "我们今天下午五点前完成联调并提交测试报告。")
        let micEchoSeg = TranscriptSegment(timestamp: 11.2, speaker: .me, text: "我们今天下午五点前完成联调并提交测试报告")
        let micRealSeg = TranscriptSegment(timestamp: 13.0, speaker: .me, text: "好的收到，我这边接口已经准备好了。")
        XCTAssertFalse(dedup.shouldDropAsEcho(remoteSeg))
        XCTAssertTrue(dedup.shouldDropAsEcho(micEchoSeg))
        XCTAssertFalse(dedup.shouldDropAsEcho(micRealSeg))

        // 3. MeetingDetector ignores blacklisted apps (like Doubao Work itself)
        let settings = AppSettings()
        let doubaoProc = [
            AudioProcessSnapshot(pid: 888, bundleID: "com.work.pc.doubao.browser.helper", appName: "DoubaoWork", isRunningInput: true, isRunningOutput: true)
        ]
        XCTAssertNil(MeetingDetector.classifyActiveMeeting(processes: doubaoProc, settings: settings, sustainedOutputDurations: [:]))

        // 4. Long-meeting Map-Reduce chunk splitter & Mermaid mindmap export
        let longText = Array(repeating: "[00:01] [我] 这是一行较长的会议转写测试文本用于验证切分逻辑。", count: 600).joined(separator: "\n")
        let chunks = GPTClient.splitTranscriptIntoChunks(longText, maxChunkChars: 5_000)
        XCTAssertGreaterThan(chunks.count, 3)

        let session = MeetingSession(
            title: "架构评审",
            minutes: SmartMinutes(
                overview: "采用 MLX 本地转写。",
                topics: [TopicSection(title: "音频链路", points: ["双轨混音", "Silero VAD"])],
                decisions: ["上线 v1.1"],
                actionItems: [ActionItem(task: "回归测试", owner: "我", dueDate: "明天")]
            )
        )
        let mermaid = MeetingStore.exportMermaidMindMap(for: session)
        XCTAssertTrue(mermaid.contains("```mermaid"))
        XCTAssertTrue(mermaid.contains("mindmap"))
        XCTAssertTrue(mermaid.contains("Silero VAD"))

        // 5. SpeakerDiarizerService maps speakers cleanly while keeping local "我"
        let segs = [
            TranscriptSegment(timestamp: 2.0, speaker: .me, text: "我先同步一下进度"),
            TranscriptSegment(timestamp: 6.0, speaker: .remote, text: "好的请说"),
            TranscriptSegment(timestamp: 12.0, speaker: .remote, text: "我补充一个风险点")
        ]
        let diar = [
            DiarizationSegment(start: 5.0, end: 8.5, speaker: 2),
            DiarizationSegment(start: 11.0, end: 15.0, speaker: 0)
        ]
        let assigned = SpeakerDiarizerService.assignSpeakerLabels(segments: segs, diarization: diar)
        XCTAssertEqual(assigned[0].resolvedSpeakerName, "我")
        XCTAssertEqual(assigned[1].resolvedSpeakerName, "发言人 1")
        XCTAssertEqual(assigned[2].resolvedSpeakerName, "发言人 2")
    }

    func testV12StreamingVADFullTextSearchTokenLedgerAndAudioStoragePruning() async throws {
        // 1. StreamingVADEndpointMachine hysteresis, pre-roll & silence endpointing
        var vadMachine = StreamingVADEndpointMachine(
            sampleRate: 16_000,
            speechStartThreshold: 0.48,
            speechContinueThreshold: 0.30,
            preRollLimit: 1024,
            minCommitSamples: 2048,
            maxCommitSamples: 8192,
            silenceEndpointSamples: 1024,
            previewStrideSamples: 4096,
            minPreviewSamples: 4096
        )
        let silenceFrame = [Float](repeating: 0.0, count: 512)
        let speechFrame = [Float](repeating: 0.2, count: 512)

        // Pre-roll 2 frames of silence
        XCTAssertEqual(vadMachine.ingest(frame: silenceFrame, speechProbability: 0.1), .none)
        XCTAssertEqual(vadMachine.ingest(frame: silenceFrame, speechProbability: 0.1), .none)
        XCTAssertFalse(vadMachine.isInSpeech)

        // Trigger speech start at 0.55, then continue at 0.35 (between 0.30 and 0.48 -> hysteresis stays active!)
        XCTAssertEqual(vadMachine.ingest(frame: speechFrame, speechProbability: 0.55), .none)
        XCTAssertTrue(vadMachine.isInSpeech)
        XCTAssertEqual(vadMachine.ingest(frame: speechFrame, speechProbability: 0.35), .none)
        XCTAssertTrue(vadMachine.isInSpeech)
        XCTAssertEqual(vadMachine.ingest(frame: speechFrame, speechProbability: 0.40), .none)

        // 2 frames of silence (1024 samples) should commit (including 1024 pre-roll + 1536 speech + 1024 trailing = 3584 samples)
        XCTAssertEqual(vadMachine.ingest(frame: silenceFrame, speechProbability: 0.05), .none)
        if case .commit(let committed) = vadMachine.ingest(frame: silenceFrame, speechProbability: 0.05) {
            XCTAssertEqual(committed.count, 3584)
            XCTAssertFalse(vadMachine.isInSpeech)
        } else {
            XCTFail("Expected StreamingVADEndpointMachine to commit utterance on silence break")
        }

        // 2. Full-text transcript + action item + manual notes search & contextual snippet
        let searchable = MeetingSession(
            title: "周会同步",
            sourceAppName: "飞书",
            segments: [
                TranscriptSegment(timestamp: 84, speaker: .remote, text: "这次我们重点验证登录合一方案的灰度回滚策略。")
            ],
            manualNotes: "记得拉运维同学评审 Redis 扩容",
            minutes: SmartMinutes(
                overview: "同步本周研发进度。",
                actionItems: [ActionItem(task: "补齐压力测试报告", owner: "王明")]
            )
        )
        XCTAssertTrue(searchable.matchesSearchQuery("灰度回滚"))
        XCTAssertTrue(searchable.searchSnippet(for: "灰度回滚")?.contains("逐字稿 01:24") == true)
        XCTAssertTrue(searchable.matchesSearchQuery("王明"))
        XCTAssertTrue(searchable.searchSnippet(for: "王明")?.contains("待办") == true)
        XCTAssertTrue(searchable.matchesSearchQuery("Redis"))
        XCTAssertTrue(searchable.searchSnippet(for: "Redis")?.contains("随手记") == true)
        XCTAssertFalse(searchable.matchesSearchQuery("完全不存在的关键词XYZ"))

        // 3. Daily token ledger accurately attributes today's GPT calls even on yesterday's meeting
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("SonoteTests-v12-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let store = MeetingStore(baseDirectory: tempDir)

        let now = Date()
        let yesterday = now.addingTimeInterval(-86_400)
        let oldMeeting = MeetingSession(
            title: "昨天的评审",
            startedAt: yesterday,
            endedAt: yesterday.addingTimeInterval(600),
            status: .completed,
            tokenUsage: TokenUsage(inputTokens: 400, outputTokens: 200, requestCount: 1)
        )
        let seeded = store.loadTokenLedger(seedFrom: [oldMeeting])
        XCTAssertEqual(seeded[MeetingStore.dayKey(for: yesterday)]?.totalTokens, 600)
        XCTAssertNil(seeded[MeetingStore.dayKey(for: now)])

        // Asking AI today on yesterday's meeting records under today's key
        let updatedLedger = store.recordTokenUsage(TokenUsage(inputTokens: 300, outputTokens: 150, requestCount: 1), on: now)
        XCTAssertEqual(updatedLedger[MeetingStore.dayKey(for: now)]?.totalTokens, 450)
        XCTAssertEqual(updatedLedger[MeetingStore.dayKey(for: yesterday)]?.totalTokens, 600)

        // 4. Audio backup M4A round-trip + storage stats + age-based pruning (preserving active recording & text minutes)
        let oldAudioURL = store.audioBackupURL(for: oldMeeting.id)
        let sineSamples = (0..<8_000).map { Float(sin(Double($0) * 0.1)) * 0.2 }
        try AudioFileImporter.writeMono16kSamplesToM4A(samples: sineSamples, destinationURL: oldAudioURL)
        let (decodedSamples, decodedDur) = try await AudioFileImporter.decodeToMono16kSamples(url: oldAudioURL)
        XCTAssertGreaterThan(decodedSamples.count, 4_000)
        XCTAssertGreaterThan(decodedDur, 0.3)

        let activeMeeting = MeetingSession(
            title: "正在进行的会议",
            startedAt: now,
            status: .recording,
            audioFilePath: store.audioBackupURL(for: UUID()).path
        )
        let activeAudioURL = URL(fileURLWithPath: activeMeeting.audioFilePath!)
        try AudioFileImporter.writeMono16kSamplesToM4A(samples: sineSamples, destinationURL: activeAudioURL)

        var oldMeetingWithAudio = oldMeeting
        oldMeetingWithAudio.startedAt = now.addingTimeInterval(-40 * 86_400)
        oldMeetingWithAudio.endedAt = now.addingTimeInterval(-40 * 86_400)
        oldMeetingWithAudio.audioFilePath = oldAudioURL.path

        let orphanURL = store.audioDirectory.appendingPathComponent("orphan-temp.m4a")
        try Data(repeating: 0xAA, count: 2048).write(to: orphanURL)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-40 * 86_400)], ofItemAtPath: orphanURL.path)

        let statsBefore = store.audioStorageStats()
        XCTAssertEqual(statsBefore.fileCount, 3)
        XCTAssertGreaterThan(statsBefore.totalBytes, 2048)

        var list = [activeMeeting, oldMeetingWithAudio]
        let pruned = store.pruneAudioBackups(olderThanDays: 30, activeMeetingID: activeMeeting.id, meetings: &list, now: now)
        XCTAssertEqual(pruned.removedFiles, 2) // old meeting audio + old orphan file
        XCTAssertNil(list[1].audioFilePath)    // old meeting audio cleared, text preserved
        XCTAssertEqual(list[1].title, "昨天的评审")
        XCTAssertNotNil(list[0].audioFilePath) // active recording audio untouched
        XCTAssertTrue(FileManager.default.fileExists(atPath: activeAudioURL.path))
        XCTAssertEqual(store.audioStorageStats().fileCount, 1)
    }

    func testV13VoiceprintMathStoreDenoiserRenameAINamingAndRichTextHTML() throws {
        // 1. VoiceprintMath L2 norm, cosine similarity, running average merge & bestMatch
        let vA = VoiceprintMath.l2Normalize([1, 0, 0, 0])
        let vB = VoiceprintMath.l2Normalize([0, 1, 0, 0])
        let vANoisy = VoiceprintMath.l2Normalize([0.92, 0.25, 0.1, 0.0])
        XCTAssertEqual(VoiceprintMath.cosineSimilarity(vA, vA), 1.0, accuracy: 0.001)
        XCTAssertEqual(VoiceprintMath.cosineSimilarity(vA, vB), 0.0, accuracy: 0.001)
        XCTAssertGreaterThan(VoiceprintMath.cosineSimilarity(vA, vANoisy), 0.9)

        let merged = VoiceprintMath.mergeEmbeddings(existing: vA, existingCount: 2, incoming: vANoisy)
        XCTAssertGreaterThan(VoiceprintMath.cosineSimilarity(merged, vA), 0.98)

        // 2. VoiceprintStore persistent upsert, merge, rename & delete
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("SonoteTests-v13-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let vpStore = VoiceprintStore(baseDirectory: tempDir)

        var profiles = vpStore.upsertProfile(name: "林致远", role: "研发", embedding: vA)
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles[0].sampleCount, 1)

        // Upserting same speaker merges embeddings and increments sampleCount
        profiles = vpStore.upsertProfile(name: "林致远", embedding: vANoisy)
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles[0].sampleCount, 2)

        profiles = vpStore.upsertProfile(name: "陈晨", role: "本人", embedding: vB, isSelf: true)
        XCTAssertEqual(profiles.count, 2)
        XCTAssertEqual(profiles.first?.name, "陈晨") // isSelf sorted first

        let match = VoiceprintMath.bestMatch(for: vANoisy, in: profiles, threshold: 0.56)
        XCTAssertEqual(match?.profile.name, "林致远")
        XCTAssertGreaterThan(match?.similarity ?? 0, 0.9)

        let renamed = vpStore.renameProfile(id: profiles[1].id, newName: "致远")
        XCTAssertTrue(renamed.contains(where: { $0.name == "致远" }))

        // 3. Extract speaker audio intervals cleanly
        let fullAudio = [Float](repeating: 0.25, count: 16_000 * 10)
        let sliced = VoiceprintService.extractSpeakerSamples(
            from: fullAudio,
            intervals: [(start: 1.0, end: 3.5), (start: 5.0, end: 8.0)],
            maxDurationSeconds: 4.0
        )
        XCTAssertEqual(sliced.count, 16_000 * 4)

        // 4. Resampling 16k -> 48k -> 16k + lightweight DSP denoiser preserves speech signal length
        let speech16k = (0..<16_000).map { i -> Float in
            // 440 Hz tone (speech band) + 30 Hz low-frequency rumble
            sin(2.0 * Float.pi * 440.0 * Float(i) / 16_000.0) * 0.3 + sin(2.0 * Float.pi * 30.0 * Float(i) / 16_000.0) * 0.1
        }
        let up48k = WAVEncoder.resampleMono(samples: speech16k, from: 16_000, to: 48_000)
        XCTAssertGreaterThan(up48k.count, 46_000)
        let back16k = WAVEncoder.resampleMono(samples: up48k, from: 48_000, to: 16_000)
        XCTAssertGreaterThan(back16k.count, 15_000)

        let cleanedDSP = SpeechEnhancementService.lightweightDSPNoiseSuppress(samples: speech16k)
        XCTAssertEqual(cleanedDSP.count, speech16k.count)

        // 5. MeetingSession speaker rename (batch + minutes sync) & GPT speaker mapping parser
        var meeting = MeetingSession(
            title: "研发周会",
            segments: [
                TranscriptSegment(timestamp: 5, speaker: .remote, speakerLabel: "发言人 1", text: "云端编译问题我来跟进。"),
                TranscriptSegment(timestamp: 12, speaker: .remote, speakerLabel: "发言人 2", text: "我来核对问题表。"),
                TranscriptSegment(timestamp: 20, speaker: .remote, speakerLabel: "发言人 1", text: "今天下午前修复。")
            ],
            minutes: SmartMinutes(
                overview: "发言人 1 负责云端编译，发言人 2 负责核对问题表。",
                topics: [TopicSection(title: "问题跟进", points: ["**云端编译：**由发言人 1 跟进"])],
                actionItems: [ActionItem(task: "修复云端编译", owner: "发言人 1", dueDate: "今天")]
            )
        )
        meeting.renameSpeaker(from: "发言人 1", to: "林致远", onlySegmentID: nil, updateMinutes: true)
        XCTAssertEqual(meeting.segments[0].resolvedSpeakerName, "林致远")
        XCTAssertEqual(meeting.segments[2].resolvedSpeakerName, "林致远")
        XCTAssertEqual(meeting.segments[1].resolvedSpeakerName, "发言人 2")
        XCTAssertEqual(meeting.minutes.actionItems.first?.owner, "林致远")
        XCTAssertTrue(meeting.minutes.overview.contains("林致远"))

        let aiMap = GPTClient.parseSpeakerNameMapping(from: #"```json {"mappings": {"发言人 2": "周明"}} ```"#)
        XCTAssertEqual(aiMap["发言人 2"], "周明")

        // 6. Rich Text HTML export preserves CJK bold and structured table
        let html = MeetingStore.exportHTML(for: meeting)
        XCTAssertTrue(html.contains("<strong>云端编译：</strong>"))
        XCTAssertTrue(html.contains("<table"))
        XCTAssertTrue(html.contains("林致远"))

        // 7. v1.3 AppSettings backward-compatible decoding
        let oldJSON = #"{"authMode":"localAuthFile"}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(oldJSON.utf8))
        XCTAssertEqual(decoded.localUserName, "")
        XCTAssertTrue(decoded.autoIdentifyVoiceprints)
        XCTAssertFalse(decoded.enableSpeechEnhancement)
        XCTAssertEqual(decoded.voiceprintMatchThreshold, 0.56, accuracy: 0.001)
    }

    func testV14MultiLLMCustomTemplatesTagsOnlineClusteringAndLocalhostAuth() throws {
        // 1. Anthropic Claude SSE parser (delta + message_start/delta token usage + error)
        let claudeStart = #"{"type":"message_start","message":{"usage":{"input_tokens":820,"cache_read_input_tokens":200}}}"#
        let claudeDelta = #"{"type":"content_block_delta","delta":{"type":"text_delta","text":"会议要点"}}"#
        let claudeEnd = #"{"type":"message_delta","usage":{"output_tokens":310}}"#
        let e1 = GPTClient.parseAnthropicSSEDataLine(claudeStart)
        let e2 = GPTClient.parseAnthropicSSEDataLine(claudeDelta)
        let e3 = GPTClient.parseAnthropicSSEDataLine(claudeEnd)
        XCTAssertEqual(e1.inputTokens, 820)
        XCTAssertEqual(e1.cachedTokens, 200)
        XCTAssertEqual(e2.delta, "会议要点")
        XCTAssertEqual(e3.outputTokens, 310)

        // 2. Google Gemini SSE parser (candidates text + usageMetadata)
        let geminiLine = #"{"candidates":[{"content":{"parts":[{"text":"阶段周报汇总"}]}}],"usageMetadata":{"promptTokenCount":950,"candidatesTokenCount":410,"cachedContentTokenCount":120,"thoughtsTokenCount":60}}"#
        let gChunk = GPTClient.parseGeminiSSEDataLine(geminiLine)
        XCTAssertEqual(gChunk.delta, "阶段周报汇总")
        XCTAssertEqual(gChunk.usage?.inputTokens, 950)
        XCTAssertEqual(gChunk.usage?.outputTokens, 410)
        XCTAssertEqual(gChunk.usage?.cachedTokens, 120)
        XCTAssertEqual(gChunk.usage?.reasoningTokens, 60)

        // 3. Localhost Ollama / MLX Server works with empty API key + Claude/Gemini resolve cleanly
        var localSettings = AppSettings()
        localSettings.authMode = .apiKey
        localSettings.apiKey = ""
        localSettings.apiBaseURL = "http://localhost:11434/v1"
        let localCred = try AuthManager.shared.resolveCredential(settings: localSettings)
        if case .openAIAPIKey(let key, let url, _, _, _) = localCred {
            XCTAssertEqual(key, "local-no-key")
            XCTAssertEqual(url, "http://localhost:11434/v1")
            XCTAssertFalse(localCred.supportsOpenAIAudioAPI)
        } else {
            XCTFail("Expected local OpenAI-compatible credential")
        }

        var claudeSettings = AppSettings()
        claudeSettings.authMode = .anthropicClaude
        claudeSettings.claudeAPIKey = "sk-ant-demo-key"
        if case .anthropicAPIKey(let k, _, _) = try AuthManager.shared.resolveCredential(settings: claudeSettings) {
            XCTAssertEqual(k, "sk-ant-demo-key")
        } else {
            XCTFail("Expected anthropicAPIKey")
        }

        var geminiSettings = AppSettings()
        geminiSettings.authMode = .googleGemini
        geminiSettings.geminiAPIKey = "AIzaDemoKey"
        if case .geminiAPIKey(let k, _, _) = try AuthManager.shared.resolveCredential(settings: geminiSettings) {
            XCTAssertEqual(k, "AIzaDemoKey")
        } else {
            XCTFail("Expected geminiAPIKey")
        }

        // 4. Unlimited-speaker (>4) OnlineSpeakerClusterBank separates 6 speakers (2 enrolled + 4 dynamic)
        func basisVec(_ idx: Int, dim: Int = 8) -> [Float] {
            var v = [Float](repeating: 0, count: dim)
            v[idx] = 1.0
            return v
        }
        let enrolled = [
            VoiceprintProfile(name: "林致远", embedding: basisVec(0)),
            VoiceprintProfile(name: "周明", embedding: basisVec(1))
        ]
        let bank = OnlineSpeakerClusterBank(enrolledProfiles: enrolled, knownMatchThreshold: 0.56, newClusterThreshold: 0.58)
        XCTAssertEqual(bank.identifyOrCluster(embedding: basisVec(0)), "林致远")
        XCTAssertEqual(bank.identifyOrCluster(embedding: basisVec(1)), "周明")
        XCTAssertEqual(bank.identifyOrCluster(embedding: basisVec(2)), "发言人 1")
        XCTAssertEqual(bank.identifyOrCluster(embedding: basisVec(3)), "发言人 2")
        XCTAssertEqual(bank.identifyOrCluster(embedding: basisVec(4)), "发言人 3")
        XCTAssertEqual(bank.identifyOrCluster(embedding: basisVec(5)), "发言人 4")
        XCTAssertEqual(bank.identifyOrCluster(embedding: basisVec(3)), "发言人 2") // re-matches existing cluster
        XCTAssertEqual(bank.totalSpeakerCount, 6)
        XCTAssertEqual(bank.matchedEnrolledNames, ["林致远", "周明"])

        // 5. Custom Minutes Template resolution + Meeting Tags full-text search
        let customTpl = CustomMinutesTemplate(name: "研发周会模板", promptGuidance: "按模块输出问题表与流程决议")
        var tplSettings = AppSettings()
        tplSettings.customTemplates = [customTpl]
        let taggedMeeting = MeetingSession(
            title: "周四例会",
            customTemplateID: customTpl.id,
            tags: ["研发周会", "性能优化"]
        )
        let resolved = GPTClient.resolveTemplate(for: taggedMeeting, settings: tplSettings)
        XCTAssertEqual(resolved.name, "研发周会模板")
        XCTAssertTrue(resolved.guidance.contains("问题表"))
        XCTAssertTrue(taggedMeeting.matchesSearchQuery("性能优化"))
    }

    func testV15WebhookSigningArchiveBackupAndLocalMLXFormat() throws {
        // 1. Feishu & DingTalk HMAC-SHA256 signing & payload generation
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let session = MeetingSession(
            title: "研发周会",
            sourceAppName: "飞书",
            startedAt: fixedDate,
            duration: 900,
            status: .completed,
            minutes: SmartMinutes(
                overview: "同步云端编译与测试耗时优化进展。",
                topics: [TopicSection(title: "核心问题", points: ["修复云端编译失败"])],
                decisions: ["提测前完成研发自测"],
                actionItems: [ActionItem(task: "补录问题表", owner: "周明", dueDate: "周五")]
            ),
            tags: ["研发周会"]
        )

        let feishuPayload = WebhookPushService.buildFeishuPayload(for: session, secret: "my-feishu-secret", timestamp: fixedDate)
        XCTAssertEqual(feishuPayload["msg_type"] as? String, "interactive")
        XCTAssertEqual(feishuPayload["timestamp"] as? String, "1700000000")
        XCTAssertFalse((feishuPayload["sign"] as? String ?? "").isEmpty)
        XCTAssertEqual(
            feishuPayload["sign"] as? String,
            WebhookPushService.feishuSign(timestampSeconds: 1_700_000_000, secret: "my-feishu-secret")
        )

        let dtURL = WebhookPushService.buildDingTalkSignedURL(
            baseURL: "https://oapi.dingtalk.com/robot/send?access_token=abc",
            secret: "SECdemo",
            timestamp: fixedDate
        )
        XCTAssertTrue(dtURL.contains("&timestamp=1700000000000&sign="))
        let dtPayload = WebhookPushService.buildDingTalkPayload(for: session)
        XCTAssertEqual(dtPayload["msgtype"] as? String, "markdown")

        // 2. Built-in Local MLX LLM credential + Qwen ChatML prompt formatting
        var mlxSettings = AppSettings()
        mlxSettings.authMode = .localMLX
        mlxSettings.localMLXLLMModelID = "mlx-community/Qwen2.5-3B-Instruct-4bit"
        let cred = try AuthManager.shared.resolveCredential(settings: mlxSettings)
        XCTAssertEqual(cred, .localMLX(modelID: "mlx-community/Qwen2.5-3B-Instruct-4bit"))
        let chatPrompt = LocalMLXLLMEngine.formatQwenChatML(system: "系统提示", user: "请总结会议")
        XCTAssertTrue(chatPrompt.contains("<|im_start|>system\n系统提示<|im_end|>"))
        XCTAssertTrue(chatPrompt.contains("<|im_start|>assistant"))

        // 3. Full Data Archive Backup & Non-Destructive Merge Restore (with zero API key leakage)
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("SonoteArchiveTest-\(UUID().uuidString)")
        let srcDir = root.appendingPathComponent("src", isDirectory: true)
        let dstDir = root.appendingPathComponent("dst", isDirectory: true)
        let zipURL = root.appendingPathComponent("backup.zip")
        defer { try? FileManager.default.removeItem(at: root) }

        let srcStore = MeetingStore(baseDirectory: srcDir)
        let srcVPStore = VoiceprintStore(baseDirectory: srcDir)
        srcStore.saveMeeting(session)
        _ = srcStore.recordTokenUsage(TokenUsage(inputTokens: 500, outputTokens: 200, requestCount: 1), on: fixedDate)
        _ = srcVPStore.upsertProfile(name: "林致远", role: "研发", embedding: [1, 0, 0, 0])

        try ArchiveBackupService.exportArchive(
            to: zipURL,
            includeAudioFiles: false,
            store: srcStore,
            voiceprintStore: srcVPStore
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: zipURL.path))

        // Restore into a separate directory that already has an existing meeting (must merge, never overwrite)
        let dstStore = MeetingStore(baseDirectory: dstDir)
        let dstVPStore = VoiceprintStore(baseDirectory: dstDir)
        let existingLocal = MeetingSession(title: "已有本地会议", status: .completed)
        dstStore.saveMeeting(existingLocal)

        let summary = try ArchiveBackupService.importArchive(
            from: zipURL,
            restoreSettings: false,
            store: dstStore,
            voiceprintStore: dstVPStore
        )
        XCTAssertEqual(summary.meetingsImported, 1)
        XCTAssertEqual(summary.voiceprintsImported, 1)
        XCTAssertEqual(dstStore.loadMeetings().count, 2)
        XCTAssertEqual(dstVPStore.loadProfiles().first?.name, "林致远")
        XCTAssertEqual(dstStore.loadTokenLedger()[MeetingStore.dayKey(for: fixedDate)]?.totalTokens, 700)

        // 4. Seamless Legacy TTMinutes -> Sonote Directory Migration & Audio Path Rewrite
        let legacyRoot = root.appendingPathComponent("TTMinutes", isDirectory: true)
        let migratedRoot = root.appendingPathComponent("Sonote", isDirectory: true)
        let legacyStore = MeetingStore(baseDirectory: legacyRoot)
        let legacyAudio = legacyStore.audioBackupURL(for: session.id)
        try Data("fake-m4a".utf8).write(to: legacyAudio)
        var legacySession = session
        legacySession.audioFilePath = legacyAudio.path
        legacyStore.saveMeeting(legacySession)
        _ = VoiceprintStore(baseDirectory: legacyRoot).upsertProfile(name: "陈晨", embedding: [0, 1, 0, 0])

        XCTAssertTrue(MeetingStore.migrateLegacyDirectoryIfNeeded(from: legacyRoot, to: migratedRoot))
        XCTAssertFalse(MeetingStore.migrateLegacyDirectoryIfNeeded(from: legacyRoot, to: migratedRoot)) // idempotent
        let migratedStore = MeetingStore(baseDirectory: migratedRoot)
        let migratedMeetings = migratedStore.loadMeetings()
        XCTAssertEqual(migratedMeetings.count, 1)
        XCTAssertEqual(migratedMeetings.first?.audioFilePath, migratedStore.audioBackupURL(for: session.id).path)
        XCTAssertEqual(VoiceprintStore(baseDirectory: migratedRoot).loadProfiles().first?.name, "陈晨")

        // 5. General Settings (Interface Language, Appearance, Accent Theme, Font Scale & Window Behavior)
        let legacyMinimalJSON = #"{"authMode":"localAuthFile"}"#
        let defaultGeneral = try JSONDecoder().decode(AppSettings.self, from: Data(legacyMinimalJSON.utf8))
        XCTAssertEqual(defaultGeneral.interfaceLanguage, .system)
        XCTAssertEqual(defaultGeneral.appearanceMode, .light)
        XCTAssertEqual(defaultGeneral.accentTheme, .cobaltBlue)
        XCTAssertEqual(defaultGeneral.fontScale, .standard)
        XCTAssertTrue(defaultGeneral.showMenuBarTimer)
        XCTAssertTrue(defaultGeneral.keepRunningInMenuBarOnClose)

        var customized = defaultGeneral
        customized.interfaceLanguage = .en
        customized.appearanceMode = .dark
        customized.accentTheme = .emeraldGreen
        customized.fontScale = .comfortable
        customized.showMenuBarTimer = false
        customized.keepRunningInMenuBarOnClose = false
        let roundTripData = try JSONEncoder().encode(customized)
        let roundTripped = try JSONDecoder().decode(AppSettings.self, from: roundTripData)
        XCTAssertEqual(roundTripped.interfaceLanguage, .en)
        XCTAssertTrue(roundTripped.interfaceLanguage.resolvedIsEnglish)
        XCTAssertFalse(AppInterfaceLanguage.zhHans.resolvedIsEnglish)
        XCTAssertEqual(roundTripped.appearanceMode, .dark)
        XCTAssertEqual(roundTripped.accentTheme, .emeraldGreen)
        XCTAssertEqual(roundTripped.fontScale, .comfortable)
        XCTAssertEqual(roundTripped.fontScale.multiplier, 1.12, accuracy: 0.001)
        XCTAssertFalse(roundTripped.showMenuBarTimer)
        XCTAssertFalse(roundTripped.keepRunningInMenuBarOnClose)

        // 6. Domestic LLM Providers (DeepSeek, Qwen DashScope, Kimi/GLM/Doubao/SiliconFlow/MiniMax/Hunyuan)
        var dsSettings = AppSettings()
        dsSettings.authMode = .deepSeek
        dsSettings.deepSeekAPIKey = "sk-deepseek-demo"
        dsSettings.deepSeekModel = "deepseek-reasoner"
        let dsCred = try AuthManager.shared.resolveCredential(settings: dsSettings)
        if case .openAIAPIKey(let key, let url, _, let model, let label) = dsCred {
            XCTAssertEqual(key, "sk-deepseek-demo")
            XCTAssertEqual(url, "https://api.deepseek.com/v1")
            XCTAssertEqual(model, "deepseek-reasoner")
            XCTAssertEqual(label, "DeepSeek")
            XCTAssertFalse(dsCred.supportsOpenAIAudioAPI)
        } else {
            XCTFail("Expected DeepSeek openAIAPIKey credential")
        }

        var qwenSettings = AppSettings()
        qwenSettings.authMode = .qwenDashScope
        qwenSettings.qwenAPIKey = "sk-qwen-demo"
        qwenSettings.qwenModel = "qwen3-max"
        let qwenCred = try AuthManager.shared.resolveCredential(settings: qwenSettings)
        if case .openAIAPIKey(let key, let url, _, let model, let label) = qwenCred {
            XCTAssertEqual(key, "sk-qwen-demo")
            XCTAssertEqual(url, "https://dashscope.aliyuncs.com/compatible-mode/v1")
            XCTAssertEqual(model, "qwen3-max")
            XCTAssertEqual(label, "通义千问 Qwen")
        } else {
            XCTFail("Expected Qwen DashScope credential")
        }

        var kimiSettings = AppSettings()
        kimiSettings.authMode = .domesticCloud
        kimiSettings.domesticProvider = .siliconFlow
        kimiSettings.domesticAPIKey = "sk-sf-demo"
        kimiSettings.domesticBaseURL = DomesticProviderPreset.siliconFlow.defaultBaseURL
        kimiSettings.domesticModel = "deepseek-ai/DeepSeek-V3"
        let sfCred = try AuthManager.shared.resolveCredential(settings: kimiSettings)
        if case .openAIAPIKey(_, let url, _, let model, let label) = sfCred {
            XCTAssertEqual(url, "https://api.siliconflow.cn/v1")
            XCTAssertEqual(model, "deepseek-ai/DeepSeek-V3")
            XCTAssertEqual(label, "硅基流动")
        } else {
            XCTFail("Expected SiliconFlow domestic credential")
        }

        // DeepSeek top-level `prompt_cache_hit_tokens` + `reasoning_content` SSE + `<think>` JSON stripping
        let dsSSE = #"{"choices":[{"delta":{"reasoning_content":"先梳理议题","content":"最终结论"}}],"usage":{"prompt_tokens":1200,"completion_tokens":380,"prompt_cache_hit_tokens":900,"completion_tokens_details":{"reasoning_tokens":140}}}"#
        let dsChunk = GPTClient.parseChatCompletionsSSEChunk(dsSSE)
        XCTAssertEqual(dsChunk.delta, "最终结论")
        XCTAssertEqual(dsChunk.reasoningDelta, "先梳理议题")
        XCTAssertEqual(dsChunk.usage?.inputTokens, 1200)
        XCTAssertEqual(dsChunk.usage?.outputTokens, 380)
        XCTAssertEqual(dsChunk.usage?.cachedTokens, 900)
        XCTAssertEqual(dsChunk.usage?.reasoningTokens, 140)

        let rawWithThink = """
        <think>草稿思考：{"ignore": true} 应该按模板输出 JSON</think>
        ```json
        {"suggestedTitle":"国产模型评审","overview":"完成 DeepSeek 与通义千问接入","topics":[],"decisions":["默认启用流式输出"],"actionItems":[],"openQuestions":[]}
        ```
        """
        let parsedFromThink = GPTClient.parseSmartMinutes(from: rawWithThink, isFinal: true)
        XCTAssertEqual(parsedFromThink.suggestedTitle, "国产模型评审")
        XCTAssertEqual(parsedFromThink.overview, "完成 DeepSeek 与通义千问接入")
        XCTAssertEqual(parsedFromThink.decisions, ["默认启用流式输出"])
        XCTAssertNil(parsedFromThink.rawMarkdownFallback)

        // 7. Semantic Version Comparison & GitHub Release Update Checker Parsing
        XCTAssertEqual(UpdateCheckerService.compareSemanticVersions("1.5.0", "1.5.1"), .orderedAscending)
        XCTAssertEqual(UpdateCheckerService.compareSemanticVersions("v1.5.1", "1.5.1"), .orderedSame)
        XCTAssertEqual(UpdateCheckerService.compareSemanticVersions("1.6.0", "1.5.9"), .orderedDescending)

        let ghReleaseJSON = #"{"tag_name":"v1.6.0","html_url":"https://github.com/eeachen4/Sonote/releases/tag/v1.6.0","body":"New release"}"#
        let updateCheck = UpdateCheckerService.parseGitHubReleaseJSON(Data(ghReleaseJSON.utf8), currentVersion: "1.5.1")
        XCTAssertEqual(updateCheck?.latestVersion, "1.6.0")
        XCTAssertEqual(updateCheck?.hasUpdate, true)
        let upToDateCheck = UpdateCheckerService.parseGitHubReleaseJSON(Data(ghReleaseJSON.utf8), currentVersion: "1.6.0")
        XCTAssertEqual(upToDateCheck?.hasUpdate, false)
    }

    // MARK: - Obsidian / Local Markdown Folder Sync Tests

    func testMarkdownFolderSyncYAMLFrontmatterAndInPlaceUpdate() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sonote-obsidian-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        var meeting = MeetingSession(
            title: "Q4 / 架构评审: \"MLX\" 管线",
            sourceAppName: "腾讯会议",
            startedAt: Date(timeIntervalSince1970: 1_764_200_000),
            duration: 1845,
            status: .completed,
            segments: [
                TranscriptSegment(timestamp: 10, speaker: .me, speakerLabel: "Alex", text: "确认启用端侧降噪。")
            ],
            minutes: SmartMinutes(
                overview: "敲定了端侧 MLX 性能指标。",
                decisions: ["采用 DeepFilterNet3 v3"],
                actionItems: [ActionItem(task: "补齐单测", owner: "林致远", dueDate: "周五")],
                participants: ["Alex", "林致远"],
                isFinalized: true
            ),
            tags: ["架构评审", "MLX"]
        )

        let firstRes = MarkdownFolderSyncService.shared.sync(meeting: meeting, toFolder: tmpDir.path)
        XCTAssertTrue(firstRes.isSuccess)
        XCTAssertEqual(firstRes.syncedCount, 1)
        let firstURL = try XCTUnwrap(firstRes.lastFileURL)
        let content1 = try String(contentsOf: firstURL, encoding: .utf8)
        XCTAssertTrue(content1.hasPrefix("---\n"))
        XCTAssertTrue(content1.contains("meeting_id: \"\(meeting.id.uuidString)\""))
        XCTAssertTrue(content1.contains("  - sonote"))
        XCTAssertTrue(content1.contains("  - 架构评审"))
        XCTAssertTrue(content1.contains("  - \"Alex\""))
        XCTAssertTrue(content1.contains("敲定了端侧 MLX 性能指标。"))

        // Rename title and update summary -> must update existing file in-place by meeting_id without duplicates!
        meeting.title = "Q4 架构评审（修订版）"
        meeting.minutes.overview = "更新后的最终会议结论。"
        let secondRes = MarkdownFolderSyncService.shared.sync(meeting: meeting, toFolder: tmpDir.path)
        XCTAssertTrue(secondRes.isSuccess)
        XCTAssertEqual(secondRes.lastFileURL?.resolvingSymlinksInPath(), firstURL.resolvingSymlinksInPath())

        let files = try FileManager.default.contentsOfDirectory(at: tmpDir, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.filter { $0.pathExtension == "md" }.count, 1)
        let content2 = try String(contentsOf: firstURL, encoding: .utf8)
        XCTAssertTrue(content2.contains("更新后的最终会议结论。"))
    }

    // MARK: - MeetingStore Fast Index & Corrupted JSON Resilience Tests

    func testMeetingStoreFastIndexAndCorruptedJSONResilience() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sonote-index-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let store = MeetingStore(baseDirectory: tmpDir)

        let m1 = MeetingSession(
            title: "DeepSeek 接入技术评审",
            sourceAppName: "飞书",
            startedAt: Date().addingTimeInterval(-3600),
            duration: 900,
            status: .completed,
            segments: [TranscriptSegment(timestamp: 5, speaker: .me, text: "解析 prompt_cache_hit_tokens 指标")],
            minutes: SmartMinutes(
                overview: "支持 DeepSeek R1 推理模型",
                actionItems: [
                    ActionItem(task: "编写缓存解析单测", owner: "Alex", isCompleted: false),
                    ActionItem(task: "更新设置页 UI", owner: "陈晨", isCompleted: true)
                ],
                isFinalized: true
            ),
            tags: ["AI", "DeepSeek"]
        )
        let m2 = MeetingSession(
            title: "设计走查会议",
            sourceAppName: "Zoom",
            startedAt: Date(),
            duration: 600,
            status: .completed,
            minutes: SmartMinutes(overview: "深色模式对比度微调", isFinalized: true),
            tags: ["UI"]
        )

        store.saveMeeting(m1)
        store.saveMeeting(m2)

        // Inject a corrupted JSON file directly into meetingsDirectory to verify resilience
        let brokenURL = store.meetingsDirectory.appendingPathComponent("broken-corrupt.json")
        try Data("{ invalid json !!!".utf8).write(to: brokenURL)

        // Fast index read & single-meeting lazy load
        let index = store.loadMeetingIndex()
        XCTAssertEqual(index.count, 2)
        XCTAssertEqual(index.first?.id, m2.id)
        XCTAssertEqual(index.last?.openActionItemCount, 1)

        let loadedSingle = store.loadMeeting(id: m1.id)
        XCTAssertEqual(loadedSingle?.title, m1.title)
        XCTAssertEqual(loadedSingle?.segments.count, 1)

        // Search via index without touching full files
        let hits = store.searchIndex(query: "prompt_cache_hit_tokens")
        XCTAssertEqual(hits.map(\.id), [m1.id])
        let tagHits = store.searchIndex(query: "", tag: "UI")
        XCTAssertEqual(tagHits.map(\.id), [m2.id])

        // Rebuild index safely skips broken JSON file
        let rebuilt = store.rebuildMeetingIndex()
        XCTAssertEqual(rebuilt.count, 2)

        // Delete removes both meeting file and index entry
        store.deleteMeeting(m1)
        XCTAssertEqual(store.loadMeetingIndex().map(\.id), [m2.id])
        XCTAssertNil(store.loadMeeting(id: m1.id))
    }

    // MARK: - AppSettings New Fields Backward Compatibility Tests

    func testAppSettingsOnboardingAndObsidianBackwardCompatibility() throws {
        // Legacy JSON missing hasCompletedOnboarding, obsidianVaultPath, autoSyncMarkdownFolder
        let legacyJSON = #"{"authMode":"deepSeek","deepSeekModel":"deepseek-chat","appearanceMode":"dark"}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(decoded.authMode, .deepSeek)
        XCTAssertEqual(decoded.appearanceMode, .dark)
        XCTAssertEqual(decoded.hasCompletedOnboarding, false)
        XCTAssertEqual(decoded.obsidianVaultPath, "")
        XCTAssertEqual(decoded.autoSyncMarkdownFolder, false)

        var updated = decoded
        updated.hasCompletedOnboarding = true
        updated.obsidianVaultPath = "~/Documents/Obsidian/Meetings"
        updated.autoSyncMarkdownFolder = true
        let reEncoded = try JSONEncoder().encode(updated)
        let roundTripped = try JSONDecoder().decode(AppSettings.self, from: reEncoded)
        XCTAssertTrue(roundTripped.hasCompletedOnboarding)
        XCTAssertEqual(roundTripped.obsidianVaultPath, "~/Documents/Obsidian/Meetings")
        XCTAssertTrue(roundTripped.autoSyncMarkdownFolder)
    }

    // MARK: - Webhook HMAC-SHA256 Signing & Payload Builder Tests

    func testWebhookHMACSignaturesAndPayloads() {
        let meeting = MeetingSession(
            title: "周会同步",
            sourceAppName: "飞书",
            startedAt: Date(timeIntervalSince1970: 1_764_200_000),
            duration: 1200,
            minutes: SmartMinutes(
                overview: "对齐了 v1.6 发版计划。",
                decisions: ["开启 GitHub CI macOS 26 runner"],
                actionItems: [ActionItem(task: "补齐单测", owner: "Alex", dueDate: "明天")],
                isFinalized: true
            ),
            tags: ["周会"]
        )

        // Feishu HMAC-SHA256 deterministic signing & interactive card structure
        let sign1 = WebhookPushService.feishuSign(timestampSeconds: 1_700_000_000, secret: "sec-demo")
        let sign2 = WebhookPushService.feishuSign(timestampSeconds: 1_700_000_000, secret: "sec-demo")
        XCTAssertFalse(sign1.isEmpty)
        XCTAssertEqual(sign1, sign2)
        XCTAssertNotEqual(sign1, WebhookPushService.feishuSign(timestampSeconds: 1_700_000_001, secret: "sec-demo"))

        let feishuPayload = WebhookPushService.buildFeishuPayload(
            for: meeting,
            secret: "sec-demo",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertEqual(feishuPayload["msg_type"] as? String, "interactive")
        XCTAssertEqual(feishuPayload["timestamp"] as? String, "1700000000")
        XCTAssertEqual(feishuPayload["sign"] as? String, sign1)

        // DingTalk signed URL appends &timestamp=&sign= cleanly when ? already present
        let dtURL = WebhookPushService.buildDingTalkSignedURL(
            baseURL: "https://oapi.dingtalk.com/robot/send?access_token=abc",
            secret: "SEC123",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertTrue(dtURL.contains("&timestamp=1700000000000&sign="))
        let dtPayload = WebhookPushService.buildDingTalkPayload(for: meeting)
        XCTAssertEqual(dtPayload["msgtype"] as? String, "markdown")

        // Custom JSON payload carries structured fields
        let custom = WebhookPushService.buildCustomJSONPayload(for: meeting)
        XCTAssertEqual(custom["event"] as? String, "sonote.meeting.exported")
        XCTAssertEqual(custom["title"] as? String, "周会同步")
        XCTAssertEqual((custom["tags"] as? [String]) ?? [], ["周会"])
    }

    // MARK: - Multi-Provider SSE & Thinking-Tag Parser Tests

    func testMultiProviderSSEParsersAndUnclosedThinkTag() {
        // Anthropic SSE
        let claudeStart = GPTClient.parseAnthropicSSEDataLine(#"{"type":"message_start","message":{"usage":{"input_tokens":500,"output_tokens":10,"cache_read_input_tokens":320}}}"#)
        XCTAssertEqual(claudeStart.inputTokens, 500)
        XCTAssertEqual(claudeStart.cachedTokens, 320)
        let claudeDelta = GPTClient.parseAnthropicSSEDataLine(#"{"type":"content_block_delta","delta":{"text":"会议摘要"}}"#)
        XCTAssertEqual(claudeDelta.delta, "会议摘要")
        let claudeErr = GPTClient.parseAnthropicSSEDataLine(#"{"type":"error","error":{"message":"overloaded"}}"#)
        XCTAssertEqual(claudeErr.errorMessage, "overloaded")

        // Gemini SSE with cached + thoughts tokens
        let geminiChunk = GPTClient.parseGeminiSSEDataLine(#"{"candidates":[{"content":{"parts":[{"text":"结论如下"}]}}],"usageMetadata":{"promptTokenCount":800,"candidatesTokenCount":200,"cachedContentTokenCount":400,"thoughtsTokenCount":90}}"#)
        XCTAssertEqual(geminiChunk.delta, "结论如下")
        XCTAssertEqual(geminiChunk.usage?.inputTokens, 800)
        XCTAssertEqual(geminiChunk.usage?.outputTokens, 200)
        XCTAssertEqual(geminiChunk.usage?.cachedTokens, 400)
        XCTAssertEqual(geminiChunk.usage?.reasoningTokens, 90)

        // Codex Responses SSE
        let codexDone = GPTClient.parseCodexSSEDataLine(#"{"type":"response.completed","response":{"output":[{"content":[{"text":"完整输出"}]}],"usage":{"input_tokens":300,"output_tokens":120}}}"#)
        XCTAssertEqual(codexDone.completedText, "完整输出")
        XCTAssertEqual(codexDone.usage?.totalTokens, 420)

        // Unclosed <think> tag safety
        let unclosed = "前置有效内容\n<think>正在推理中但被截断..."
        XCTAssertEqual(GPTClient.stripThinkingTags(unclosed), "前置有效内容")
    }

    // MARK: - WAVEncoder Integrity Tests

    func testWAVEncoderHeaderAndSize() {
        let samples = (0..<1600).map { i in sin(Float(i) * 0.1) * 0.5 }
        let wav = WAVEncoder.encodeMono16kWAV(samples: samples, sampleRate: 16_000)
        // 44-byte RIFF/WAVE header + 1600 * 2 bytes PCM16
        XCTAssertEqual(wav.count, 44 + 1600 * 2)
        XCTAssertEqual(String(data: wav.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: wav.subdata(in: 8..<12), encoding: .ascii), "WAVE")

        // Verify 16kHz -> 48kHz mono resampling produces ~3x samples
        let upsampled = WAVEncoder.resampleMono(samples: samples, from: 16_000, to: 48_000)
        XCTAssertGreaterThan(upsampled.count, 4500)
        XCTAssertLessThan(upsampled.count, 5100)
    }

    // MARK: - Opt-in Live Hardware Verification for DeepFilterNet3, ECAPA-TDNN & Sortformer (SONOTE_LIVE_V15=1)

    func testLiveVoiceprintDenoiserAndDiarization() async throws {
        guard ProcessInfo.processInfo.environment["SONOTE_LIVE_V15"] == "1" else {
            throw XCTSkip("Set SONOTE_LIVE_V15=1 to run live DeepFilterNet3 + ECAPA-TDNN + Sortformer verification.")
        }

        let hfHost = ProcessInfo.processInfo.environment["SONOTE_HF_HOST"] ?? "https://huggingface.co"

        func synthSpeech(voice: String?, text: String) throws -> [Float] {
            let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("sonote-live-\(UUID().uuidString).aiff")
            defer { try? FileManager.default.removeItem(at: tmp) }
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            proc.arguments = voice != nil ? ["-v", voice!, "-o", tmp.path, text] : ["-o", tmp.path, text]
            try proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus != 0 {
                let fb = Process()
                fb.executableURL = URL(fileURLWithPath: "/usr/bin/say")
                fb.arguments = ["-o", tmp.path, text]
                try fb.run()
                fb.waitUntilExit()
                XCTAssertEqual(fb.terminationStatus, 0)
            }
            let f = try AVAudioFile(forReading: tmp)
            guard let buf = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length)) else {
                XCTFail("buffer alloc failed")
                return []
            }
            try f.read(into: buf)
            return WAVEncoder.extractMono16kSamples(from: buf)
        }

        let voiceA1 = try synthSpeech(voice: "Tingting", text: "大家好，今天我们来讨论智能会议纪要的声纹识别和人声降噪效果。")
        let voiceA2 = try synthSpeech(voice: "Tingting", text: "云端编译问题已经排查完毕，本周五前可以合入主分支并发布新版本。")
        let voiceB1 = try synthSpeech(voice: "Daniel", text: "Hello everyone, let us review the Apple Silicon speaker diarization and noise suppression pipeline today.")

        // 1. Live DeepFilterNet3 v3 Neural Speech Enhancement
        let noisy = voiceA1.enumerated().map { idx, s in
            max(-1.0, min(1.0, s + sin(Float(idx) * 0.05) * 0.04))
        }
        let denoiseStart = Date()
        let enhanced = await SpeechEnhancementService.shared.enhance16k(samples: noisy, hfHost: hfHost)
        let denoiseSec = Date().timeIntervalSince(denoiseStart)
        let dfnLoaded = await SpeechEnhancementService.shared.isModelLoaded()
        XCTAssertTrue(dfnLoaded, "DeepFilterNet3 v3 model should load and run on Apple Silicon")
        XCTAssertGreaterThan(enhanced.count, noisy.count * 8 / 10)
        print(String(format: "[LIVE V1.5] DeepFilterNet3 v3 loaded=%@ enhanced=%d samples in %.2fs", "\(dfnLoaded)", enhanced.count, denoiseSec))
        await SpeechEnhancementService.shared.unload()

        // 2. Live ECAPA-TDNN 192-dim Speaker Voiceprint Extraction & Same/Cross Speaker Discrimination
        let ecapaStart = Date()
        let embA1 = try await VoiceprintService.shared.extractEmbedding(samples16k: voiceA1, hfHost: hfHost)
        let embA2 = try await VoiceprintService.shared.extractEmbedding(samples16k: voiceA2, hfHost: hfHost)
        let embB1 = try await VoiceprintService.shared.extractEmbedding(samples16k: voiceB1, hfHost: hfHost)
        let ecapaSec = Date().timeIntervalSince(ecapaStart)
        XCTAssertEqual(embA1.count, 192)
        let simSame = VoiceprintMath.cosineSimilarity(embA1, embA2)
        let simDiff = VoiceprintMath.cosineSimilarity(embA1, embB1)
        print(String(format: "[LIVE V1.5] ECAPA-TDNN 192-dim in %.2fs | sameSpeaker=%.3f diffSpeaker=%.3f", ecapaSec, simSame, simDiff))
        XCTAssertGreaterThan(simSame, simDiff + 0.15, "Same-speaker similarity should significantly exceed different-speaker similarity")
        await VoiceprintService.shared.unload()

        // 3. Live Sortformer + ECAPA-TDNN Cross-Meeting Auto-Identification on Concatenated 2-Speaker Audio
        let silencePad = [Float](repeating: 0, count: 16_000)
        let combined = voiceA1 + silencePad + voiceB1 + silencePad + voiceA2
        let sortStart = Date()
        let diarSegs = try await SpeakerDiarizerService.shared.diarize(samples16k: combined, hfHost: hfHost)
        let sortSec = Date().timeIntervalSince(sortStart)
        let uniqueSpks = Set(diarSegs.map(\.speaker))
        print(String(format: "[LIVE V1.5] Sortformer in %.2fs | segments=%d uniqueSpeakers=%d", sortSec, diarSegs.count, uniqueSpks.count))
        XCTAssertGreaterThanOrEqual(diarSegs.count, 2)
        XCTAssertGreaterThanOrEqual(uniqueSpks.count, 2)
        await SpeakerDiarizerService.shared.unload()

        // 4. Verify ECAPA-TDNN cross-meeting clustering identifies both speakers cleanly
        let durA1 = Double(voiceA1.count) / 16_000.0
        let durB1 = Double(voiceB1.count) / 16_000.0
        let mockSegs = [
            TranscriptSegment(timestamp: 0.2, speaker: .remote, text: "第一段发言"),
            TranscriptSegment(timestamp: durA1 + 1.2, speaker: .remote, text: "Second speaker turn"),
            TranscriptSegment(timestamp: durA1 + 1.0 + durB1 + 1.2, speaker: .remote, text: "第一人继续发言")
        ]
        let enrolled = [
            VoiceprintProfile(name: "婷婷", embedding: embA1),
            VoiceprintProfile(name: "Daniel", embedding: embB1)
        ]
        let clusterResult = await SpeakerDiarizerService.diarizeByVoiceprintClustering(
            segments: mockSegs,
            fullSamples16k: combined,
            meetingDuration: Double(combined.count) / 16_000.0,
            profiles: enrolled,
            matchThreshold: 0.56,
            hfHost: hfHost
        )
        print("[LIVE V1.5] Voiceprint Auto-ID => \(clusterResult.segments.map(\.resolvedSpeakerName))")
        XCTAssertEqual(clusterResult.segments[0].resolvedSpeakerName, "婷婷")
        XCTAssertEqual(clusterResult.segments[1].resolvedSpeakerName, "Daniel")
        XCTAssertEqual(clusterResult.segments[2].resolvedSpeakerName, "婷婷")
    }

    // MARK: - Opt-in Live MLX Qwen3-ASR Transcription Verification (SONOTE_LIVE_MLX=1)

    func testLiveMLXQwen3ASRTranscription() async throws {
        guard ProcessInfo.processInfo.environment["SONOTE_LIVE_MLX"] == "1" else {
            throw XCTSkip("Set SONOTE_LIVE_MLX=1 to run live MLX Qwen3-ASR transcription verification.")
        }

        // Synthesize a bilingual Chinese + English utterance via macOS `say`
        let tempAIFF = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("sonote-qwen3-test.aiff")
        defer { try? FileManager.default.removeItem(at: tempAIFF) }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        // Use a Chinese voice (e.g. Tingting) so both Mandarin and embedded English terms are spoken
        proc.arguments = ["-v", "Tingting", "-o", tempAIFF.path, "今天我们来 review 一下智能会议纪要的 API 接口和 Apple Silicon 本地识别效果。"]
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            let fallback = Process()
            fallback.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            fallback.arguments = ["-o", tempAIFF.path, "Today we will review the smart meeting minutes API and Apple Silicon local transcription."]
            try fallback.run()
            fallback.waitUntilExit()
            XCTAssertEqual(fallback.terminationStatus, 0, "macOS say failed to generate test audio")
        }

        let file = try AVAudioFile(forReading: tempAIFF)
        let frameCount = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount) else {
            return XCTFail("Failed to allocate PCM buffer")
        }
        try file.read(into: buffer)
        let samples = WAVEncoder.extractMono16kSamples(from: buffer)
        XCTAssertGreaterThan(samples.count, 16_000)

        let modelID = ProcessInfo.processInfo.environment["SONOTE_MLX_MODEL"] ?? "mlx-community/Qwen3-ASR-0.6B-8bit"
        let hfHost = ProcessInfo.processInfo.environment["SONOTE_HF_HOST"] ?? "https://huggingface.co"

        let start = Date()
        let text = try await MLXQwen3ASREngine.shared.transcribe(
            samples: samples,
            language: .autoBilingual,
            context: "review, API, Apple Silicon, 智能会议纪要",
            modelID: modelID,
            hfHost: hfHost
        ) { state in
            print("[LIVE-MLX] State: \(state.statusText)")
        }
        let elapsed = Date().timeIntervalSince(start)
        let audioSecs = Double(samples.count) / 16_000.0
        print("[LIVE-MLX] Model=\(modelID) audio=\(String(format: "%.2f", audioSecs))s elapsed=\(String(format: "%.2f", elapsed))s text=\(text)")

        XCTAssertFalse(text.isEmpty, "Qwen3-ASR returned empty transcript")
        XCTAssertTrue(
            text.contains("会议") || text.contains("接口") || text.localizedCaseInsensitiveContains("review") || text.localizedCaseInsensitiveContains("API"),
            "Unexpected Qwen3-ASR transcript: \(text)"
        )

        await MLXQwen3ASREngine.shared.unloadModel()
        let postUnloadState = await MLXQwen3ASREngine.shared.currentState()
        XCTAssertEqual(postUnloadState, .idle)
    }

    // MARK: - Opt-in Live End-to-End Verification (SONOTE_LIVE_VERIFY=1)

    func testLiveEnvironmentAndGPTIntegration() async throws {
        guard ProcessInfo.processInfo.environment["SONOTE_LIVE_VERIFY"] == "1" else {
            throw XCTSkip("Set SONOTE_LIVE_VERIFY=1 to run live macOS & GPT integration verification.")
        }

        // 1. Inspect local ~/.codex/auth.json (never log raw tokens)
        let settings = AppSettings()
        let inspection = AuthManager.shared.inspect(settings: settings)
        print("[LIVE] Auth valid=\(inspection.isValid) summary=\(inspection.summary) detail=\(inspection.detail)")
        XCTAssertTrue(inspection.isValid, "Local auth inspection failed: \(inspection.detail)")

        // 2. Test live GPT connection
        let conn = await GPTClient.shared.testConnection(settings: settings)
        print("[LIVE] GPT testConnection success=\(conn.success) model=\(conn.modelUsed) latency=\(conn.latencyMs)ms msg=\(conn.message)")
        XCTAssertTrue(conn.success, "GPT live connection failed: \(conn.message)")

        // 3. Test live Smart Minutes generation with realistic Chinese meeting transcript
        let sampleMeeting = MeetingSession(
            title: "腾讯会议 · 13:30",
            sourceAppName: "腾讯会议",
            duration: 180,
            segments: [
                TranscriptSegment(timestamp: 5, speaker: .remote, text: "今天我们同步一下 Mac Sonote 声记上线前的验证项，重点看系统声音采集和 GPT 实时总结。"),
                TranscriptSegment(timestamp: 25, speaker: .me, text: "收到，系统声音采集和双轨转写已经写完，我今天下午五点前完成联调并提交测试报告。"),
                TranscriptSegment(timestamp: 52, speaker: .remote, text: "好的，那下周一全员内测，另外需要确认一下离线语音包下载速度。")
            ],
            manualNotes: "关注：下周一全员内测"
        )
        let (minutes, usage) = try await GPTClient.shared.generateMinutesWithUsage(for: sampleMeeting, settings: settings, isFinal: true)
        print("[LIVE] Minutes suggestedTitle=\(minutes.suggestedTitle)")
        print("[LIVE] Minutes overview=\(minutes.overview)")
        print("[LIVE] Minutes topics=\(minutes.topics.count) decisions=\(minutes.decisions.count) actions=\(minutes.actionItems.count) questions=\(minutes.openQuestions.count)")
        print("[LIVE] TokenUsage total=\(usage.totalTokens) (\(usage.detailedSummary)) estimated=\(usage.isEstimated)")
        XCTAssertGreaterThan(usage.totalTokens, 0, "Expected non-zero token usage")
        XCTAssertFalse(minutes.isEmpty, "Generated minutes should not be empty")
        XCTAssertNil(minutes.rawMarkdownFallback, "Expected structured JSON smart minutes, got raw fallback")
        XCTAssertFalse(minutes.actionItems.isEmpty, "Expected at least one action item extracted")

        // 4. Test CoreAudio process scanning live
        let procs = MeetingDetector.fetchAudioProcesses(excludingPID: ProcessInfo.processInfo.processIdentifier)
        print("[LIVE] CoreAudio active audio processes count=\(procs.count)")
        for p in procs.prefix(8) {
            print("[LIVE]   proc pid=\(p.pid) bundle=\(p.bundleID) in=\(p.isRunningInput) out=\(p.isRunningOutput)")
        }

        // 5. Check macOS 26 SpeechTranscriber availability live
        if #available(macOS 26.0, *) {
            let zhLocale = Locale(identifier: "zh-CN")
            let supported = await SpeechTranscriber.supportedLocale(equivalentTo: zhLocale)
            print("[LIVE] SpeechTranscriber.isAvailable=\(SpeechTranscriber.isAvailable) zh-CN supported=\(supported?.identifier ?? "nil")")
            if let supported {
                let module = SpeechTranscriber(
                    locale: supported,
                    transcriptionOptions: [],
                    reportingOptions: [.volatileResults, .fastResults],
                    attributeOptions: [.audioTimeRange]
                )
                let assetStatus = await AssetInventory.status(forModules: [module])
                let bestFmt = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module])
                print("[LIVE] SpeechTranscriber zh-CN assetStatus=\(assetStatus) bestFormat=\(String(describing: bestFmt))")
            }
        }
    }
}
