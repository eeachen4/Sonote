import Foundation

/// Thread-safe language bridge so `SonoteCore` display strings follow General Settings live.
public enum SonoteLocale {
    private static let lock = NSLock()
    private static var _isEnglish: Bool = false

    public static var isEnglish: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _isEnglish }
        set { lock.lock(); _isEnglish = newValue; lock.unlock() }
    }

    public static func t(_ zh: String, _ en: String) -> String {
        isEnglish ? en : zh
    }
}

public enum MinutesOutputLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto = "auto"
    case zhHans = "zh-Hans"
    case english = "en"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .auto: return SonoteLocale.t("自动跟随会议语言（推荐）", "Auto (Match Transcript)")
        case .zhHans: return SonoteLocale.t("固定输出简体中文", "Always Simplified Chinese")
        case .english: return SonoteLocale.t("固定输出 English", "Always English")
        }
    }

    public var promptDirective: String {
        switch self {
        case .auto:
            return "语言要求：默认跟随会议逐字稿的主要语言输出纪要（中英混说会议默认使用自然流畅的简体中文并保留关键英文专业术语）。"
        case .zhHans:
            return "语言要求：无论原会议使用中文、英文还是其他语言，所有纪要字段（suggestedTitle、overview、topics、decisions、actionItems、openQuestions）都必须使用专业、简洁的简体中文输出（可保留专有名词与代码标识）。"
        case .english:
            return "Language Requirement: Regardless of the spoken language in the transcript, write ALL JSON values (suggestedTitle, overview, topics, decisions, actionItems, openQuestions) in crisp, natural professional English."
        }
    }
}

public enum AppInterfaceLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case system = "system"
    case zhHans = "zh-Hans"
    case en = "en"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: return "跟随系统 / System"
        case .zhHans: return "简体中文"
        case .en: return "English"
        }
    }

    public func localizedName(isEnglish: Bool) -> String {
        switch self {
        case .system: return isEnglish ? "Follow System" : "跟随系统"
        case .zhHans: return "简体中文"
        case .en: return "English"
        }
    }

    public var resolvedIsEnglish: Bool {
        switch self {
        case .zhHans:
            return false
        case .en:
            return true
        case .system:
            let preferred = Locale.preferredLanguages.first?.lowercased() ?? "zh"
            return !preferred.hasPrefix("zh")
        }
    }
}

public enum AppAppearanceMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    public var id: String { rawValue }

    public func localizedName(isEnglish: Bool) -> String {
        switch self {
        case .system: return isEnglish ? "Auto" : "跟随系统"
        case .light: return isEnglish ? "Light" : "浅色"
        case .dark: return isEnglish ? "Dark" : "深色"
        }
    }
}

public struct AccentRGB: Equatable, Sendable {
    public let r: Double
    public let g: Double
    public let b: Double

    public init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }
}

public enum AppAccentTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case cobaltBlue = "cobaltBlue"
    case indigoViolet = "indigoViolet"
    case emeraldGreen = "emeraldGreen"
    case amberGold = "amberGold"
    case roseCoral = "roseCoral"
    case graphiteSlate = "graphiteSlate"

    public var id: String { rawValue }

    public func localizedName(isEnglish: Bool) -> String {
        switch self {
        case .cobaltBlue: return isEnglish ? "Cobalt" : "晴空蓝"
        case .indigoViolet: return isEnglish ? "Indigo" : "星云紫"
        case .emeraldGreen: return isEnglish ? "Emerald" : "青竹绿"
        case .amberGold: return isEnglish ? "Amber" : "琥珀橙"
        case .roseCoral: return isEnglish ? "Rose" : "绯樱粉"
        case .graphiteSlate: return isEnglish ? "Graphite" : "石墨灰"
        }
    }

    public var lightRGB: AccentRGB {
        switch self {
        case .cobaltBlue: return AccentRGB(0.13, 0.43, 0.97)     // #216EF7
        case .indigoViolet: return AccentRGB(0.39, 0.36, 0.98)   // #635BFF
        case .emeraldGreen: return AccentRGB(0.06, 0.64, 0.48)   // #10A37A
        case .amberGold: return AccentRGB(0.88, 0.49, 0.11)      // #E07D1C
        case .roseCoral: return AccentRGB(0.89, 0.27, 0.41)      // #E34568
        case .graphiteSlate: return AccentRGB(0.31, 0.35, 0.42)  // #4F596B
        }
    }

    public var darkRGB: AccentRGB {
        switch self {
        case .cobaltBlue: return AccentRGB(0.33, 0.58, 1.00)     // #5494FF
        case .indigoViolet: return AccentRGB(0.55, 0.52, 1.00)   // #8C85FF
        case .emeraldGreen: return AccentRGB(0.18, 0.78, 0.60)   // #2EC799
        case .amberGold: return AccentRGB(0.96, 0.62, 0.25)      // #F59E40
        case .roseCoral: return AccentRGB(0.96, 0.42, 0.55)      // #F56B8C
        case .graphiteSlate: return AccentRGB(0.62, 0.67, 0.76)  // #9EABC2
        }
    }
}

public enum AppFontScale: String, Codable, CaseIterable, Identifiable, Sendable {
    case compact = "compact"
    case standard = "standard"
    case comfortable = "comfortable"

    public var id: String { rawValue }

