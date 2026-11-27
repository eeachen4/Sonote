import Foundation

public struct CodexOAuthCredential: Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String?
    public var idToken: String?
    public var accountID: String?
    public var clientID: String
    public var issuer: String
    public var authFilePath: String
    public var lastRefresh: String?
    public var email: String?
    public var planType: String?
    public var expiresAt: Date?

    public static let defaultClientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    public static let defaultIssuer = "https://auth.openai.com"

    public init(
        accessToken: String,
        refreshToken: String? = nil,
        idToken: String? = nil,
        accountID: String? = nil,
        clientID: String = CodexOAuthCredential.defaultClientID,
        issuer: String = CodexOAuthCredential.defaultIssuer,
        authFilePath: String,
        lastRefresh: String? = nil,
        email: String? = nil,
        planType: String? = nil,
        expiresAt: Date? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.idToken = idToken
        self.accountID = accountID
        self.clientID = clientID
        self.issuer = issuer
        self.authFilePath = authFilePath
        self.lastRefresh = lastRefresh
        self.email = email
        self.planType = planType
        self.expiresAt = expiresAt
    }

    public var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSinceNow < 60
    }
}

public enum ResolvedCredential: Equatable, Sendable {
    case openAIAPIKey(apiKey: String, baseURL: String, source: String, modelOverride: String? = nil, providerLabel: String? = nil)
    case codexOAuth(CodexOAuthCredential)
    case anthropicAPIKey(apiKey: String, baseURL: String, source: String)
    case geminiAPIKey(apiKey: String, baseURL: String, source: String)
    case localMLX(modelID: String)

    public var displayBadge: String {
        switch self {
        case .openAIAPIKey(_, _, let source, _, let providerLabel):
            let label = providerLabel ?? "OpenAI 兼容"
            return "\(label) (\(source))"
        case .codexOAuth(let oauth):
            if let email = oauth.email, !email.isEmpty {
                return "Codex Auth · \(email)"
            }
            return "Codex OAuth Auth"
        case .anthropicAPIKey(_, _, let source):
            return "Claude (\(source))"
        case .geminiAPIKey(_, _, let source):
            return "Gemini (\(source))"
        case .localMLX(let modelID):
            let short = modelID.split(separator: "/").last.map(String.init) ?? modelID
            return "内置离线 MLX · \(short)"
        }
    }

    public var supportsOpenAIAudioAPI: Bool {
        if case .openAIAPIKey(let key, _, _, _, let providerLabel) = self {
            return providerLabel == nil && !key.isEmpty && key != "local-no-key"
        }
        return false
    }
}

public struct AuthInspectionResult: Equatable, Sendable {
    public var isValid: Bool
    public var summary: String
    public var detail: String
    public var credential: ResolvedCredential?

    public init(isValid: Bool, summary: String, detail: String, credential: ResolvedCredential? = nil) {
        self.isValid = isValid
        self.summary = summary
        self.detail = detail
        self.credential = credential
    }
}

public enum AuthError: LocalizedError {
    case missingCredential(String)
    case fileNotFound(String)
    case invalidAuthFile(String)
    case refreshFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingCredential(let msg): return msg
        case .fileNotFound(let path): return "找不到凭证文件：\(path)"
        case .invalidAuthFile(let msg): return "Auth 文件解析失败：\(msg)"
        case .refreshFailed(let msg): return "刷新 OAuth 凭证失败：\(msg)"
        }
    }
}

public final class AuthManager: @unchecked Sendable {
    public static let shared = AuthManager()

    public static let knownAuthFilePaths: [String] = [
        "~/.codex/auth.json",
        "~/.openai/auth.json",
        "~/.config/openai/auth.json",
        "~/.config/codex/auth.json"
    ]

    public init() {}

