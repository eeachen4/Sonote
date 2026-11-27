import SwiftUI
import AppKit
import AVFoundation
import Speech
import UniformTypeIdentifiers
import SonoteCore

/// Ultra-clean adaptive 2-column Settings window:
/// left minimalist navigation rail + right editorial card canvas, modularized per tab.
struct SettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var theme = ThemeManager.shared

    enum SectionTab: String, CaseIterable, Identifiable {
        case general = "general"
        case aiModel = "aiModel"
        case audio = "audio"
        case voiceprint = "voiceprint"
        case templates = "templates"
        case detection = "detection"
        case syncBackup = "syncBackup"

        var id: String { rawValue }

        @MainActor
        var title: String {
            switch self {
            case .general: return L("通用", "General")
            case .aiModel: return L("AI 模型", "AI Models")
            case .audio: return L("音频与转写", "Audio & ASR")
            case .voiceprint: return L("声纹库", "Voiceprints")
            case .templates: return L("纪要模板", "Templates")
            case .detection: return L("自动检测", "Detection")
            case .syncBackup: return L("协作与备份", "Sync & Backup")
            }
        }

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .aiModel: return "sparkles"
            case .audio: return "waveform"
            case .voiceprint: return "person.wave.2"
            case .templates: return "doc.text"
            case .detection: return "bell.badge"
            case .syncBackup: return "paperplane"
            }
        }

        @MainActor
        var subtitle: String {
            switch self {
            case .general: return L("设置界面语言、浅色/深色主题、主题色、阅读字号与窗口行为", "Customize interface language, light/dark appearance, accent color, typography & window behavior")
            case .aiModel: return L("配置 DeepSeek / 通义千问等国产与国际大模型，或 App 内置离线 MLX 引擎（密钥加密存入钥匙串）", "Configure DeepSeek, Qwen, global cloud LLMs, or built-in offline Apple Silicon MLX models")
            case .audio: return L("管理本机用户名、双轨采集、本地语音转写、人声降噪与存储空间", "Manage speaker name, dual-track capture, local ASR, neural denoising & audio storage")
            case .voiceprint: return L("本地 ECAPA-TDNN 192 维声纹库，支持跨会议自动识别真实姓名", "Offline 192-dim ECAPA-TDNN voiceprint library for cross-meeting speaker recognition")
            case .templates: return L("设置默认纪要风格、会中实时提炼频率与团队自定义 Prompt 模板", "Configure default summary template, live cadence & custom prompt templates")
            case .detection: return L("控制开机自启、会议自动弹窗提醒、日历联动与系统级全局快捷键", "Control auto-launch, meeting detection prompts, Calendar sync & global hotkeys")
            case .syncBackup: return L("配置飞书 / 钉钉 / Notion Webhook 一键推送与全库备份迁移", "Configure Feishu / DingTalk / Notion Webhooks and full-library archive backup")
            }
        }
    }

    @State var selectedTab: SectionTab = .general
    @State var isTestingConnection = false
    @State var testResult: GPTConnectionTestResult?
    @State var discoveredAuthFiles: [String] = []
    @State var discoveredCodexModels: [String] = []
    @State var micStatus: AVAuthorizationStatus = MicrophoneCapture.authorizationStatus()
    @State var speechStatus: SFSpeechRecognizerAuthorizationStatus = SFSpeechRecognizer.authorizationStatus()
    @State var calendarAuthorized: Bool = CalendarContextService.shared.isAuthorized()
    @State var launchAtLogin: Bool = LaunchAtLoginService.isEnabled

    @State var showAdvancedMLX: Bool = false
    @State var showAppMonitoringList: Bool = false
    @State var newIgnoredBundleID: String = ""
    @State var newVoiceprintName: String = ""
    @State var newVoiceprintRole: String = ""
    @State var newVoiceprintIsSelf: Bool = false
    @State var newGlossaryTerm: String = ""
    @State var newTemplateName: String = ""
    @State var newTemplateGuidance: String = ""
    @State var webhookTestFeedback: String? = nil
    @State var includeAudioInBackup: Bool = false
    @State var backupFeedback: String? = nil
    @State var isCheckingUpdates: Bool = false
    @State var updateResult: AppUpdateCheckResult? = nil
    @State var updateError: String? = nil

    var body: some View {
        HStack(spacing: 0) {
            sidebarRail

            Rectangle()
                .fill(AppTheme.divider)
                .frame(width: 1)

            rightDetailCanvas
        }
        .frame(width: 780, height: 600)
        .background(AppTheme.canvasWhite)
        .tint(AppTheme.brandPrimary)
        .preferredColorScheme(theme.preferredColorScheme)
        .onAppear {
            discoveredAuthFiles = AuthManager.shared.discoverExistingAuthFiles()
            refreshCodexModels()
            refreshPermissions()
            appState.refreshAudioStorageStats()
        }
        .onChange(of: appState.settings.authFilePath) { _, _ in
            refreshCodexModels()
        }
    }

    // MARK: - Minimalist Left Navigation Rail

    private var sidebarRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(AppTheme.brandSoftFill)
                        .frame(width: 24, height: 24)
                    Image(systemName: "waveform")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(AppTheme.brandPrimary)
                }
                Text(L("Sonote 设置", "Settings"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Text("v\(UpdateCheckerService.installedVersion)")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppTheme.textMuted)
            }
            .padding(.horizontal, 16)
            .padding(.top, 36)
            .padding(.bottom, 16)

            VStack(spacing: 4) {
                ForEach(SectionTab.allCases) { tab in
                    let isSelected = selectedTab == tab
                    Button {
                        withAnimation(.easeInOut(duration: 0.14)) {
                            selectedTab = tab
                        }
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? AppTheme.brandPrimary : AppTheme.textSecondary)
                                .frame(width: 18)
                            Text(tab.title)
                                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? AppTheme.brandPrimary : AppTheme.textPrimary)
                            Spacer()
                            if tab == .voiceprint && !appState.voiceprints.isEmpty {
                                Text("\(appState.voiceprints.count)")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(isSelected ? AppTheme.brandPrimary : AppTheme.textMuted)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(isSelected ? AppTheme.elevatedSurface.opacity(0.9) : AppTheme.neutralPill))
                            }
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8.5)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(isSelected ? AppTheme.brandSoftFill : Color.clear)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            // Quiet bottom status summary card
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(appState.authInspection.isValid ? AppTheme.successGreen : AppTheme.warningAmber)
                        .frame(width: 6.5, height: 6.5)
                    Text(appState.settings.authMode.displayName)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)
                }
                Text(
                    appState.todayTokenUsage.isEmpty
                        ? L("今日暂无 Token 消耗", "No tokens used today")
                        : (theme.isEnglish
                            ? "Today \(appState.todayTokenUsage.formattedCompact) tokens"
                            : "今日 \(appState.todayTokenUsage.formattedCompact) tokens")
                )
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppTheme.elevatedSurface.opacity(0.9))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(AppTheme.subtleBorder, lineWidth: 1)
            )
            .padding(12)
        }
        .frame(width: 186)
        .background(AppTheme.leftPaneBg)
    }

    // MARK: - Right Adaptive Detail Canvas

    private var rightDetailCanvas: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedTab.title)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(selectedTab.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding(.bottom, 2)

                switch selectedTab {
                case .general:
                    generalPage
                case .aiModel:
                    aiModelPage
                case .audio:
                    audioTranscriptionPage
                case .voiceprint:
                    voiceprintLibraryPage
                case .templates:
                    templatesPage
                case .detection:
                    detectionPage
                case .syncBackup:
                    syncBackupPage
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 30)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppTheme.canvasWhite)
    }

    // MARK: - Shared Helpers & Actions

    func fieldLabel(_ title: String, hint: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.textPrimary)
            if let hint, !hint.isEmpty {
                Text(hint)
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }

    func cleanMenuLabel(_ text: String) -> some View {
        HStack(spacing: 5) {
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(AppTheme.textMuted)
        }
        .foregroundStyle(AppTheme.textPrimary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5.5)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppTheme.softCardBg))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(AppTheme.subtleBorder, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    func tokenStatTile(label: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.textSecondary)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppTheme.textPrimary)
            Text(detail)
                .font(.system(size: 10.5))
                .foregroundStyle(AppTheme.textMuted)
                .lineLimit(1)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(AppTheme.softCardBg))
    }

    func cleanPermissionRow(
        title: String,
        detail: String,
        status: Bool?,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(status == true ? AppTheme.successGreen : (status == false ? AppTheme.warningAmber : AppTheme.brandPrimary))
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppTheme.textPrimary)
                    if let status {
                        Text(status ? L("已授权", "Granted") : L("未授权", "Not Granted"))
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(status ? AppTheme.successGreen : AppTheme.warningAmber)
                    }
                }
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Spacer()
            CleanSmallButton(buttonTitle, action: action)
        }
    }

    func shortEngineName(_ engine: TranscriptionEngine) -> String {
        switch engine {
        case .mlxQwen3ASR: return L("MLX Qwen3-ASR 本地（推荐）", "MLX Qwen3-ASR Local (Recommended)")
        case .appleSpeech: return L("Apple 本机实时识别", "Apple Speech On-Device")
        case .openAITranscribe: return L("OpenAI 转写 API", "OpenAI Transcribe API")
        }
    }

    var selectedMLXPresetShortLabel: String {
        if let match = MLXQwen3ModelPreset.all.first(where: { $0.repoID == appState.settings.mlxQwen3ModelID }) {
            return "\(match.repoID.split(separator: "/").last ?? "") · \(match.footprintHint)"
        }
        return appState.settings.mlxQwen3ModelID.split(separator: "/").last.map(String.init) ?? appState.settings.mlxQwen3ModelID
    }

    var mlxCacheSummary: String {
        let cached = MLXQwen3ASREngine.isModelCachedLocally(modelID: appState.settings.mlxQwen3ModelID)
        if appState.mlxModelState == .idle && cached {
            return L("本地已缓存权重，开始录音即可秒加载", "Weights cached locally for instant start")
        }
        return appState.mlxModelState.statusText
    }

    func addGlossaryTerm() {
        let parts = newGlossaryTerm
            .components(separatedBy: CharacterSet(charactersIn: ",，、;；"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for part in parts where !appState.settings.glossaryTerms.contains(part) {
            appState.settings.glossaryTerms.append(part)
        }
        newGlossaryTerm = ""
    }

    func pickAuthFile() {
        let panel = NSOpenPanel()
        panel.title = L("选择本地 Auth 凭证文件（JSON / .env）", "Select Local Auth File (JSON / .env)")
        panel.showsHiddenFiles = true
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        if panel.runModal() == .OK, let url = panel.url {
            appState.settings.authFilePath = url.path
        }
    }

    func pickAudioFileForVoiceprint() {
        let panel = NSOpenPanel()
        panel.title = L("选择包含该说话人清晰人声的音频文件（建议 3~30 秒）", "Select Clear Speech Sample (3–30s recommended)")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio, .mpeg4Audio, .mp3, .wav, .movie, .mpeg4Movie]
        if panel.runModal() == .OK, let url = panel.url {
            let name = newVoiceprintName.trimmingCharacters(in: .whitespacesAndNewlines)
            let role = newVoiceprintRole.trimmingCharacters(in: .whitespacesAndNewlines)
            let isSelf = newVoiceprintIsSelf
            Task {
                await appState.enrollVoiceprintFromAudioFile(url: url, name: name, role: role, isSelf: isSelf)
                if appState.voiceprints.contains(where: { $0.name == name }) {
                    newVoiceprintName = ""
                    newVoiceprintRole = ""
                    newVoiceprintIsSelf = false
                }
            }
        }
    }

    func runConnectionTest() {
        isTestingConnection = true
        testResult = nil
        let snapshot = appState.settings
        Task {
            let result = await GPTClient.shared.testConnection(settings: snapshot)
            await MainActor.run {
                self.testResult = result
                self.isTestingConnection = false
            }
        }
    }

    func checkForAppUpdates() {
        guard !isCheckingUpdates else { return }
        isCheckingUpdates = true
        updateError = nil
        updateResult = nil
        Task {
            do {
                let res = try await UpdateCheckerService.checkLatestRelease()
                await MainActor.run {
                    self.updateResult = res
                    self.isCheckingUpdates = false
                }
            } catch {
                await MainActor.run {
                    self.updateError = error.localizedDescription
                    self.isCheckingUpdates = false
                }
            }
        }
    }

    var codexModelOptions: [String] {
        var list = discoveredCodexModels.isEmpty ? AppSettings.suggestedCodexModels : discoveredCodexModels
        let current = appState.settings.codexModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !current.isEmpty && !list.contains(current) {
            list.insert(current, at: 0)
        }
        return list
    }

    func refreshCodexModels() {
        let catalog = AuthManager.shared.discoverLocalCodexCatalog(authFilePath: appState.settings.authFilePath)
        discoveredCodexModels = catalog.availableModels
        if appState.settings.codexModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let def = catalog.defaultModel {
            appState.settings.codexModel = def
        }
    }

    func refreshPermissions() {
        micStatus = MicrophoneCapture.authorizationStatus()
        speechStatus = SFSpeechRecognizer.authorizationStatus()
        calendarAuthorized = CalendarContextService.shared.isAuthorized()
        launchAtLogin = LaunchAtLoginService.isEnabled
    }
}