    public var multiplier: Double {
        switch self {
        case .compact: return 0.92
        case .standard: return 1.0
        case .comfortable: return 1.12
        }
    }

    public func localizedName(isEnglish: Bool) -> String {
        switch self {
        case .compact: return isEnglish ? "Compact" : "紧凑"
        case .standard: return isEnglish ? "Standard" : "标准"
        case .comfortable: return isEnglish ? "Large" : "舒适"
        }
    }
}

public enum DomesticProviderPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case kimi = "kimi"
    case zhipuGLM = "zhipuGLM"
    case doubaoArk = "doubaoArk"
    case siliconFlow = "siliconFlow"
    case miniMax = "miniMax"
    case hunyuan = "hunyuan"

    public var id: String { rawValue }

    public var shortName: String {
        switch self {
        case .kimi: return "Kimi"
        case .zhipuGLM: return SonoteLocale.t("智谱 GLM", "Zhipu GLM")
        case .doubaoArk: return SonoteLocale.t("豆包方舟", "Doubao Ark")
        case .siliconFlow: return SonoteLocale.t("硅基流动", "SiliconFlow")
        case .miniMax: return "MiniMax"
        case .hunyuan: return SonoteLocale.t("腾讯混元", "Hunyuan")
        }
    }

    public var displayName: String {
        switch self {
        case .kimi: return SonoteLocale.t("Kimi（月之暗面 Moonshot）", "Kimi (Moonshot AI)")
        case .zhipuGLM: return SonoteLocale.t("智谱 GLM（BigModel）", "Zhipu GLM (BigModel)")
        case .doubaoArk: return SonoteLocale.t("豆包（火山方舟 Ark）", "Doubao (Volcengine Ark)")
        case .siliconFlow: return SonoteLocale.t("硅基流动（SiliconFlow）", "SiliconFlow")
        case .miniMax: return SonoteLocale.t("MiniMax 开放平台", "MiniMax")
        case .hunyuan: return SonoteLocale.t("腾讯混元（Hunyuan）", "Tencent Hunyuan")
        }
    }

    public var defaultBaseURL: String {
        switch self {
        case .kimi: return "https://api.moonshot.cn/v1"
        case .zhipuGLM: return "https://open.bigmodel.cn/api/paas/v4"
        case .doubaoArk: return "https://ark.cn-beijing.volces.com/api/v3"
        case .siliconFlow: return "https://api.siliconflow.cn/v1"
        case .miniMax: return "https://api.minimax.chat/v1"
        case .hunyuan: return "https://api.hunyuan.cloud.tencent.com/v1"
        }
    }

    public var defaultModel: String {
        suggestedModels.first ?? ""
    }

    public var suggestedModels: [String] {
        switch self {
        case .kimi:
            return ["kimi-k2-0905-preview", "kimi-k2-turbo-preview", "moonshot-v1-128k", "moonshot-v1-32k"]
        case .zhipuGLM:
            return ["glm-4.5", "glm-4.5-air", "glm-4-plus", "glm-4-flash"]
        case .doubaoArk:
            return ["doubao-seed-1-6-250615", "doubao-1-5-pro-32k-250115", "doubao-1-5-lite-32k-250115", "deepseek-v3-250324"]
        case .siliconFlow:
            return ["deepseek-ai/DeepSeek-V3", "deepseek-ai/DeepSeek-R1", "Qwen/Qwen3-32B", "Qwen/Qwen2.5-72B-Instruct"]
        case .miniMax:
            return ["MiniMax-M1", "MiniMax-Text-01", "abab6.5s-chat"]
        case .hunyuan:
            return ["hunyuan-turbos-latest", "hunyuan-t1-latest", "hunyuan-large"]
        }
    }

    public var envVarName: String {
        switch self {
        case .kimi: return "MOONSHOT_API_KEY"
        case .zhipuGLM: return "ZHIPU_API_KEY"
        case .doubaoArk: return "ARK_API_KEY"
        case .siliconFlow: return "SILICONFLOW_API_KEY"
        case .miniMax: return "MINIMAX_API_KEY"
        case .hunyuan: return "HUNYUAN_API_KEY"
        }
    }

    public var modelHint: String {
        switch self {
        case .doubaoArk: return SonoteLocale.t("可直接填模型名或火山方舟推理接入点 ID（ep-...）", "Enter a model ID or Volcengine Ark endpoint ID (ep-...)")
        case .siliconFlow: return SonoteLocale.t("聚合 DeepSeek-V3 / R1 / Qwen3 等开源旗舰模型", "Hosts DeepSeek-V3 / R1, Qwen3 and open flagship models")
        case .kimi: return SonoteLocale.t("长上下文表现优异，适合超长会议纪要与追问", "Strong long-context performance for lengthy meetings")
        default: return SonoteLocale.t("支持从列表选择或手动输入任意官方模型 ID", "Pick from presets or enter any official model ID")
        }
    }
}