    public func expandPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed as NSString).expandingTildeInPath
    }

    public func discoverExistingAuthFiles() -> [String] {
        Self.knownAuthFilePaths.filter { path in
            FileManager.default.fileExists(atPath: expandPath(path))
        }
    }

    public struct LocalCodexCatalog: Equatable, Sendable {
        public var defaultModel: String?
        public var availableModels: [String]

        public init(defaultModel: String?, availableModels: [String]) {
            self.defaultModel = defaultModel
            self.availableModels = availableModels
        }
    }

    /// Reads sibling `models_cache.json` and `config.toml` next to `auth.json` (e.g. `~/.codex/`)
    /// so the app automatically uses the user's actually accessible Codex models.
    public func discoverLocalCodexCatalog(authFilePath: String = "~/.codex/auth.json") -> LocalCodexCatalog {
        let expanded = expandPath(authFilePath)
        let dir = URL(fileURLWithPath: expanded).deletingLastPathComponent()

        var models: [String] = []
        let cacheURL = dir.appendingPathComponent("models_cache.json")
        if let data = try? Data(contentsOf: cacheURL),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let list = root["models"] as? [[String: Any]] {
            for item in list {
                let visibility = (item["visibility"] as? String) ?? "list"
                if visibility == "hide" { continue }
                if let slug = item["slug"] as? String, !slug.isEmpty, !models.contains(slug) {
                    models.append(slug)
                }
            }
        }

        var defaultModel: String? = nil
        let configURL = dir.appendingPathComponent("config.toml")
        if let toml = try? String(contentsOf: configURL, encoding: .utf8) {
            for rawLine in toml.components(separatedBy: .newlines) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                // Stop scanning top-level keys once a [table] starts
                if line.hasPrefix("[") { break }
                if line.hasPrefix("model ") || line.hasPrefix("model=") {
                    if let eqIdx = line.firstIndex(of: "=") {
                        let rhs = line[line.index(after: eqIdx)...]
                            .components(separatedBy: "#").first ?? ""
                        let cleaned = rhs.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'"))
                        if !cleaned.isEmpty {
                            defaultModel = cleaned
                            if !models.contains(cleaned) {
                                models.insert(cleaned, at: 0)
                            }
                            break
                        }
                    }
                }
            }
        }

        if defaultModel == nil {
            defaultModel = models.first
        }

        return LocalCodexCatalog(defaultModel: defaultModel, availableModels: models)
    }

    public func resolveCredential(settings: AppSettings) throws -> ResolvedCredential {
        switch settings.authMode {
        case .apiKey:
            let trimmedKey = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let baseURL = normalizeBaseURL(settings.apiBaseURL)
            if !trimmedKey.isEmpty {
                return .openAIAPIKey(apiKey: trimmedKey, baseURL: baseURL, source: "手动输入")
            }
            if Self.isLocalhostEndpoint(baseURL) {
                return .openAIAPIKey(apiKey: "local-no-key", baseURL: baseURL, source: "本地零成本服务")
            }
            if let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !envKey.isEmpty {
                return .openAIAPIKey(apiKey: envKey, baseURL: baseURL, source: "环境变量")
            }
            throw AuthError.missingCredential("请输入 OpenAI API Key，或填本地 Ollama / MLX Server 地址（如 http://localhost:11434/v1）。")

        case .deepSeek:
            let trimmedKey = settings.deepSeekAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let baseURL = normalizeCustomBaseURL(settings.deepSeekBaseURL, fallback: "https://api.deepseek.com/v1")
            let chosenModel = settings.deepSeekModel.trimmingCharacters(in: .whitespacesAndNewlines)
            let model = chosenModel.isEmpty ? "deepseek-chat" : chosenModel
            if !trimmedKey.isEmpty {
                return .openAIAPIKey(apiKey: trimmedKey, baseURL: baseURL, source: "手动输入", modelOverride: model, providerLabel: "DeepSeek")
            }
            if let envKey = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !envKey.isEmpty {
                return .openAIAPIKey(apiKey: envKey, baseURL: baseURL, source: "环境变量", modelOverride: model, providerLabel: "DeepSeek")
            }
            throw AuthError.missingCredential("请输入 DeepSeek API Key（或配置 DEEPSEEK_API_KEY 环境变量）。")

        case .qwenDashScope:
            let trimmedKey = settings.qwenAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let baseURL = normalizeCustomBaseURL(settings.qwenBaseURL, fallback: "https://dashscope.aliyuncs.com/compatible-mode/v1")
            let chosenModel = settings.qwenModel.trimmingCharacters(in: .whitespacesAndNewlines)
            let model = chosenModel.isEmpty ? "qwen-plus" : chosenModel
            if !trimmedKey.isEmpty {
                return .openAIAPIKey(apiKey: trimmedKey, baseURL: baseURL, source: "手动输入", modelOverride: model, providerLabel: "通义千问 Qwen")
            }
            if let envKey = (ProcessInfo.processInfo.environment["DASHSCOPE_API_KEY"] ?? ProcessInfo.processInfo.environment["QWEN_API_KEY"])?.trimmingCharacters(in: .whitespacesAndNewlines),
               !envKey.isEmpty {
                return .openAIAPIKey(apiKey: envKey, baseURL: baseURL, source: "环境变量", modelOverride: model, providerLabel: "通义千问 Qwen")
            }
            throw AuthError.missingCredential("请输入阿里云百炼 DashScope API Key（或配置 DASHSCOPE_API_KEY 环境变量）。")

        case .domesticCloud:
            let preset = settings.domesticProvider
            let trimmedKey = settings.domesticAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let baseURL = normalizeCustomBaseURL(settings.domesticBaseURL, fallback: preset.defaultBaseURL)
            let chosenModel = settings.domesticModel.trimmingCharacters(in: .whitespacesAndNewlines)
            let model = chosenModel.isEmpty ? preset.defaultModel : chosenModel
            if !trimmedKey.isEmpty {
                return .openAIAPIKey(apiKey: trimmedKey, baseURL: baseURL, source: "手动输入", modelOverride: model, providerLabel: preset.shortName)
            }
            if let envKey = ProcessInfo.processInfo.environment[preset.envVarName]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !envKey.isEmpty {
                return .openAIAPIKey(apiKey: envKey, baseURL: baseURL, source: "环境变量", modelOverride: model, providerLabel: preset.shortName)
            }
            throw AuthError.missingCredential("请输入 \(preset.displayName) API Key（或配置 \(preset.envVarName) 环境变量）。")

        case .anthropicClaude:
            let trimmedKey = settings.claudeAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let baseURL = normalizeCustomBaseURL(settings.claudeBaseURL, fallback: "https://api.anthropic.com/v1")
            if !trimmedKey.isEmpty {
                return .anthropicAPIKey(apiKey: trimmedKey, baseURL: baseURL, source: "手动输入")
            }
            if let envKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !envKey.isEmpty {
                return .anthropicAPIKey(apiKey: envKey, baseURL: baseURL, source: "环境变量")
            }
            throw AuthError.missingCredential("请输入 Anthropic Claude API Key（或配置 ANTHROPIC_API_KEY 环境变量）。")

        case .googleGemini:
            let trimmedKey = settings.geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let baseURL = normalizeCustomBaseURL(settings.geminiBaseURL, fallback: "https://generativelanguage.googleapis.com/v1beta")
            if !trimmedKey.isEmpty {
                return .geminiAPIKey(apiKey: trimmedKey, baseURL: baseURL, source: "手动输入")
            }
            if let envKey = (ProcessInfo.processInfo.environment["GEMINI_API_KEY"] ?? ProcessInfo.processInfo.environment["GOOGLE_API_KEY"])?.trimmingCharacters(in: .whitespacesAndNewlines),
               !envKey.isEmpty {
                return .geminiAPIKey(apiKey: envKey, baseURL: baseURL, source: "环境变量")
            }
            throw AuthError.missingCredential("请输入 Google Gemini API Key（或配置 GEMINI_API_KEY 环境变量）。")

        case .localAuthFile:
            let path = settings.authFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
            if path.isEmpty {
                throw AuthError.missingCredential("请指定本机 Auth 文件路径（例如 ~/.codex/auth.json）。")
            }
            return try parseAuthFile(at: path, fallbackBaseURL: normalizeBaseURL(settings.apiBaseURL))

        case .localMLX:
            let modelID = settings.localMLXLLMModelID.trimmingCharacters(in: .whitespacesAndNewlines)
            let chosen = modelID.isEmpty ? "mlx-community/Qwen2.5-3B-Instruct-4bit" : modelID
            return .localMLX(modelID: chosen)
        }
    }

    public static func isLocalhostEndpoint(_ urlString: String) -> Bool {
        guard let host = URL(string: urlString)?.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1" || host.hasSuffix(".local")
    }

    private func normalizeCustomBaseURL(_ raw: String, fallback: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { s = fallback }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    public func inspect(settings: AppSettings) -> AuthInspectionResult {
        do {
            let credential = try resolveCredential(settings: settings)
            switch credential {
            case .openAIAPIKey(let apiKey, let baseURL, let source, _, let providerLabel):
                let masked = apiKey == "local-no-key" ? "无需 Key (离线本地)" : maskSecret(apiKey)
                let summaryPrefix = providerLabel.map { "\($0) (\(source))" } ?? source
                return AuthInspectionResult(
                    isValid: true,
                    summary: "已就绪 · \(summaryPrefix)",
                    detail: "Key: \(masked) · Endpoint: \(baseURL)",
                    credential: credential
                )
            case .anthropicAPIKey(let apiKey, let baseURL, let source):
                return AuthInspectionResult(
                    isValid: true,
                    summary: "已就绪 · Claude (\(source))",
                    detail: "Key: \(maskSecret(apiKey)) · Endpoint: \(baseURL)",
                    credential: credential
                )
            case .geminiAPIKey(let apiKey, let baseURL, let source):
                return AuthInspectionResult(
                    isValid: true,
                    summary: "已就绪 · Gemini (\(source))",
                    detail: "Key: \(maskSecret(apiKey)) · Endpoint: \(baseURL)",
                    credential: credential
                )
            case .localMLX(let modelID):
                let cached = LocalMLXLLMEngine.isModelCachedLocally(modelID: modelID)
                let short = modelID.split(separator: "/").last.map(String.init) ?? modelID
                return AuthInspectionResult(
                    isValid: true,
                    summary: "已就绪 · 内置离线 MLX（零 Token 费用）",
                    detail: cached ? "本地已缓存 \(short)，100% 离线运行" : "首次调用将自动下载 \(short)",
                    credential: credential
                )
            case .codexOAuth(let oauth):
                var parts: [String] = []
                if let email = oauth.email { parts.append(email) }
                if let plan = oauth.planType { parts.append("Plan: \(plan)") }
                if let exp = oauth.expiresAt {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "MM-dd HH:mm"
                    parts.append(oauth.isExpired ? "Token 需刷新" : "有效期至 \(formatter.string(from: exp))")
                }
                let detail = parts.isEmpty ? "使用 ChatGPT Codex OAuth 凭证" : parts.joined(separator: " · ")
                return AuthInspectionResult(
                    isValid: true,
                    summary: "已读取本机 Codex Auth",
                    detail: detail,
                    credential: credential
                )
            }
        } catch {
            return AuthInspectionResult(
                isValid: false,
                summary: "未配置可用凭证",
                detail: error.localizedDescription,
                credential: nil
            )
        }
    }

    public func parseAuthFile(at rawPath: String, fallbackBaseURL: String = "https://api.openai.com/v1") throws -> ResolvedCredential {
        let expanded = expandPath(rawPath)
        guard FileManager.default.fileExists(atPath: expanded) else {
            throw AuthError.fileNotFound(rawPath)
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: expanded))
        return try parseAuthData(data, filePath: expanded, fallbackBaseURL: fallbackBaseURL)
    }

    public func parseAuthData(
        _ data: Data,
        filePath: String,
        fallbackBaseURL: String = "https://api.openai.com/v1"
    ) throws -> ResolvedCredential {
        // 1. Try JSON parsing first
        if let jsonObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // Check for explicit API key fields (top-level or nested under openai)
            let apiKeyKeys = ["OPENAI_API_KEY", "openai_api_key", "api_key", "apiKey", "token"]
            for key in apiKeyKeys {
                if let value = jsonObj[key] as? String {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        let baseURL = (jsonObj["OPENAI_BASE_URL"] as? String)
                            ?? (jsonObj["base_url"] as? String)
                            ?? (jsonObj["baseURL"] as? String)
                            ?? fallbackBaseURL
                        let fileName = (filePath as NSString).lastPathComponent
                        return .openAIAPIKey(
                            apiKey: trimmed,
                            baseURL: normalizeBaseURL(baseURL),
                            source: fileName
                        )
                    }
                }
            }

            if let openaiDict = jsonObj["openai"] as? [String: Any],
               let nestedKey = (openaiDict["api_key"] as? String) ?? (openaiDict["apiKey"] as? String),
               !nestedKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let baseURL = (openaiDict["base_url"] as? String) ?? fallbackBaseURL
                let fileName = (filePath as NSString).lastPathComponent
                return .openAIAPIKey(
                    apiKey: nestedKey.trimmingCharacters(in: .whitespacesAndNewlines),
                    baseURL: normalizeBaseURL(baseURL),
                    source: fileName
                )
            }

            // Check for Codex ChatGPT OAuth tokens structure (~/.codex/auth.json)
            if let tokens = jsonObj["tokens"] as? [String: Any],
               let accessToken = tokens["access_token"] as? String,
               !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let refreshToken = tokens["refresh_token"] as? String
                let idToken = tokens["id_token"] as? String
                let accountID = tokens["account_id"] as? String
                let provenance = tokens["oauth_provenance"] as? [String: Any]
                let clientID = (provenance?["client_id"] as? String) ?? CodexOAuthCredential.defaultClientID
                let issuer = (provenance?["issuer"] as? String) ?? CodexOAuthCredential.defaultIssuer
                let lastRefresh = jsonObj["last_refresh"] as? String

                let claims = decodeJWTClaims(idToken ?? accessToken)
                let accessClaims = decodeJWTClaims(accessToken)
                let email = (claims?["email"] as? String)
                    ?? ((claims?["https://api.openai.com/profile"] as? [String: Any])?["email"] as? String)
                let authInfo = (claims?["https://api.openai.com/auth"] as? [String: Any])
                    ?? (accessClaims?["https://api.openai.com/auth"] as? [String: Any])
                let planType = authInfo?["chatgpt_plan_type"] as? String
                let resolvedAccountID = accountID ?? (authInfo?["chatgpt_account_id"] as? String)

                var expiresAt: Date? = nil
                if let exp = accessClaims?["exp"] as? TimeInterval {
                    expiresAt = Date(timeIntervalSince1970: exp)
                } else if let expInt = accessClaims?["exp"] as? Int {
                    expiresAt = Date(timeIntervalSince1970: TimeInterval(expInt))
                }

                return .codexOAuth(CodexOAuthCredential(
                    accessToken: accessToken.trimmingCharacters(in: .whitespacesAndNewlines),
                    refreshToken: refreshToken,
                    idToken: idToken,
                    accountID: resolvedAccountID,
                    clientID: clientID,
                    issuer: issuer,
                    authFilePath: filePath,
                    lastRefresh: lastRefresh,
                    email: email,
                    planType: planType,
                    expiresAt: expiresAt
                ))
            }

            throw AuthError.invalidAuthFile("JSON 中未找到 OPENAI_API_KEY 或 tokens.access_token 字段。")
        }

        // 2. Try .env / plain text key format
        if let text = String(data: data, encoding: .utf8) {
            for rawLine in text.components(separatedBy: .newlines) {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                if line.isEmpty || line.hasPrefix("#") { continue }
                if line.hasPrefix("OPENAI_API_KEY=") || line.hasPrefix("export OPENAI_API_KEY=") {
                    let keyPart = line.components(separatedBy: "=").dropFirst().joined(separator: "=")
                        .trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                    if !keyPart.isEmpty {
                        let fileName = (filePath as NSString).lastPathComponent
                        return .openAIAPIKey(apiKey: keyPart, baseURL: fallbackBaseURL, source: fileName)
                    }
                }
                if line.hasPrefix("sk-") && line.count > 20 {
                    let fileName = (filePath as NSString).lastPathComponent
                    return .openAIAPIKey(apiKey: line, baseURL: fallbackBaseURL, source: fileName)
                }
            }
        }

        throw AuthError.invalidAuthFile("无法识别文件格式，支持 Codex auth.json、包含 api_key 的 JSON 或 .env 文件。")
    }

    public func refreshCodexOAuth(_ current: CodexOAuthCredential) async throws -> CodexOAuthCredential {
        // First re-read from disk in case Codex CLI already refreshed the token
        if let diskCred = try? parseAuthFile(at: current.authFilePath),
           case .codexOAuth(let freshDisk) = diskCred,
           freshDisk.accessToken != current.accessToken,
           !freshDisk.isExpired {
            return freshDisk
        }

        guard let refreshToken = current.refreshToken, !refreshToken.isEmpty else {
            throw AuthError.refreshFailed("本地 auth.json 缺少 refresh_token，请运行 `codex login` 重新登录。")
        }

        let issuerBase = current.issuer.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(issuerBase)/oauth/token") else {
            throw AuthError.refreshFailed("无效的 OAuth issuer URL。")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20

        let body: [String: Any] = [
            "client_id": current.clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "scope": "openid profile email"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw AuthError.refreshFailed("HTTP \(status)，建议重新运行 `codex login` 刷新本机登录态。")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newAccess = json["access_token"] as? String, !newAccess.isEmpty else {
            throw AuthError.refreshFailed("OAuth 响应缺少 access_token。")
        }

        let newRefresh = (json["refresh_token"] as? String) ?? refreshToken
        let newIDToken = (json["id_token"] as? String) ?? current.idToken

        // Atomically persist rotated tokens back to auth.json so Codex CLI stays in sync
        persistRefreshedCodexTokens(
            at: current.authFilePath,
            accessToken: newAccess,
            refreshToken: newRefresh,
            idToken: newIDToken
        )

        if let reloaded = try? parseAuthFile(at: current.authFilePath),
           case .codexOAuth(let updated) = reloaded {
            return updated
        }

        var updated = current
        updated.accessToken = newAccess
        updated.refreshToken = newRefresh
        updated.idToken = newIDToken
        return updated
    }

    private func persistRefreshedCodexTokens(
        at path: String,
        accessToken: String,
        refreshToken: String,
        idToken: String?
    ) {
        let url = URL(fileURLWithPath: path)
        guard let raw = try? Data(contentsOf: url),
              var root = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any],
              var tokens = root["tokens"] as? [String: Any] else {
            return
        }
        tokens["access_token"] = accessToken
        tokens["refresh_token"] = refreshToken
        if let idToken {
            tokens["id_token"] = idToken
        }
        root["tokens"] = tokens
        root["last_refresh"] = ISO8601DateFormatter().string(from: Date())
        if let updatedData = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) {
            try? updatedData.write(to: url, options: .atomic)
        }
    }

    public func normalizeBaseURL(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "https://api.openai.com/v1"
        }
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed
    }

    public func maskSecret(_ secret: String) -> String {
        if secret.count <= 10 {
            return String(repeating: "•", count: max(4, secret.count))
        }
        let prefix = secret.prefix(6)
        let suffix = secret.suffix(4)
        return "\(prefix)••••\(suffix)"
    }

    public func decodeJWTClaims(_ jwt: String?) -> [String: Any]? {
        guard let jwt else { return nil }
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }
}
