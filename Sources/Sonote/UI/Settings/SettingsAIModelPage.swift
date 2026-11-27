import SwiftUI
import SonoteCore

// MARK: - Page 1: AI Models & Providers (Global, Chinese Domestic & Built-in Offline MLX)

extension SettingsView {

    var aiModelPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(title: L("模型提供方", "AI Provider")) {
                VStack(alignment: .leading, spacing: 12) {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 4),
                        spacing: 7
                    ) {
                        ForEach(AuthMode.allCases) { mode in
                            let active = appState.settings.authMode == mode
                            Button {
                                appState.settings.authMode = mode
                            } label: {
                                Text(mode.displayName)
                                    .font(.system(size: 11.5, weight: active ? .semibold : .regular))
                                    .foregroundStyle(active ? AppTheme.brandPrimary : AppTheme.textSecondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 7.5)
                                    .padding(.horizontal, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(active ? AppTheme.brandSoftFill : AppTheme.softCardBg)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .strokeBorder(active ? AppTheme.brandPrimary.opacity(0.35) : Color.clear, lineWidth: 1)
                                    )
                                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack(spacing: 9) {
                        Image(systemName: appState.authInspection.isValid ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(appState.authInspection.isValid ? AppTheme.successGreen : AppTheme.warningAmber)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(appState.authInspection.summary)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                            Text(appState.authInspection.detail)
                                .font(.system(size: 11))
                                .foregroundStyle(AppTheme.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        CleanSmallButton(L("刷新", "Refresh")) {
                            appState.refreshAuthInspection()
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(AppTheme.softCardBg))
                }
            }

            if appState.settings.authMode == .localAuthFile {
                SettingsCard(title: L("本机 Codex Auth 文件", "Local Codex Auth File")) {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            fieldLabel(L("Auth 文件路径", "Auth File Path"), hint: L("自动兼容 ~/.codex/auth.json、JSON 与 .env", "Supports ~/.codex/auth.json, JSON & .env"))
                            HStack(spacing: 8) {
                                CleanInputBox(placeholder: "~/.codex/auth.json", text: $appState.settings.authFilePath)
                                CleanSmallButton(L("选择文件...", "Browse...")) { pickAuthFile() }
                            }
                            if !discoveredAuthFiles.isEmpty {
                                HStack(spacing: 6) {
                                    Text(L("已探测：", "Detected:"))
                                        .font(.system(size: 11))
                                        .foregroundStyle(AppTheme.textMuted)
                                    ForEach(discoveredAuthFiles, id: \.self) { path in
                                        CleanChipButton(path, selected: appState.settings.authFilePath == path) {
                                            appState.settings.authFilePath = path
                                        }
                                    }
                                }
                            }
                        }

                        Divider().overlay(AppTheme.divider)

                        HStack {
                            fieldLabel(L("使用模型", "Model"), hint: L("自动读取本地 models_cache.json", "Auto-reads local models_cache.json"))
                            Spacer()
                            CleanMenuPicker(
                                title: appState.settings.codexModel.isEmpty ? L("选择模型", "Select Model") : appState.settings.codexModel,
                                options: codexModelOptions,
                                selection: $appState.settings.codexModel
                            )
                        }

                        CleanInputBox(placeholder: L("或手动输入自定义模型 ID", "Or enter custom model ID"), text: $appState.settings.codexModel)
                    }
                }
            } else if appState.settings.authMode == .apiKey {
                SettingsCard(title: L("OpenAI / 兼容接口 / 本地零成本模型", "OpenAI / Compatible / Local Server")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 6) {
                            Text(L("一键预设", "Presets"))
                                .font(.system(size: 11.5))
                                .foregroundStyle(AppTheme.textSecondary)
                            CleanChipButton(L("OpenAI 官方", "OpenAI"), selected: appState.settings.apiBaseURL.contains("api.openai.com")) {
                                appState.settings.apiBaseURL = "https://api.openai.com/v1"
                                appState.settings.model = "gpt-5.4"
                            }
                            CleanChipButton(L("本地 Ollama", "Local Ollama"), selected: appState.settings.apiBaseURL.contains("11434")) {
                                appState.settings.apiBaseURL = "http://localhost:11434/v1"
                                appState.settings.model = "qwen3:14b"
                            }
                            CleanChipButton(L("本地 MLX Server", "Local MLX Server"), selected: appState.settings.apiBaseURL.contains("8080")) {
                                appState.settings.apiBaseURL = "http://localhost:8080/v1"
                                appState.settings.model = "mlx-community/Qwen3-8B-4bit"
                            }
                        }

                        VStack(alignment: .leading, spacing: 5) {
                            fieldLabel("API Key", hint: L("加密存于 macOS 钥匙串；本地 localhost 服务可留空", "Stored in macOS Keychain; optional for localhost"))
                            CleanSecureBox(placeholder: "sk-...", text: $appState.settings.apiKey)
                        }

                        VStack(alignment: .leading, spacing: 5) {
                            fieldLabel("Base URL")
                            CleanInputBox(placeholder: "https://api.openai.com/v1", text: $appState.settings.apiBaseURL)
                        }

                        HStack {
                            fieldLabel(L("模型 ID", "Model ID"))
                            Spacer()
                            CleanMenuPicker(
                                title: appState.settings.model.isEmpty ? L("选择模型", "Select Model") : appState.settings.model,
                                options: AppSettings.suggestedAPIModels,
                                selection: $appState.settings.model
                            )
                        }
                        CleanInputBox(placeholder: L("自定义模型 ID（如 gpt-5.4 / qwen3:14b）", "Custom model ID (e.g. gpt-5.4 / qwen3:14b)"), text: $appState.settings.model)
                    }
                }
            } else if appState.settings.authMode == .deepSeek {
                SettingsCard(
                    title: L("DeepSeek（深度求索）", "DeepSeek API"),
                    subtitle: L("原生支持 DeepSeek-V3 / R1 推理模型、缓存命中统计与 <think> 自动过滤", "Native DeepSeek-V3 / R1 support with cache-hit accounting & thinking-tag filtering")
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            fieldLabel("DeepSeek API Key", hint: L("加密存于 macOS 钥匙串；留空时自动读取 DEEPSEEK_API_KEY", "Stored in macOS Keychain; falls back to DEEPSEEK_API_KEY"))
                            CleanSecureBox(placeholder: "sk-...", text: $appState.settings.deepSeekAPIKey)
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            fieldLabel("Base URL")
                            CleanInputBox(placeholder: "https://api.deepseek.com/v1", text: $appState.settings.deepSeekBaseURL)
                        }
                        HStack {
                            fieldLabel(L("DeepSeek 模型", "DeepSeek Model"), hint: L("deepseek-chat (V3 极速) / deepseek-reasoner (R1 深度推理)", "deepseek-chat (V3) / deepseek-reasoner (R1)"))
                            Spacer()
                            CleanMenuPicker(
                                title: appState.settings.deepSeekModel.isEmpty ? L("选择模型", "Select Model") : appState.settings.deepSeekModel,
                                options: AppSettings.suggestedDeepSeekModels,
                                selection: $appState.settings.deepSeekModel
                            )
                        }
                        CleanInputBox(placeholder: L("或输入自定义模型 ID（如 deepseek-chat）", "Or enter custom model ID (e.g. deepseek-chat)"), text: $appState.settings.deepSeekModel)
                    }
                }
            } else if appState.settings.authMode == .qwenDashScope {
                SettingsCard(
                    title: L("通义千问 Qwen（阿里云百炼 DashScope）", "Alibaba Qwen (DashScope)"),
                    subtitle: L("原生支持 Qwen3 / Qwen-Max / Qwen-Plus / Qwen-Long 超长上下文会议纪要", "Native Qwen3 / Qwen-Max / Qwen-Plus / Qwen-Long support")
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 6) {
                            Text(L("接入地域", "Region"))
                                .font(.system(size: 11.5))
                                .foregroundStyle(AppTheme.textSecondary)
                            CleanChipButton(L("中国北京（默认）", "Beijing (CN)"), selected: appState.settings.qwenBaseURL.contains("dashscope.aliyuncs.com")) {
                                appState.settings.qwenBaseURL = "https://dashscope.aliyuncs.com/compatible-mode/v1"
                            }
                            CleanChipButton(L("新加坡（国际）", "Singapore (Intl)"), selected: appState.settings.qwenBaseURL.contains("dashscope-intl.aliyuncs.com")) {
                                appState.settings.qwenBaseURL = "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"
                            }
                        }

                        VStack(alignment: .leading, spacing: 5) {
                            fieldLabel("DashScope API Key", hint: L("加密存于 macOS 钥匙串；留空时自动读取 DASHSCOPE_API_KEY", "Stored in macOS Keychain; falls back to DASHSCOPE_API_KEY"))
                            CleanSecureBox(placeholder: "sk-...", text: $appState.settings.qwenAPIKey)
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            fieldLabel("Base URL")
                            CleanInputBox(placeholder: "https://dashscope.aliyuncs.com/compatible-mode/v1", text: $appState.settings.qwenBaseURL)
                        }
                        HStack {
                            fieldLabel(L("通义千问模型", "Qwen Model"), hint: L("日常推荐 qwen-plus，超长会议推荐 qwen-long", "qwen-plus for daily use, qwen-long for long meetings"))
                            Spacer()
                            CleanMenuPicker(
                                title: appState.settings.qwenModel.isEmpty ? L("选择模型", "Select Model") : appState.settings.qwenModel,
                                options: AppSettings.suggestedQwenModels,
                                selection: $appState.settings.qwenModel
                            )
                        }
                        CleanInputBox(placeholder: L("或输入自定义模型 ID（如 qwen3-max / qwq-plus）", "Or enter custom model ID (e.g. qwen3-max / qwq-plus)"), text: $appState.settings.qwenModel)
                    }
                }
            } else if appState.settings.authMode == .domesticCloud {
                let preset = appState.settings.domesticProvider
                SettingsCard(
                    title: L("更多国产大模型平台", "More Chinese LLM Providers"),
                    subtitle: L("一键切换 Kimi、智谱 GLM、豆包火山方舟、硅基流动、MiniMax 与腾讯混元", "One-click presets for Kimi, Zhipu GLM, Doubao Ark, SiliconFlow, MiniMax & Tencent Hunyuan")
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3),
                            spacing: 6
                        ) {
                            ForEach(DomesticProviderPreset.allCases) { item in
                                let active = appState.settings.domesticProvider == item
                                Button {
                                    appState.settings.domesticProvider = item
                                    appState.settings.domesticBaseURL = item.defaultBaseURL
                                    appState.settings.domesticModel = item.defaultModel
                                } label: {
                                    Text(item.shortName)
                                        .font(.system(size: 11.5, weight: active ? .semibold : .regular))
                                        .foregroundStyle(active ? AppTheme.brandPrimary : AppTheme.textSecondary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                        .background(
                                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                .fill(active ? AppTheme.brandSoftFill : AppTheme.softCardBg)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                .strokeBorder(active ? AppTheme.brandPrimary.opacity(0.35) : Color.clear, lineWidth: 1)
                                        )
                                        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        VStack(alignment: .leading, spacing: 5) {
                            fieldLabel("\(preset.shortName) API Key", hint: L("加密存于 macOS 钥匙串；留空自动读取 \(preset.envVarName)", "Stored in macOS Keychain; falls back to \(preset.envVarName)"))
                            CleanSecureBox(placeholder: "API Key...", text: $appState.settings.domesticAPIKey)
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            fieldLabel("Base URL")
                            CleanInputBox(placeholder: preset.defaultBaseURL, text: $appState.settings.domesticBaseURL)
                        }
                        HStack {
                            fieldLabel(L("使用模型", "Model ID"), hint: preset.modelHint)
                            Spacer()
                            CleanMenuPicker(
                                title: appState.settings.domesticModel.isEmpty ? L("选择模型", "Select Model") : appState.settings.domesticModel,
                                options: preset.suggestedModels,
                                selection: $appState.settings.domesticModel
                            )
                        }
                        CleanInputBox(placeholder: preset.defaultModel, text: $appState.settings.domesticModel)
                    }
                }
            } else if appState.settings.authMode == .anthropicClaude {
                SettingsCard(title: "Anthropic Claude API") {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            fieldLabel("Claude API Key", hint: L("加密存于 macOS 钥匙串", "Stored in macOS Keychain"))
                            CleanSecureBox(placeholder: "sk-ant-...", text: $appState.settings.claudeAPIKey)
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            fieldLabel("Base URL")
                            CleanInputBox(placeholder: "https://api.anthropic.com/v1", text: $appState.settings.claudeBaseURL)
                        }
                        HStack {
                            fieldLabel(L("Claude 模型", "Claude Model"))
                            Spacer()
                            CleanMenuPicker(
                                title: appState.settings.claudeModel.isEmpty ? L("选择模型", "Select Model") : appState.settings.claudeModel,
                                options: AppSettings.suggestedClaudeModels,
                                selection: $appState.settings.claudeModel
                            )
                        }
                        CleanInputBox(placeholder: L("或自定义 Claude 模型 ID", "Or custom Claude model ID"), text: $appState.settings.claudeModel)
                    }
                }
            } else if appState.settings.authMode == .googleGemini {
                SettingsCard(title: "Google Gemini API") {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            fieldLabel("Gemini API Key", hint: L("加密存于 macOS 钥匙串", "Stored in macOS Keychain"))
                            CleanSecureBox(placeholder: "AIza...", text: $appState.settings.geminiAPIKey)
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            fieldLabel("Base URL")
                            CleanInputBox(placeholder: "https://generativelanguage.googleapis.com/v1beta", text: $appState.settings.geminiBaseURL)
                        }
                        HStack {
                            fieldLabel(L("Gemini 模型", "Gemini Model"))
                            Spacer()
                            CleanMenuPicker(
                                title: appState.settings.geminiModel.isEmpty ? L("选择模型", "Select Model") : appState.settings.geminiModel,
                                options: AppSettings.suggestedGeminiModels,
                                selection: $appState.settings.geminiModel
                            )
                        }
                        CleanInputBox(placeholder: L("或自定义 Gemini 模型 ID", "Or custom Gemini model ID"), text: $appState.settings.geminiModel)
                    }
                }
            } else if appState.settings.authMode == .localMLX {
                SettingsCard(title: L("内置离线 MLX 大模型（无需外部 Ollama，零 Token 成本）", "Built-in Offline MLX LLM (No Ollama, Zero Token Cost)")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            fieldLabel(
                                L("本地 Qwen2.5 模型", "Local Qwen2.5 Model"),
                                hint: LocalMLXLLMEngine.isModelCachedLocally(modelID: appState.settings.localMLXLLMModelID)
                                    ? L("本地已缓存权重，完全离线可用", "Weights cached locally — 100% offline ready")
                                    : L("首次运行将通过 HuggingFace 镜像自动下载", "Downloads automatically via HuggingFace on first use")
                            )
                            Spacer()
                            CleanMenuPicker(
                                title: appState.settings.localMLXLLMModelID.split(separator: "/").last.map(String.init) ?? L("选择模型", "Select Model"),
                                options: AppSettings.suggestedLocalMLXLLMModels,
                                selection: $appState.settings.localMLXLLMModelID
                            )
                        }
                        CleanInputBox(placeholder: L("或输入自定义 Qwen2.5 MLX Repo / 本地目录", "Or enter custom Qwen2.5 MLX Repo / local path"), text: $appState.settings.localMLXLLMModelID)

                        HStack(spacing: 8) {
                            CleanPrimaryButton(
                                title: appState.isPreloadingLocalLLM ? L("加载中...", "Loading...") : L("预下载 / 加载模型", "Preload Model"),
                                icon: "arrow.down.circle",
                                disabled: appState.isPreloadingLocalLLM
                            ) {
                                Task { await appState.preloadLocalMLXLLM() }
                            }
                            CleanSmallButton(L("释放显存", "Unload GPU")) {
                                Task { await appState.unloadLocalMLXLLM() }
                            }
                            Spacer()
                        }
                    }
                }
            }

            // Connectivity Test + Token Ledger Card
            SettingsCard(title: L("连通性测试与 Token 消耗", "Connection Test & Token Usage")) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        CleanPrimaryButton(
                            title: isTestingConnection ? L("测试中...", "Testing...") : L("测试 AI 连接", "Test Connection"),
                            icon: "bolt.horizontal.fill",
                            disabled: isTestingConnection
                        ) {
                            runConnectionTest()
                        }

                        if let testResult {
                            HStack(spacing: 5) {
                                Image(systemName: testResult.success ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                    .foregroundStyle(testResult.success ? AppTheme.successGreen : AppTheme.recordingRed)
                                Text("\(testResult.message) (\(testResult.latencyMs)ms)")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(testResult.success ? AppTheme.textPrimary : AppTheme.recordingRed)
                                    .lineLimit(2)
                            }
                        }
                        Spacer()
                    }

                    Divider().overlay(AppTheme.divider)

                    HStack(spacing: 12) {
                        tokenStatTile(
                            label: L("今日累计", "Today"),
                            value: appState.todayTokenUsage.isEmpty ? "0" : "\(appState.todayTokenUsage.formattedCompact) tokens",
                            detail: appState.todayTokenUsage.isEmpty ? L("按实际调用日期统计", "Tracked per day") : appState.todayTokenUsage.detailedSummary
                        )
                        tokenStatTile(
                            label: L("全部历史", "All Time"),
                            value: appState.totalTokenUsage.isEmpty ? "0" : "\(appState.totalTokenUsage.formattedCompact) tokens",
                            detail: appState.totalTokenUsage.isEmpty ? L("暂无历史消耗", "No usage yet") : appState.totalTokenUsage.detailedSummary
                        )
                    }

                    if !appState.totalTokenUsage.isEmpty {
                        HStack {
                            Spacer()
                            Button(L("重置统计", "Reset Stats")) {
                                appState.resetAllTokenUsage()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11.5))
                            .foregroundStyle(AppTheme.recordingRed.opacity(0.85))
                            .contentShape(Rectangle())
                        }
                    }
                }
            }
        }
    }
}