public enum AuthMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case localAuthFile = "localAuthFile"
    case apiKey = "apiKey"
    case deepSeek = "deepSeek"
    case qwenDashScope = "qwenDashScope"
    case domesticCloud = "domesticCloud"
    case anthropicClaude = "anthropicClaude"
    case googleGemini = "googleGemini"
    case localMLX = "localMLX"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .localAuthFile: return "Codex Auth"
        case .apiKey: return SonoteLocale.t("OpenAI / 本地", "OpenAI / Local")
        case .deepSeek: return "DeepSeek"
        case .qwenDashScope: return SonoteLocale.t("通义千问 Qwen", "Alibaba Qwen")
        case .domesticCloud: return SonoteLocale.t("更多国产", "CN Presets")
        case .anthropicClaude: return "Claude"
        case .googleGemini: return "Gemini"
        case .localMLX: return SonoteLocale.t("内置离线 MLX", "Offline MLX")
        }
    }

    public var subtitle: String {
        switch self {
        case .localAuthFile: return SonoteLocale.t("自动读取 ~/.codex/auth.json 或自定义 JSON / .env 凭证文件", "Reads ~/.codex/auth.json or custom JSON / .env credentials")
        case .apiKey: return SonoteLocale.t("支持 OpenAI、自定义中转或本地 Ollama / MLX Server", "Supports OpenAI, custom relays, or local Ollama / MLX Server")
        case .deepSeek: return SonoteLocale.t("原生适配深度求索 DeepSeek-V3 / R1 推理模型，精准统计缓存命中与思考 Token", "Native DeepSeek-V3 / R1 support with cache hit & reasoning token tracking")
        case .qwenDashScope: return SonoteLocale.t("原生接入阿里云百炼通义千问（Qwen3 / Qwen-Max / Qwen-Plus / Qwen-Long）", "Native Alibaba DashScope Qwen (Qwen3 / Qwen-Max / Plus / Long)")
        case .domesticCloud: return SonoteLocale.t("一键预设 Kimi、智谱 GLM、豆包火山方舟、硅基流动、MiniMax 与腾讯混元", "One-click presets for Kimi, Zhipu GLM, Doubao, SiliconFlow, MiniMax & Hunyuan")
        case .anthropicClaude: return SonoteLocale.t("原生接入 Anthropic Claude Messages API（支持自定义代理地址）", "Native Anthropic Claude Messages API with custom proxy URL support")
        case .googleGemini: return SonoteLocale.t("原生接入 Google Gemini Stream API（支持免费/付费 Key）", "Native Google Gemini streaming API")
        case .localMLX: return SonoteLocale.t("在 App 内直接通过 Apple Silicon Metal 运行本地 Qwen2.5-Instruct，100% 离线零 Token 费用", "Runs quantized Qwen2.5-Instruct on Apple Silicon Metal GPU — 100% offline, zero fees")
        }
    }
}

public enum WebhookProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case feishu = "feishu"
    case dingtalk = "dingtalk"
    case customJSON = "customJSON"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .feishu: return SonoteLocale.t("飞书机器人卡片", "Feishu Card")
        case .dingtalk: return SonoteLocale.t("钉钉机器人 Markdown", "DingTalk Markdown")
        case .customJSON: return SonoteLocale.t("通用 JSON Webhook（Notion / n8n）", "Custom JSON (Notion / n8n)")
        }
    }
}

public enum DiarizationStrategy: String, Codable, CaseIterable, Identifiable, Sendable {
    case sortformerFourSpeaker = "sortformer"
    case voiceprintClusteringUnlimited = "voiceprintClustering"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .sortformerFourSpeaker: return SonoteLocale.t("Sortformer 精准分离（适合 ≤4 人会议）", "Sortformer Precision (≤4 speakers)")
        case .voiceprintClusteringUnlimited: return SonoteLocale.t("ECAPA 声纹聚类（突破 4 人上限，支持 5~12 人大组会）", "ECAPA Voiceprint Clustering (5–12+ speakers)")
        }
    }
}

public struct CustomMinutesTemplate: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var promptGuidance: String

    public init(id: UUID = UUID(), name: String, promptGuidance: String) {
        self.id = id
        self.name = name
        self.promptGuidance = promptGuidance
    }
}

public enum AudioCaptureMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case systemAndMic = "systemAndMic"
    case systemOnly = "systemOnly"
    case micOnly = "micOnly"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .systemAndMic: return SonoteLocale.t("系统声音 + 麦克风（推荐）", "System Audio + Mic (Recommended)")
        case .systemOnly: return SonoteLocale.t("仅采集系统声音（对方声音）", "System Audio Only (Remote)")
        case .micOnly: return SonoteLocale.t("仅采集麦克风（本机输入）", "Microphone Only (Local)")
        }
    }

    public var capturesSystem: Bool {
        self == .systemAndMic || self == .systemOnly
    }

    public var capturesMic: Bool {
        self == .systemAndMic || self == .micOnly
    }
}

public enum TranscriptionEngine: String, Codable, CaseIterable, Identifiable, Sendable {
    case mlxQwen3ASR = "mlxQwen3ASR"
    case appleSpeech = "appleSpeech"
    case openAITranscribe = "openAITranscribe"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .mlxQwen3ASR: return SonoteLocale.t("MLX Qwen3-ASR 本地引擎（推荐 · 中英混说高精度）", "MLX Qwen3-ASR Local (Recommended · Bilingual)")
        case .appleSpeech: return SonoteLocale.t("Apple 本机实时识别（轻量免下载）", "Apple On-Device Speech (Zero Download)")
        case .openAITranscribe: return SonoteLocale.t("OpenAI 音频转写 API（需 API Key）", "OpenAI Transcribe API")
        }
    }
}

public struct MLXQwen3ModelPreset: Identifiable, Hashable, Sendable {
    public var id: String { repoID }
    public var repoID: String
    public var label: String
    public var footprintHint: String

    public init(repoID: String, label: String, footprintHint: String) {
        self.repoID = repoID
        self.label = label
        self.footprintHint = footprintHint
    }

    public static let all: [MLXQwen3ModelPreset] = [
        MLXQwen3ModelPreset(
            repoID: "mlx-community/Qwen3-ASR-1.7B-8bit",
            label: "Qwen3-ASR 1.7B (8-bit · 最高中英精度)",
            footprintHint: "~2.3 GB 内存"
        ),
        MLXQwen3ModelPreset(
            repoID: "mlx-community/Qwen3-ASR-1.7B-4bit",
            label: "Qwen3-ASR 1.7B (4-bit · 高精度轻量)",
            footprintHint: "~1.4 GB 内存"
        ),
        MLXQwen3ModelPreset(
            repoID: "mlx-community/Qwen3-ASR-0.6B-8bit",
            label: "Qwen3-ASR 0.6B (8-bit · 极速均衡)",
            footprintHint: "~0.9 GB 内存"
        ),
        MLXQwen3ModelPreset(
            repoID: "mlx-community/Qwen3-ASR-0.6B-4bit",
            label: "Qwen3-ASR 0.6B (4-bit · 超轻极速)",
            footprintHint: "~0.6 GB 内存"
        )
    ]
}

public enum MinutesTemplate: String, Codable, CaseIterable, Identifiable, Sendable {
    case general = "general"
    case techReview = "techReview"
    case interview = "interview"
    case oneOnOne = "oneOnOne"
    case clientSync = "clientSync"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .general: return SonoteLocale.t("通用会议", "General Meeting")
        case .techReview: return SonoteLocale.t("研发技术评审", "Engineering Review")
        case .interview: return SonoteLocale.t("面试评估", "Interview Notes")
        case .oneOnOne: return SonoteLocale.t("1-on-1 沟通", "1-on-1 Sync")
        case .clientSync: return SonoteLocale.t("客户与商务沟通", "Client & Business")
        }
    }

    public var promptGuidance: String {
        switch self {
        case .general:
            return "按标准商务会议纪要提炼核心背景、讨论议题、已确认决议、带负责人与截止时间的待办事项以及待确认风险。"
        case .techReview:
            return "以研发技术评审风格提炼：重点保留技术方案对比、架构取舍、API/埋点/数据契约变更、性能指标、回退方案、排期里程碑与技术风险。"
        case .interview:
            return "以面试评估纪要风格提炼：topics 按考察维度（项目深度/算法基础/系统设计/沟通协作）组织；decisions 填写综合评价与录用倾向建议；openQuestions 填写待后续轮次重点追问的疑点。"
        case .oneOnOne:
            return "以 1-on-1 沟通纪要风格提炼：聚焦近期进展、当前卡点与所需支持、双向反馈建议、下阶段目标与双方跟进事项。"
        case .clientSync:
            return "以客户沟通纪要风格提炼：聚焦客户核心诉求、痛点与异议、我方承诺方案、商务/排期节点以及需要内部协同落地的跟进项。"
        }
    }
}

public enum TranscriptionLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case autoBilingual = "auto"
    case zhCN = "zh-CN"
    case enUS = "en-US"
    case zhTW = "zh-TW"
    case jaJP = "ja-JP"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .autoBilingual: return SonoteLocale.t("自动检测（中英混说推荐）", "Auto-Detect (ZH/EN Bilingual)")
        case .zhCN: return "简体中文 (zh-CN)"
        case .enUS: return "English (en-US)"
        case .zhTW: return "繁體中文 (zh-TW)"
        case .jaJP: return "日本語 (ja-JP)"
        }
    }

    public var iso639Code: String {
        switch self {
        case .autoBilingual, .zhCN, .zhTW: return "zh"
        case .enUS: return "en"
        case .jaJP: return "ja"
        }
    }

    public var appleLocaleIdentifier: String {
        switch self {
        case .autoBilingual: return "zh-CN"
        default: return rawValue
        }
    }

    /// Passed to Qwen3ASRModel.generate(language:). `nil` enables seamless Chinese-English code-switching.
    public var qwen3LanguageName: String? {
        switch self {
        case .autoBilingual: return nil
        case .zhCN, .zhTW: return "Chinese"
        case .enUS: return "English"
        case .jaJP: return "Japanese"
        }
    }
}

public enum GlobalHotKeyModifierPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case optionShift = "optionShift"
    case controlOption = "controlOption"
    case controlShift = "controlShift"

    public var id: String { rawValue }

    public var symbolPrefix: String {
        switch self {
        case .optionShift: return "⌥⇧"
        case .controlOption: return "⌃⌥"
        case .controlShift: return "⌃⇧"
        }
    }

    public var displayName: String {
        switch self {
        case .optionShift: return SonoteLocale.t("⌥⇧R / ⌥⇧M（推荐，不与浏览器冲突）", "⌥⇧R / ⌥⇧M (Recommended)")
        case .controlOption: return "⌃⌥R / ⌃⌥M"
        case .controlShift: return "⌃⇧R / ⌃⇧M"
        }
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    // General (Interface Language, Appearance, Accent Theme, Font Scale & Window Behavior)
    public var interfaceLanguage: AppInterfaceLanguage = .system
    public var appearanceMode: AppAppearanceMode = .light
    public var accentTheme: AppAccentTheme = .cobaltBlue
    public var fontScale: AppFontScale = .standard
    public var showMenuBarTimer: Bool = true
    public var keepRunningInMenuBarOnClose: Bool = true
    public var hasCompletedOnboarding: Bool = false

    // Local Markdown / Obsidian Vault Auto-Sync
    public var obsidianVaultPath: String = ""
    public var autoSyncMarkdownFolder: Bool = false

    // AI & Auth (Multi-Provider: Codex Auth, OpenAI/Ollama/MLX, Claude, Gemini)
    public var authMode: AuthMode = .localAuthFile
    public var authFilePath: String = "~/.codex/auth.json"
    public var apiKey: String = ""
    public var apiBaseURL: String = "https://api.openai.com/v1"
    public var model: String = "gpt-5.4"
    public var codexModel: String = ""
    public var deepSeekAPIKey: String = ""
    public var deepSeekBaseURL: String = "https://api.deepseek.com/v1"
    public var deepSeekModel: String = "deepseek-chat"
    public var qwenAPIKey: String = ""
    public var qwenBaseURL: String = "https://dashscope.aliyuncs.com/compatible-mode/v1"
    public var qwenModel: String = "qwen-plus"
    public var domesticProvider: DomesticProviderPreset = .kimi
    public var domesticAPIKey: String = ""
    public var domesticBaseURL: String = "https://api.moonshot.cn/v1"
    public var domesticModel: String = "kimi-k2-0905-preview"
    public var claudeAPIKey: String = ""
    public var claudeBaseURL: String = "https://api.anthropic.com/v1"
    public var claudeModel: String = "claude-sonnet-4-5"
    public var geminiAPIKey: String = ""
    public var geminiBaseURL: String = "https://generativelanguage.googleapis.com/v1beta"
    public var geminiModel: String = "gemini-2.5-flash"
    public var localMLXLLMModelID: String = "mlx-community/Qwen2.5-3B-Instruct-4bit"
    public var openAITranscribeModel: String = "gpt-4o-mini-transcribe"

    // Webhook Push Integration (Feishu / DingTalk / Notion / n8n)
    public var webhookProvider: WebhookProvider = .feishu
    public var webhookURL: String = ""
    public var webhookSecret: String = ""

    // Audio & Transcription
    public var audioCaptureMode: AudioCaptureMode = .systemAndMic
    public var transcriptionEngine: TranscriptionEngine = .mlxQwen3ASR
    public var transcriptionLanguage: TranscriptionLanguage = .autoBilingual
    public var saveAudioBackup: Bool = true
    public var localUserName: String = ""

    // MLX Qwen3-ASR, Neural VAD, Denoise & Voiceprint Diarization Settings
    public var mlxQwen3ModelID: String = "mlx-community/Qwen3-ASR-1.7B-8bit"
    public var mlxAutoUnloadAfterMeeting: Bool = true
    public var mlxHuggingFaceHost: String = "https://huggingface.co"
    public var asrContextHint: String = ""
    public var glossaryTerms: [String] = []
    public var enableNeuralVAD: Bool = true
    public var sileroVADModelID: String = "mlx-community/silero-vad-v6"
    public var enableSpeechEnhancement: Bool = false
    public var speechEnhancementModelID: String = "mlx-community/DeepFilterNet-mlx"
    public var enableEchoDeduplication: Bool = true
    public var enableSpeakerDiarization: Bool = false
    public var enableLiveSpeakerDiarization: Bool = false
    public var diarizationStrategy: DiarizationStrategy = .sortformerFourSpeaker
    public var autoIdentifyVoiceprints: Bool = true
    public var diarizationModelID: String = "mlx-community/diar_streaming_sortformer_4spk-v2.1-fp16"
    public var voiceprintModelID: String = "aufklarer/SpeechBrain-ECAPA-VoxCeleb-20M-MLX"
    public var voiceprintMatchThreshold: Float = 0.56

    // Live Minutes Behavior & Custom Templates
    public var defaultMinutesTemplate: MinutesTemplate = .general
    public var minutesOutputLanguage: MinutesOutputLanguage = .auto
    public var customTemplates: [CustomMinutesTemplate] = []
    public var liveSummaryEnabled: Bool = true
    public var liveSummaryIntervalSeconds: Int = 35
    public var showFloatingCapsuleWhileRecording: Bool = true
    public var enableLiveSubtitleTranslation: Bool = false
    public var customMinutesPrompt: String = ""

    // Meeting Detection, Calendar & Global Hotkeys
    public var autoDetectMeetings: Bool = true
    public var detectBrowserCalls: Bool = true
    public var promptOnMeetingEnd: Bool = true
    public var enableCalendarIntegration: Bool = true
    public var enableGlobalHotKeys: Bool = true
    public var globalHotKeyPreset: GlobalHotKeyModifierPreset = .optionShift
    public var monitoredBundleIDs: [String] = MeetingAppCatalog.defaultBundleIDs
    public var ignoredBundleIDs: [String] = [
        "com.work.pc.doubao",
        "com.work.pc.doubao.browser.helper",
        "com.bytedance.doubao"
    ]

    public init() {}

    // Backward-compatible decoder so existing settings.json files migrate cleanly
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        interfaceLanguage = try c.decodeIfPresent(AppInterfaceLanguage.self, forKey: .interfaceLanguage) ?? d.interfaceLanguage
        appearanceMode = try c.decodeIfPresent(AppAppearanceMode.self, forKey: .appearanceMode) ?? d.appearanceMode
        accentTheme = try c.decodeIfPresent(AppAccentTheme.self, forKey: .accentTheme) ?? d.accentTheme
        fontScale = try c.decodeIfPresent(AppFontScale.self, forKey: .fontScale) ?? d.fontScale
        showMenuBarTimer = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarTimer) ?? d.showMenuBarTimer
        keepRunningInMenuBarOnClose = try c.decodeIfPresent(Bool.self, forKey: .keepRunningInMenuBarOnClose) ?? d.keepRunningInMenuBarOnClose
        hasCompletedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? d.hasCompletedOnboarding
        obsidianVaultPath = try c.decodeIfPresent(String.self, forKey: .obsidianVaultPath) ?? d.obsidianVaultPath
        autoSyncMarkdownFolder = try c.decodeIfPresent(Bool.self, forKey: .autoSyncMarkdownFolder) ?? d.autoSyncMarkdownFolder

        authMode = try c.decodeIfPresent(AuthMode.self, forKey: .authMode) ?? d.authMode
        authFilePath = try c.decodeIfPresent(String.self, forKey: .authFilePath) ?? d.authFilePath
        apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey) ?? d.apiKey
        apiBaseURL = try c.decodeIfPresent(String.self, forKey: .apiBaseURL) ?? d.apiBaseURL
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? d.model
        codexModel = try c.decodeIfPresent(String.self, forKey: .codexModel) ?? d.codexModel
        deepSeekAPIKey = try c.decodeIfPresent(String.self, forKey: .deepSeekAPIKey) ?? d.deepSeekAPIKey
        deepSeekBaseURL = try c.decodeIfPresent(String.self, forKey: .deepSeekBaseURL) ?? d.deepSeekBaseURL
        deepSeekModel = try c.decodeIfPresent(String.self, forKey: .deepSeekModel) ?? d.deepSeekModel
        qwenAPIKey = try c.decodeIfPresent(String.self, forKey: .qwenAPIKey) ?? d.qwenAPIKey
        qwenBaseURL = try c.decodeIfPresent(String.self, forKey: .qwenBaseURL) ?? d.qwenBaseURL
        qwenModel = try c.decodeIfPresent(String.self, forKey: .qwenModel) ?? d.qwenModel
        domesticProvider = try c.decodeIfPresent(DomesticProviderPreset.self, forKey: .domesticProvider) ?? d.domesticProvider
        domesticAPIKey = try c.decodeIfPresent(String.self, forKey: .domesticAPIKey) ?? d.domesticAPIKey
        domesticBaseURL = try c.decodeIfPresent(String.self, forKey: .domesticBaseURL) ?? d.domesticBaseURL
        domesticModel = try c.decodeIfPresent(String.self, forKey: .domesticModel) ?? d.domesticModel
        claudeAPIKey = try c.decodeIfPresent(String.self, forKey: .claudeAPIKey) ?? d.claudeAPIKey
        claudeBaseURL = try c.decodeIfPresent(String.self, forKey: .claudeBaseURL) ?? d.claudeBaseURL
        claudeModel = try c.decodeIfPresent(String.self, forKey: .claudeModel) ?? d.claudeModel
        geminiAPIKey = try c.decodeIfPresent(String.self, forKey: .geminiAPIKey) ?? d.geminiAPIKey
        geminiBaseURL = try c.decodeIfPresent(String.self, forKey: .geminiBaseURL) ?? d.geminiBaseURL
        geminiModel = try c.decodeIfPresent(String.self, forKey: .geminiModel) ?? d.geminiModel
        localMLXLLMModelID = try c.decodeIfPresent(String.self, forKey: .localMLXLLMModelID) ?? d.localMLXLLMModelID
        openAITranscribeModel = try c.decodeIfPresent(String.self, forKey: .openAITranscribeModel) ?? d.openAITranscribeModel
        webhookProvider = try c.decodeIfPresent(WebhookProvider.self, forKey: .webhookProvider) ?? d.webhookProvider
        webhookURL = try c.decodeIfPresent(String.self, forKey: .webhookURL) ?? d.webhookURL
        webhookSecret = try c.decodeIfPresent(String.self, forKey: .webhookSecret) ?? d.webhookSecret

        audioCaptureMode = try c.decodeIfPresent(AudioCaptureMode.self, forKey: .audioCaptureMode) ?? d.audioCaptureMode
        transcriptionEngine = try c.decodeIfPresent(TranscriptionEngine.self, forKey: .transcriptionEngine) ?? d.transcriptionEngine
        transcriptionLanguage = try c.decodeIfPresent(TranscriptionLanguage.self, forKey: .transcriptionLanguage) ?? d.transcriptionLanguage
        saveAudioBackup = try c.decodeIfPresent(Bool.self, forKey: .saveAudioBackup) ?? d.saveAudioBackup
        localUserName = try c.decodeIfPresent(String.self, forKey: .localUserName) ?? d.localUserName

        mlxQwen3ModelID = try c.decodeIfPresent(String.self, forKey: .mlxQwen3ModelID) ?? d.mlxQwen3ModelID
        mlxAutoUnloadAfterMeeting = try c.decodeIfPresent(Bool.self, forKey: .mlxAutoUnloadAfterMeeting) ?? d.mlxAutoUnloadAfterMeeting
        mlxHuggingFaceHost = try c.decodeIfPresent(String.self, forKey: .mlxHuggingFaceHost) ?? d.mlxHuggingFaceHost
        asrContextHint = try c.decodeIfPresent(String.self, forKey: .asrContextHint) ?? d.asrContextHint
        glossaryTerms = try c.decodeIfPresent([String].self, forKey: .glossaryTerms) ?? d.glossaryTerms
        enableNeuralVAD = try c.decodeIfPresent(Bool.self, forKey: .enableNeuralVAD) ?? d.enableNeuralVAD
        sileroVADModelID = try c.decodeIfPresent(String.self, forKey: .sileroVADModelID) ?? d.sileroVADModelID
        enableSpeechEnhancement = try c.decodeIfPresent(Bool.self, forKey: .enableSpeechEnhancement) ?? d.enableSpeechEnhancement
        speechEnhancementModelID = try c.decodeIfPresent(String.self, forKey: .speechEnhancementModelID) ?? d.speechEnhancementModelID
        enableEchoDeduplication = try c.decodeIfPresent(Bool.self, forKey: .enableEchoDeduplication) ?? d.enableEchoDeduplication
        enableSpeakerDiarization = try c.decodeIfPresent(Bool.self, forKey: .enableSpeakerDiarization) ?? d.enableSpeakerDiarization
        enableLiveSpeakerDiarization = try c.decodeIfPresent(Bool.self, forKey: .enableLiveSpeakerDiarization) ?? d.enableLiveSpeakerDiarization
        diarizationStrategy = try c.decodeIfPresent(DiarizationStrategy.self, forKey: .diarizationStrategy) ?? d.diarizationStrategy
        autoIdentifyVoiceprints = try c.decodeIfPresent(Bool.self, forKey: .autoIdentifyVoiceprints) ?? d.autoIdentifyVoiceprints
        diarizationModelID = try c.decodeIfPresent(String.self, forKey: .diarizationModelID) ?? d.diarizationModelID
        voiceprintModelID = try c.decodeIfPresent(String.self, forKey: .voiceprintModelID) ?? d.voiceprintModelID
        voiceprintMatchThreshold = try c.decodeIfPresent(Float.self, forKey: .voiceprintMatchThreshold) ?? d.voiceprintMatchThreshold

        defaultMinutesTemplate = try c.decodeIfPresent(MinutesTemplate.self, forKey: .defaultMinutesTemplate) ?? d.defaultMinutesTemplate
        minutesOutputLanguage = try c.decodeIfPresent(MinutesOutputLanguage.self, forKey: .minutesOutputLanguage) ?? d.minutesOutputLanguage
        customTemplates = try c.decodeIfPresent([CustomMinutesTemplate].self, forKey: .customTemplates) ?? d.customTemplates
        liveSummaryEnabled = try c.decodeIfPresent(Bool.self, forKey: .liveSummaryEnabled) ?? d.liveSummaryEnabled
        liveSummaryIntervalSeconds = try c.decodeIfPresent(Int.self, forKey: .liveSummaryIntervalSeconds) ?? d.liveSummaryIntervalSeconds
        showFloatingCapsuleWhileRecording = try c.decodeIfPresent(Bool.self, forKey: .showFloatingCapsuleWhileRecording) ?? d.showFloatingCapsuleWhileRecording
        enableLiveSubtitleTranslation = try c.decodeIfPresent(Bool.self, forKey: .enableLiveSubtitleTranslation) ?? d.enableLiveSubtitleTranslation
        customMinutesPrompt = try c.decodeIfPresent(String.self, forKey: .customMinutesPrompt) ?? d.customMinutesPrompt

        autoDetectMeetings = try c.decodeIfPresent(Bool.self, forKey: .autoDetectMeetings) ?? d.autoDetectMeetings
        detectBrowserCalls = try c.decodeIfPresent(Bool.self, forKey: .detectBrowserCalls) ?? d.detectBrowserCalls
        promptOnMeetingEnd = try c.decodeIfPresent(Bool.self, forKey: .promptOnMeetingEnd) ?? d.promptOnMeetingEnd
        enableCalendarIntegration = try c.decodeIfPresent(Bool.self, forKey: .enableCalendarIntegration) ?? d.enableCalendarIntegration
        enableGlobalHotKeys = try c.decodeIfPresent(Bool.self, forKey: .enableGlobalHotKeys) ?? d.enableGlobalHotKeys
        globalHotKeyPreset = try c.decodeIfPresent(GlobalHotKeyModifierPreset.self, forKey: .globalHotKeyPreset) ?? d.globalHotKeyPreset
        monitoredBundleIDs = try c.decodeIfPresent([String].self, forKey: .monitoredBundleIDs) ?? d.monitoredBundleIDs
        ignoredBundleIDs = try c.decodeIfPresent([String].self, forKey: .ignoredBundleIDs) ?? d.ignoredBundleIDs
    }

    public static let suggestedAPIModels: [String] = [
        "gpt-5.4",
        "gpt-5.2",
        "gpt-5-mini",
        "gpt-4.1",
        "gpt-4o",
        "gpt-4o-mini"
    ]

    public static let suggestedCodexModels: [String] = [
        "gpt-6.1-sol",
        "gpt-6.2-sol",
        "gpt-6.2-astra",
        "gpt-5.6-sol"
    ]

    public static let suggestedDeepSeekModels: [String] = [
        "deepseek-chat",
        "deepseek-reasoner"
    ]

    public static let suggestedQwenModels: [String] = [
        "qwen-plus",
        "qwen-max",
        "qwen-turbo",
        "qwen3-max",
        "qwen3-235b-a22b",
        "qwq-plus",
        "qwen-long"
    ]

    public static let suggestedClaudeModels: [String] = [
        "claude-sonnet-4-5",
        "claude-opus-4-1",
        "claude-3-7-sonnet-latest",
        "claude-3-5-haiku-latest"
    ]

    public static let suggestedGeminiModels: [String] = [
        "gemini-2.5-pro",
        "gemini-2.5-flash",
        "gemini-2.5-flash-lite"
    ]

    public static let suggestedLocalMLXLLMModels: [String] = [
        "mlx-community/Qwen2.5-3B-Instruct-4bit",
        "mlx-community/Qwen2.5-7B-Instruct-4bit",
        "mlx-community/Qwen2.5-1.5B-Instruct-4bit"
    ]
}

public struct MeetingAppDescriptor: Identifiable, Hashable, Codable, Sendable {
    public var id: String { bundleID }
    public var bundleID: String
    public var displayName: String
    public var isBrowser: Bool
    /// Dedicated meeting apps can trigger even on sustained output audio (e.g. muted listener)
    public var isDedicatedMeetingApp: Bool

    public init(bundleID: String, displayName: String, isBrowser: Bool = false, isDedicatedMeetingApp: Bool = false) {
        self.bundleID = bundleID
        self.displayName = displayName
        self.isBrowser = isBrowser
        self.isDedicatedMeetingApp = isDedicatedMeetingApp
    }
}

public enum MeetingAppCatalog {
    public static let all: [MeetingAppDescriptor] = [
        MeetingAppDescriptor(bundleID: "com.tencent.meeting", displayName: "腾讯会议", isDedicatedMeetingApp: true),
        MeetingAppDescriptor(bundleID: "com.tencent.voov", displayName: "VooV Meeting", isDedicatedMeetingApp: true),
        MeetingAppDescriptor(bundleID: "com.electron.lark", displayName: "飞书", isDedicatedMeetingApp: false),
        MeetingAppDescriptor(bundleID: "com.bytedance.lark", displayName: "飞书", isDedicatedMeetingApp: false),
        MeetingAppDescriptor(bundleID: "com.larksuite.larkApp", displayName: "Lark", isDedicatedMeetingApp: false),
        MeetingAppDescriptor(bundleID: "com.alibaba.DingTalkMac", displayName: "钉钉", isDedicatedMeetingApp: false),
        MeetingAppDescriptor(bundleID: "com.tencent.WeWorkMac", displayName: "企业微信", isDedicatedMeetingApp: false),
        MeetingAppDescriptor(bundleID: "com.tencent.xinWeChat", displayName: "微信语音/视频", isDedicatedMeetingApp: false),
        MeetingAppDescriptor(bundleID: "us.zoom.xos", displayName: "Zoom", isDedicatedMeetingApp: true),
        MeetingAppDescriptor(bundleID: "com.microsoft.teams2", displayName: "Microsoft Teams", isDedicatedMeetingApp: true),
        MeetingAppDescriptor(bundleID: "com.microsoft.teams", displayName: "Microsoft Teams", isDedicatedMeetingApp: true),
        MeetingAppDescriptor(bundleID: "com.apple.FaceTime", displayName: "FaceTime", isDedicatedMeetingApp: true),
        MeetingAppDescriptor(bundleID: "com.tinyspeck.slackmacgap", displayName: "Slack Huddle", isDedicatedMeetingApp: false),
        MeetingAppDescriptor(bundleID: "com.hnc.Discord", displayName: "Discord", isDedicatedMeetingApp: false),
        MeetingAppDescriptor(bundleID: "com.cisco.webexmeetingsapp", displayName: "Webex", isDedicatedMeetingApp: true),
        MeetingAppDescriptor(bundleID: "com.google.Chrome", displayName: "Chrome 网页会议", isBrowser: true),
        MeetingAppDescriptor(bundleID: "com.apple.Safari", displayName: "Safari 网页会议", isBrowser: true),
        MeetingAppDescriptor(bundleID: "company.thebrowser.Browser", displayName: "Arc 网页会议", isBrowser: true),
        MeetingAppDescriptor(bundleID: "com.microsoft.edgemac", displayName: "Edge 网页会议", isBrowser: true)
    ]

    public static var defaultBundleIDs: [String] {
        all.map(\.bundleID)
    }

    public static func descriptor(for bundleID: String) -> MeetingAppDescriptor? {
        all.first { $0.bundleID.caseInsensitiveCompare(bundleID) == .orderedSame }
    }
}
