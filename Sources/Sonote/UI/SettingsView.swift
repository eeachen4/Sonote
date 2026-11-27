import SwiftUI
import AppKit
import AVFoundation
import Speech
import UniformTypeIdentifiers
import SonoteCore

/// Ultra-clean Doubao Work–inspired 2-column Settings window:
/// left minimalist navigation rail + right pure-white editorial card canvas.
struct SettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var theme = ThemeManager.shared

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
            case .aiModel: return L("配置云端大模型或 App 内置离线 MLX 引擎（密钥加密存入钥匙串）", "Configure cloud LLMs or built-in offline Apple Silicon MLX models (secrets stored in Keychain)")
            case .audio: return L("管理本机用户名、双轨采集、本地语音转写、人声降噪与存储空间", "Manage speaker name, dual-track capture, local ASR, neural denoising & audio storage")
            case .voiceprint: return L("本地 ECAPA-TDNN 192 维声纹库，支持跨会议自动识别真实姓名", "Offline 192-dim ECAPA-TDNN voiceprint library for cross-meeting speaker recognition")
            case .templates: return L("设置默认纪要风格、会中实时提炼频率与团队自定义 Prompt 模板", "Configure default summary template, live cadence & custom prompt templates")
            case .detection: return L("控制开机自启、会议自动弹窗提醒、日历联动与系统级全局快捷键", "Control auto-launch, meeting detection prompts, Calendar sync & global hotkeys")
            case .syncBackup: return L("配置飞书 / 钉钉 / Notion Webhook 一键推送与全库备份迁移", "Configure Feishu / DingTalk / Notion Webhooks and full-library archive backup")
            }
        }
    }

    @State private var selectedTab: SectionTab = .general
    @State private var isTestingConnection = false
    @State private var testResult: GPTConnectionTestResult?
    @State private var discoveredAuthFiles: [String] = []
    @State private var discoveredCodexModels: [String] = []
    @State private var micStatus: AVAuthorizationStatus = MicrophoneCapture.authorizationStatus()
    @State private var speechStatus: SFSpeechRecognizerAuthorizationStatus = SFSpeechRecognizer.authorizationStatus()
    @State private var calendarAuthorized: Bool = CalendarContextService.shared.isAuthorized()
    @State private var launchAtLogin: Bool = LaunchAtLoginService.isEnabled

    @State private var showAdvancedMLX: Bool = false
    @State private var showAppMonitoringList: Bool = false
    @State private var newIgnoredBundleID: String = ""
    @State private var newVoiceprintName: String = ""
    @State private var newVoiceprintRole: String = ""
    @State private var newVoiceprintIsSelf: Bool = false
    @State private var newGlossaryTerm: String = ""
    @State private var newTemplateName: String = ""
    @State private var newTemplateGuidance: String = ""
    @State private var webhookTestFeedback: String? = nil
    @State private var includeAudioInBackup: Bool = false
    @State private var backupFeedback: String? = nil

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
                Text("v1.5")
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
                // Clean Editorial Page Header
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

    // MARK: - Page 0: 通用设置 (General: Language, Theme, Accent Color, Typography & Startup)

    private var generalPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Card 1: Appearance & Accent Theme
            SettingsCard(
                title: L("外观与主题", "Appearance & Theme"),
                subtitle: L("实时切换浅色、深色或跟随系统，并自定义全局主题强调色", "Switch Light, Dark, or Auto appearance and customize your global accent color in real time")
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    // 1.1 Appearance Mode Miniature Preview Cards
                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel(L("主题模式", "Appearance"))
                        HStack(spacing: 10) {
                            ForEach(AppAppearanceMode.allCases) { mode in
                                appearancePreviewCard(mode)
                            }
                        }
                    }

                    Divider().overlay(AppTheme.divider)

                    // 1.2 Accent Theme Color Swatches
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            fieldLabel(L("主题色", "Accent Color"))
                            Spacer()
                            Text(appState.settings.accentTheme.localizedName(isEnglish: theme.isEnglish))
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(AppTheme.brandPrimary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2.5)
                                .background(Capsule().fill(AppTheme.brandSoftFill))
                        }

                        HStack(spacing: 12) {
                            ForEach(AppAccentTheme.allCases) { accentOption in
                                let isSelected = appState.settings.accentTheme == accentOption
                                let swatchColor = AppTheme.accentColor(for: accentOption)
                                Button {
                                    withAnimation(.easeInOut(duration: 0.16)) {
                                        appState.settings.accentTheme = accentOption
                                    }
                                } label: {
                                    VStack(spacing: 6) {
                                        ZStack {
                                            Circle()
                                                .strokeBorder(isSelected ? swatchColor : Color.clear, lineWidth: 2)
                                                .frame(width: 34, height: 34)
                                            Circle()
                                                .fill(swatchColor)
                                                .frame(width: 26, height: 26)
                                                .shadow(color: swatchColor.opacity(0.32), radius: 3, y: 1)
                                            if isSelected {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 11, weight: .bold))
                                                    .foregroundStyle(.white)
                                            }
                                        }
                                        Text(accentOption.localizedName(isEnglish: theme.isEnglish))
                                            .font(.system(size: 10.5, weight: isSelected ? .semibold : .regular))
                                            .foregroundStyle(isSelected ? AppTheme.textPrimary : AppTheme.textSecondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 4)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Divider().overlay(AppTheme.divider)

                    // 1.3 Reading Font Size
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            fieldLabel(
                                L("纪要阅读字号", "Reading Font Size"),
                                hint: L("调整会议纪要与逐字稿正文大小", "Adjust summary & transcript text scale")
                            )
                            Spacer()
                            HStack(spacing: 6) {
                                ForEach(AppFontScale.allCases) { scale in
                                    let active = appState.settings.fontScale == scale
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.14)) {
                                            appState.settings.fontScale = scale
                                        }
                                    } label: {
                                        Text(scale.localizedName(isEnglish: theme.isEnglish))
                                            .font(.system(size: 11.5, weight: active ? .semibold : .regular))
                                            .foregroundStyle(active ? AppTheme.brandPrimary : AppTheme.textSecondary)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
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
                        }

                        Text(L(
                            "预览效果：Sonote 实时将会议语音提炼为结构化决议与待办事项。",
                            "Preview: Sonote turns live meetings into clear decisions and action items."
                        ))
                        .font(.system(size: AppTheme.scaled(13.5)))
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppTheme.softCardBg))
                    }
                }
            }

            // Card 2: Interface Language
            SettingsCard(
                title: L("语言", "Language"),
                subtitle: L("界面语言切换后立即生效，无需重启应用", "Interface language updates live across windows without restarting")
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        fieldLabel(L("界面语言", "Interface Language"))
                        Spacer()
                        HStack(spacing: 6) {
                            ForEach(AppInterfaceLanguage.allCases) { lang in
                                let active = appState.settings.interfaceLanguage == lang
                                Button {
                                    withAnimation(.easeInOut(duration: 0.14)) {
                                        appState.settings.interfaceLanguage = lang
                                    }
                                } label: {
                                    Text(lang.localizedName(isEnglish: theme.isEnglish))
                                        .font(.system(size: 12, weight: active ? .semibold : .regular))
                                        .foregroundStyle(active ? AppTheme.brandPrimary : AppTheme.textSecondary)
                                        .padding(.horizontal, 11)
                                        .padding(.vertical, 6)
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
                    }

                    Divider().overlay(AppTheme.divider)

                    HStack(spacing: 12) {
                        fieldLabel(
                            L("语音转写识别语言", "Speech Recognition Language"),
                            hint: appState.settings.transcriptionLanguage.displayName
                        )
                        Spacer()
                        CleanSmallButton(L("前往音频设置", "Audio Settings")) {
                            withAnimation(.easeInOut(duration: 0.14)) {
                                selectedTab = .audio
                            }
                        }
                    }
                }
            }

            // Card 3: Startup & Window Behavior
            SettingsCard(title: L("启动与窗口行为", "Startup & Window")) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsToggleRow(
                        title: L("登录 macOS 时自动启动", "Launch at Login"),
                        subtitle: L("开机静默驻留顶部菜单栏，加入会议自动提醒", "Start silently in the menu bar to detect meetings automatically"),
                        isOn: Binding(
                            get: { launchAtLogin },
                            set: { newValue in
                                try? LaunchAtLoginService.setEnabled(newValue)
                                launchAtLogin = LaunchAtLoginService.isEnabled
                            }
                        )
                    )

                    Divider().overlay(AppTheme.divider)

                    SettingsToggleRow(
                        title: L("菜单栏显示录制时长计时", "Show Recording Timer in Menu Bar"),
                        subtitle: L("录制会议时在顶部状态栏波形图标旁显示实时计时", "Display live elapsed time next to the menu bar icon while recording"),
                        isOn: $appState.settings.showMenuBarTimer
                    )

                    Divider().overlay(AppTheme.divider)

                    SettingsToggleRow(
                        title: L("关闭主窗口后保持驻留菜单栏", "Keep Running in Menu Bar on Close"),
                        subtitle: L("关闭主窗口时不退出应用，持续在后台监测会议", "Keep Sonote active in the menu bar when closing the main window"),
                        isOn: $appState.settings.keepRunningInMenuBarOnClose
                    )

                    Divider().overlay(AppTheme.divider)

                    SettingsToggleRow(
                        title: L("录制中自动收起为左上角悬浮小窗", "Minimize to Floating Capsule While Recording"),
                        subtitle: L("开会时不遮挡屏幕，随时一键展开完整双栏视图", "Keep a compact floating HUD during calls with one-click expand"),
                        isOn: $appState.settings.showFloatingCapsuleWhileRecording
                    )
                }
            }

            // Card 4: About Sonote
            SettingsCard(title: L("关于", "About")) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(AppTheme.brandSoftFill)
                            .frame(width: 40, height: 40)
                        Image(systemName: "waveform")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(AppTheme.brandPrimary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Sonote")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                            Text("声记")
                                .font(.system(size: 11.5))
                                .foregroundStyle(AppTheme.textMuted)
                            Text("v1.5.0")
                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(AppTheme.brandPrimary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(Capsule().fill(AppTheme.brandSoftFill))
                        }
                        Text(L("原生 macOS Apple Silicon MLX 智能会议纪要 · MIT License", "Native macOS Apple Silicon MLX Meeting Minutes · MIT License"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(AppTheme.textSecondary)
                    }

                    Spacer()

                    CleanSmallButton(L("数据目录", "Data Folder")) {
                        NSWorkspace.shared.open(MeetingStore.shared.baseDirectory)
                    }
                    CleanSmallButton("GitHub") {
                        if let url = URL(string: "https://github.com/eeachen4/Sonote") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        }
    }

    private func appearancePreviewCard(_ mode: AppAppearanceMode) -> some View {
        let isSelected = appState.settings.appearanceMode == mode
        let accent = AppTheme.brandPrimary
        return Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                appState.settings.appearanceMode = mode
            }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    switch mode {
                    case .light:
                        miniWindowMock(isDark: false, accent: accent)
                    case .dark:
                        miniWindowMock(isDark: true, accent: accent)
                    case .system:
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                miniWindowMock(isDark: true, accent: accent)
                                miniWindowMock(isDark: false, accent: accent)
                                    .frame(width: geo.size.width / 2, alignment: .leading)
                                    .clipped()
                            }
                        }
                    }
                }
                .frame(height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isSelected ? accent : AppTheme.subtleBorder, lineWidth: isSelected ? 2 : 1)
                )

                HStack(spacing: 4) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(accent)
                    }
                    Text(mode.localizedName(isEnglish: theme.isEnglish))
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? AppTheme.textPrimary : AppTheme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isSelected ? AppTheme.brandSoftFill.opacity(0.55) : AppTheme.softCardBg)
            )
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func miniWindowMock(isDark: Bool, accent: Color) -> some View {
        let bg = isDark ? Color(red: 0.10, green: 0.11, blue: 0.14) : Color.white
        let sidebar = isDark ? Color(red: 0.14, green: 0.15, blue: 0.19) : Color(red: 0.96, green: 0.97, blue: 0.98)
        let line = isDark ? Color.white.opacity(0.22) : Color.black.opacity(0.12)
        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 2.5) {
                    Circle().fill(Color.red.opacity(0.75)).frame(width: 4, height: 4)
                    Circle().fill(Color.orange.opacity(0.75)).frame(width: 4, height: 4)
                    Circle().fill(Color.green.opacity(0.75)).frame(width: 4, height: 4)
                }
                RoundedRectangle(cornerRadius: 2).fill(accent.opacity(0.85)).frame(width: 24, height: 5)
                RoundedRectangle(cornerRadius: 2).fill(line).frame(width: 20, height: 4)
                RoundedRectangle(cornerRadius: 2).fill(line).frame(width: 22, height: 4)
                Spacer()
            }
            .padding(6)
            .frame(width: 38, alignment: .leading)
            .background(sidebar)

            VStack(alignment: .leading, spacing: 5) {
                RoundedRectangle(cornerRadius: 2.5).fill(accent.opacity(0.28)).frame(width: 44, height: 8)
                RoundedRectangle(cornerRadius: 2).fill(line).frame(maxWidth: .infinity, maxHeight: 4)
                RoundedRectangle(cornerRadius: 2).fill(line).frame(width: 52, height: 4)
                Spacer()
            }
            .padding(7)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(bg)
        }
    }

    // MARK: - Page 1: AI 模型与认证

    private var aiModelPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(title: "模型提供方") {
                VStack(alignment: .leading, spacing: 12) {
                    // Clean 4-pill provider selector
                    HStack(spacing: 6) {
                        ForEach(AuthMode.allCases) { mode in
                            let active = appState.settings.authMode == mode
                            Button {
                                appState.settings.authMode = mode
                            } label: {
                                Text(mode.displayName)
                                    .font(.system(size: 12, weight: active ? .semibold : .regular))
                                    .foregroundStyle(active ? AppTheme.brandPrimary : AppTheme.textSecondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 7)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(active ? AppTheme.brandSoftFill : AppTheme.softCardBg)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .strokeBorder(active ? AppTheme.brandPrimary.opacity(0.3) : Color.clear, lineWidth: 1)
                                    )
                                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Live credential health banner
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
                        CleanSmallButton("刷新") {
                            appState.refreshAuthInspection()
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(AppTheme.softCardBg))
                }
            }

            // Provider-specific configuration card
            if appState.settings.authMode == .localAuthFile {
                SettingsCard(title: "本机 Codex Auth 文件") {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            fieldLabel("Auth 文件路径", hint: "自动兼容 ~/.codex/auth.json、JSON 与 .env")
                            HStack(spacing: 8) {
                                CleanInputBox(placeholder: "~/.codex/auth.json", text: $appState.settings.authFilePath)
                                CleanSmallButton("选择文件...") { pickAuthFile() }
                            }
                            if !discoveredAuthFiles.isEmpty {
                                HStack(spacing: 6) {
                                    Text("已探测：")
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
                            fieldLabel("使用模型", hint: "自动读取本地 models_cache.json")
                            Spacer()
                            CleanMenuPicker(
                                title: appState.settings.codexModel.isEmpty ? "选择模型" : appState.settings.codexModel,
                                options: codexModelOptions,
                                selection: $appState.settings.codexModel
                            )
                        }

                        CleanInputBox(placeholder: "或手动输入自定义模型 ID", text: $appState.settings.codexModel)
                    }
                }
            } else if appState.settings.authMode == .apiKey {
                SettingsCard(title: "OpenAI / 兼容接口 / 本地零成本模型") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 6) {
                            Text("一键预设")
                                .font(.system(size: 11.5))
                                .foregroundStyle(AppTheme.textSecondary)
                            CleanChipButton("OpenAI 官方", selected: appState.settings.apiBaseURL.contains("api.openai.com")) {
                                appState.settings.apiBaseURL = "https://api.openai.com/v1"
                                appState.settings.model = "gpt-5.4"
                            }
                            CleanChipButton("本地 Ollama", selected: appState.settings.apiBaseURL.contains("11434")) {
                                appState.settings.apiBaseURL = "http://localhost:11434/v1"
                                appState.settings.model = "qwen3:14b"
                            }
                            CleanChipButton("本地 MLX Server", selected: appState.settings.apiBaseURL.contains("8080")) {
                                appState.settings.apiBaseURL = "http://localhost:8080/v1"
                                appState.settings.model = "mlx-community/Qwen3-8B-4bit"
                            }
                        }

                        VStack(alignment: .leading, spacing: 5) {
                            fieldLabel("API Key", hint: "加密存于 macOS 钥匙串；本地 localhost 服务可留空")
                            CleanSecureBox(placeholder: "sk-...", text: $appState.settings.apiKey)
                        }

                        VStack(alignment: .leading, spacing: 5) {
                            fieldLabel("Base URL")
                            CleanInputBox(placeholder: "https://api.openai.com/v1", text: $appState.settings.apiBaseURL)
                        }

                        HStack {
                            fieldLabel("模型 ID")
                            Spacer()
                            CleanMenuPicker(
                                title: appState.settings.model.isEmpty ? "选择模型" : appState.settings.model,
                                options: AppSettings.suggestedAPIModels,
                                selection: $appState.settings.model
                            )
                        }
                        CleanInputBox(placeholder: "自定义模型 ID（如 deepseek-chat / qwen3:14b）", text: $appState.settings.model)
                    }
                }
            } else if appState.settings.authMode == .anthropicClaude {
                SettingsCard(title: "Anthropic Claude API") {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            fieldLabel("Claude API Key", hint: "加密存于 macOS 钥匙串")
                            CleanSecureBox(placeholder: "sk-ant-...", text: $appState.settings.claudeAPIKey)
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            fieldLabel("Base URL")
                            CleanInputBox(placeholder: "https://api.anthropic.com/v1", text: $appState.settings.claudeBaseURL)
                        }
                        HStack {
                            fieldLabel("Claude 模型")
                            Spacer()
                            CleanMenuPicker(
                                title: appState.settings.claudeModel.isEmpty ? "选择模型" : appState.settings.claudeModel,
                                options: AppSettings.suggestedClaudeModels,
                                selection: $appState.settings.claudeModel
                            )
                        }
                        CleanInputBox(placeholder: "或自定义 Claude 模型 ID", text: $appState.settings.claudeModel)
                    }
                }
            } else if appState.settings.authMode == .googleGemini {
                SettingsCard(title: "Google Gemini API") {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            fieldLabel("Gemini API Key", hint: "加密存于 macOS 钥匙串")
                            CleanSecureBox(placeholder: "AIza...", text: $appState.settings.geminiAPIKey)
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            fieldLabel("Base URL")
                            CleanInputBox(placeholder: "https://generativelanguage.googleapis.com/v1beta", text: $appState.settings.geminiBaseURL)
                        }
                        HStack {
                            fieldLabel("Gemini 模型")
                            Spacer()
                            CleanMenuPicker(
                                title: appState.settings.geminiModel.isEmpty ? "选择模型" : appState.settings.geminiModel,
                                options: AppSettings.suggestedGeminiModels,
                                selection: $appState.settings.geminiModel
                            )
                        }
                        CleanInputBox(placeholder: "或自定义 Gemini 模型 ID", text: $appState.settings.geminiModel)
                    }
                }
            } else if appState.settings.authMode == .localMLX {
                SettingsCard(title: "内置离线 MLX 大模型（无需外部 Ollama，零 Token 成本）") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            fieldLabel("本地 Qwen2.5 模型", hint: LocalMLXLLMEngine.isModelCachedLocally(modelID: appState.settings.localMLXLLMModelID) ? "本地已缓存权重，完全离线可用" : "首次运行将通过 HuggingFace 镜像自动下载")
                            Spacer()
                            CleanMenuPicker(
                                title: appState.settings.localMLXLLMModelID.split(separator: "/").last.map(String.init) ?? "选择模型",
                                options: AppSettings.suggestedLocalMLXLLMModels,
                                selection: $appState.settings.localMLXLLMModelID
                            )
                        }
                        CleanInputBox(placeholder: "或输入自定义 Qwen2.5 MLX Repo / 本地目录", text: $appState.settings.localMLXLLMModelID)

                        HStack(spacing: 8) {
                            CleanPrimaryButton(
                                title: appState.isPreloadingLocalLLM ? "加载中..." : "预下载 / 加载模型",
                                icon: "arrow.down.circle",
                                disabled: appState.isPreloadingLocalLLM
                            ) {
                                Task { await appState.preloadLocalMLXLLM() }
                            }
                            CleanSmallButton("释放显存") {
                                Task { await appState.unloadLocalMLXLLM() }
                            }
                            Spacer()
                        }
                    }
                }
            }

            // Connectivity Test + Token Ledger Card
            SettingsCard(title: "连通性测试与 Token 消耗") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        CleanPrimaryButton(
                            title: isTestingConnection ? "测试中..." : "测试 AI 连接",
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
                            label: "今日累计",
                            value: appState.todayTokenUsage.isEmpty ? "0" : "\(appState.todayTokenUsage.formattedCompact) tokens",
                            detail: appState.todayTokenUsage.isEmpty ? "按实际调用日期统计" : appState.todayTokenUsage.detailedSummary
                        )
                        tokenStatTile(
                            label: "全部历史",
                            value: appState.totalTokenUsage.isEmpty ? "0" : "\(appState.totalTokenUsage.formattedCompact) tokens",
                            detail: appState.totalTokenUsage.isEmpty ? "暂无历史消耗" : appState.totalTokenUsage.detailedSummary
                        )
                    }

                    if !appState.totalTokenUsage.isEmpty {
                        HStack {
                            Spacer()
                            Button("重置统计") {
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

    // MARK: - Page 2: 音频与转写

    private var audioTranscriptionPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Card 1: Profile & Capture Basics
            SettingsCard(title: "采集与存储") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 14) {
                        fieldLabel("本机发言人名称", hint: "留空默认显示「我」")
                        Spacer()
                        CleanInputBox(placeholder: "例如：林致远 / Alex", text: $appState.settings.localUserName)
                            .frame(width: 210)
                    }

                    Divider().overlay(AppTheme.divider)

                    HStack {
                        fieldLabel("采集通道", hint: "支持系统远端声音与麦克风双轨分离")
                        Spacer()
                        Menu {
                            ForEach(AudioCaptureMode.allCases) { mode in
                                Button(mode.displayName) { appState.settings.audioCaptureMode = mode }
                            }
                        } label: {
                            cleanMenuLabel(appState.settings.audioCaptureMode.displayName)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }

                    Divider().overlay(AppTheme.divider)

                    SettingsToggleRow(
                        title: "保存会议音频备份 (.m4a)",
                        subtitle: "支持会后音文同步倍速回听与声纹认人",
                        isOn: $appState.settings.saveAudioBackup
                    )

                    Divider().overlay(AppTheme.divider)

                    SettingsToggleRow(
                        title: "录制中收起为左上角悬浮小窗",
                        subtitle: "开会时不遮挡屏幕，随时一键展开完整视图",
                        isOn: $appState.settings.showFloatingCapsuleWhileRecording
                    )

                    Divider().overlay(AppTheme.divider)

                    HStack(spacing: 8) {
                        fieldLabel(
                            "本地录音存储空间",
                            hint: appState.audioStorageStats.fileCount == 0
                                ? "暂无音频备份文件"
                                : "共 \(appState.audioStorageStats.fileCount) 个文件 · 占用 \(appState.audioStorageStats.formattedSize)"
                        )
                        Spacer()
                        CleanSmallButton("打开目录") {
                            appState.revealAudioDirectoryInFinder()
                        }
                        Menu {
                            Button("清理 30 天前音频（保留文字纪要）") { appState.pruneAudioBackups(olderThanDays: 30) }
                            Button("清理 7 天前音频（保留文字纪要）") { appState.pruneAudioBackups(olderThanDays: 7) }
                            Divider()
                            Button("清理全部已完成会议音频", role: .destructive) { appState.pruneAudioBackups(olderThanDays: 0) }
                        } label: {
                            cleanMenuLabel("清理音频")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .disabled(appState.audioStorageStats.fileCount == 0)
                    }
                }
            }

            // Card 2: Speech-to-Text Engine & Audio Enhancement
            SettingsCard(title: "语音转写与降噪引擎") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        fieldLabel("转写引擎")
                        Spacer()
                        Menu {
                            ForEach(TranscriptionEngine.allCases) { engine in
                                Button(engine.displayName) { appState.settings.transcriptionEngine = engine }
                            }
                        } label: {
                            cleanMenuLabel(shortEngineName(appState.settings.transcriptionEngine))
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }

                    Divider().overlay(AppTheme.divider)

                    HStack {
                        fieldLabel("会议语言", hint: "中英混说建议保持自动检测")
                        Spacer()
                        Menu {
                            ForEach(TranscriptionLanguage.allCases) { lang in
                                Button(lang.displayName) { appState.settings.transcriptionLanguage = lang }
                            }
                        } label: {
                            cleanMenuLabel(appState.settings.transcriptionLanguage.displayName)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }

                    if appState.settings.transcriptionEngine == .mlxQwen3ASR {
                        Divider().overlay(AppTheme.divider)

                        HStack {
                            fieldLabel("Qwen3-ASR 模型", hint: mlxCacheSummary)
                            Spacer()
                            Menu {
                                ForEach(MLXQwen3ModelPreset.all) { preset in
                                    Button("\(preset.label) · \(preset.footprintHint)") {
                                        appState.settings.mlxQwen3ModelID = preset.repoID
                                    }
                                }
                            } label: {
                                cleanMenuLabel(selectedMLXPresetShortLabel)
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        }

                        // Compact model action bar
                        HStack(spacing: 8) {
                            CleanPrimaryButton(
                                title: appState.mlxModelState.isBusy ? "加载中..." : "预下载 / 加载模型",
                                icon: "arrow.down.circle",
                                disabled: appState.mlxModelState.isBusy
                            ) {
                                Task { await appState.preloadMLXQwen3Model() }
                            }
                            if appState.mlxModelState.isReady {
                                CleanSmallButton("释放内存") {
                                    Task { await appState.unloadMLXQwen3Model() }
                                }
                            }
                            Spacer()
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    showAdvancedMLX.toggle()
                                }
                            } label: {
                                HStack(spacing: 3) {
                                    Text("镜像源与高级选项")
                                    Image(systemName: showAdvancedMLX ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 9))
                                }
                                .font(.system(size: 11.5))
                                .foregroundStyle(AppTheme.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }

                        if case .downloading(let progress, _) = appState.mlxModelState, progress > 0 {
                            ProgressView(value: progress).tint(AppTheme.brandPrimary)
                        }

                        if showAdvancedMLX {
                            VStack(alignment: .leading, spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("自定义 HuggingFace Repo / 本地目录")
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundStyle(AppTheme.textSecondary)
                                    CleanInputBox(placeholder: "mlx-community/Qwen3-ASR-1.7B-8bit", text: $appState.settings.mlxQwen3ModelID)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("HuggingFace 镜像源")
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundStyle(AppTheme.textSecondary)
                                    HStack(spacing: 6) {
                                        CleanInputBox(placeholder: "https://huggingface.co", text: $appState.settings.mlxHuggingFaceHost)
                                        CleanChipButton("官方源", selected: appState.settings.mlxHuggingFaceHost.contains("huggingface.co")) {
                                            appState.settings.mlxHuggingFaceHost = "https://huggingface.co"
                                        }
                                        CleanChipButton("国内镜像", selected: appState.settings.mlxHuggingFaceHost.contains("hf-mirror")) {
                                            appState.settings.mlxHuggingFaceHost = "https://hf-mirror.com"
                                        }
                                    }
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("补充语境提示（可选）")
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundStyle(AppTheme.textSecondary)
                                    CleanInputBox(placeholder: "如：PR, API, 飞书, 豆包, Swift", text: $appState.settings.asrContextHint)
                                }
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(AppTheme.softCardBg))
                        }

                        Divider().overlay(AppTheme.divider)

                        SettingsToggleRow(
                            title: "Silero 逐帧流式人声检测",
                            subtitle: "过滤敲键盘、风扇底噪并精准断句",
                            isOn: $appState.settings.enableNeuralVAD
                        )

                        Divider().overlay(AppTheme.divider)

                        HStack(alignment: .center, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text("嘈杂环境人声降噪 (DeepFilterNet3)")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(AppTheme.textPrimary)
                                    if appState.settings.enableSpeechEnhancement {
                                        let cached = SpeechEnhancementService.isModelCachedLocally(modelID: appState.settings.speechEnhancementModelID)
                                        if cached {
                                            Text("已缓存")
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundStyle(AppTheme.successGreen)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 1.5)
                                                .background(Capsule().fill(AppTheme.successGreen.opacity(0.12)))
                                        } else {
                                            CleanSmallButton(appState.isPreloadingDenoiser ? "下载中..." : "预下载") {
                                                Task { await appState.preloadSpeechEnhancementModel() }
                                            }
                                            .disabled(appState.isPreloadingDenoiser)
                                        }
                                    }
                                }
                                Text("在咖啡馆、开放办公区或外放开会时抑制背景噪声")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                            Spacer()
                            Toggle("", isOn: $appState.settings.enableSpeechEnhancement)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .tint(AppTheme.brandPrimary)
                        }

                        Divider().overlay(AppTheme.divider)

                        SettingsToggleRow(
                            title: "外放开会双轨回声去重",
                            subtitle: "防止扬声器串入麦克风导致重复记录",
                            isOn: $appState.settings.enableEchoDeduplication
                        )

                        Divider().overlay(AppTheme.divider)

                        SettingsToggleRow(
                            title: "会后自动释放 MLX 显存与内存",
                            subtitle: "非录制时段待机零模型内存占用",
                            isOn: $appState.settings.mlxAutoUnloadAfterMeeting
                        )
                    } else if appState.settings.transcriptionEngine == .openAITranscribe {
                        Divider().overlay(AppTheme.divider)
                        VStack(alignment: .leading, spacing: 5) {
                            fieldLabel("OpenAI 转写模型")
                            CleanInputBox(placeholder: "gpt-4o-mini-transcribe / whisper-1", text: $appState.settings.openAITranscribeModel)
                        }
                    }
                }
            }

            // Card 3: Team Glossary Dictionary
            SettingsCard(title: "团队术语词典", subtitle: "自动合并声纹库姓名与日程参会人，提升中英专有名词转写准确度") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        CleanInputBox(placeholder: "输入术语（支持逗号批量，如：MLX, PR, GraphQL, Kubernetes）", text: $newGlossaryTerm) {
                            addGlossaryTerm()
                        }
                        CleanSmallButton("加入词典") { addGlossaryTerm() }
                            .disabled(newGlossaryTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if !appState.settings.glossaryTerms.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(appState.settings.glossaryTerms, id: \.self) { term in
                                    HStack(spacing: 4) {
                                        Text(term)
                                            .font(.system(size: 11.5, weight: .medium))
                                        Button {
                                            appState.settings.glossaryTerms.removeAll { $0 == term }
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 8.5, weight: .bold))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .foregroundStyle(AppTheme.brandPrimary)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(AppTheme.brandSoftFill))
                                }
                            }
                        }
                    }
                }
            }

            // Card 4: Speaker Diarization Strategy
            SettingsCard(title: "多说话人分离策略") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        fieldLabel("分离算法")
                        Spacer()
                        Menu {
                            ForEach(DiarizationStrategy.allCases) { s in
                                Button(s.displayName) { appState.settings.diarizationStrategy = s }
                            }
                        } label: {
                            cleanMenuLabel(appState.settings.diarizationStrategy == .sortformerFourSpeaker ? "Sortformer (≤4 人)" : "ECAPA 聚类 (5~12 人)")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }

                    Divider().overlay(AppTheme.divider)

                    SettingsToggleRow(
                        title: "会中实时多说话人分离",
                        subtitle: "录制过程中实时匹配远端说话人声纹",
                        isOn: $appState.settings.enableLiveSpeakerDiarization
                    )

                    Divider().overlay(AppTheme.divider)

                    SettingsToggleRow(
                        title: "导入音视频时自动区分说话人",
                        subtitle: "离线转写完成后自动分轨并匹配声纹库",
                        isOn: $appState.settings.enableSpeakerDiarization
                    )

                    Divider().overlay(AppTheme.divider)

                    SettingsToggleRow(
                        title: "自动匹配本地声纹库",
                        subtitle: "跨会议自动把「发言人 1 / 2」标为真实姓名",
                        isOn: $appState.settings.autoIdentifyVoiceprints
                    )
                }
            }

            // Card 5: macOS Permissions
            SettingsCard(title: "系统隐私权限") {
                VStack(spacing: 11) {
                    cleanPermissionRow(
                        title: "仅系统音频录制",
                        detail: "采集会议远端声音（无需完整录屏权限）",
                        status: nil,
                        buttonTitle: "系统设置"
                    ) {
                        appState.openPrivacySettings("Privacy_AudioCapture")
                    }

                    Divider().overlay(AppTheme.divider)

                    cleanPermissionRow(
                        title: "麦克风",
                        detail: "采集本机发言，实现双轨逐字稿与声纹建档",
                        status: micStatus == .authorized,
                        buttonTitle: micStatus == .authorized ? "系统设置" : "授权"
                    ) {
                        if micStatus == .notDetermined {
                            Task {
                                _ = await MicrophoneCapture.requestPermission()
                                refreshPermissions()
                            }
                        } else {
                            appState.openPrivacySettings("Privacy_Microphone")
                        }
                    }

                    Divider().overlay(AppTheme.divider)

                    cleanPermissionRow(
                        title: "语音识别",
                        detail: "Apple 本机识别回退链路所需权限",
                        status: speechStatus == .authorized,
                        buttonTitle: speechStatus == .authorized ? "系统设置" : "授权"
                    ) {
                        if speechStatus == .notDetermined {
                            Task {
                                _ = await LegacySpeechTranscriber.requestSpeechAuthorization()
                                refreshPermissions()
                            }
                        } else {
                            appState.openPrivacySettings("Privacy_SpeechRecognition")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Page 3: 声纹库

    private var voiceprintLibraryPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(title: "录入新声纹", subtitle: "本地提取 192 维 ECAPA-TDNN 向量，数据仅保存在本机") {
                VStack(alignment: .leading, spacing: 11) {
                    HStack(spacing: 8) {
                        CleanInputBox(placeholder: "姓名（如：林致远 / Alex）", text: $newVoiceprintName)
                        CleanInputBox(placeholder: "角色备注（可选）", text: $newVoiceprintRole)
                            .frame(width: 150)
                    }

                    Toggle("标记为本人声纹（自动同步为本机发言人名称）", isOn: $newVoiceprintIsSelf)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.textSecondary)

                    HStack(spacing: 8) {
                        CleanPrimaryButton(
                            title: appState.isEnrollingVoiceprint ? "正在录入..." : "麦克风录音 5 秒建档",
                            icon: "mic.fill",
                            disabled: newVoiceprintName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || appState.isEnrollingVoiceprint
                        ) {
                            let name = newVoiceprintName.trimmingCharacters(in: .whitespacesAndNewlines)
                            let role = newVoiceprintRole.trimmingCharacters(in: .whitespacesAndNewlines)
                            let isSelf = newVoiceprintIsSelf
                            Task {
                                await appState.enrollVoiceprintFromLiveMic(name: name, role: role, isSelf: isSelf)
                                if appState.voiceprints.contains(where: { $0.name == name }) {
                                    newVoiceprintName = ""
                                    newVoiceprintRole = ""
                                    newVoiceprintIsSelf = false
                                }
                            }
                        }

                        CleanSmallButton("从音频文件建档...") {
                            pickAudioFileForVoiceprint()
                        }
                        .disabled(newVoiceprintName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || appState.isEnrollingVoiceprint)

                        Spacer()
                    }

                    if appState.isEnrollingVoiceprint && appState.voiceprintEnrollProgress > 0 {
                        VStack(alignment: .leading, spacing: 4) {
                            ProgressView(value: appState.voiceprintEnrollProgress)
                                .tint(AppTheme.brandPrimary)
                            HStack {
                                Text("采集中 \(Int(appState.voiceprintEnrollProgress * 100))%")
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppTheme.textSecondary)
                                Spacer()
                                Text("音量 \(Int(min(100, appState.voiceprintEnrollLevel * 100)))%")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                        }
                    }

                    if let msg = appState.voiceprintStatusMessage {
                        Text(msg)
                            .font(.system(size: 11.5))
                            .foregroundStyle(msg.contains("失败") ? AppTheme.recordingRed : AppTheme.brandPrimary)
                    }
                }
            }

            SettingsCard(title: "已建档声纹（\(appState.voiceprints.count) 人）", subtitle: "也可在历史会议逐字稿中点击说话人改名并勾选「记住声纹」持续优化") {
                if appState.voiceprints.isEmpty {
                    Text("暂无已录入声纹。录入后，开会或导入音视频时将自动识别并标出真实姓名。")
                        .font(.system(size: 12.5))
                        .foregroundStyle(AppTheme.textMuted)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(appState.voiceprints.enumerated()), id: \.element.id) { idx, profile in
                            if idx > 0 {
                                Divider().overlay(AppTheme.divider).padding(.vertical, 8)
                            }
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(profile.isSelf ? AppTheme.brandSoftFill : AppTheme.neutralPill)
                                        .frame(width: 30, height: 30)
                                    Text(String(profile.name.prefix(1)))
                                        .font(.system(size: 12.5, weight: .semibold))
                                        .foregroundStyle(profile.isSelf ? AppTheme.brandPrimary : AppTheme.textPrimary)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(profile.name)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(AppTheme.textPrimary)
                                        if profile.isSelf {
                                            Text("本人")
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundStyle(AppTheme.brandPrimary)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 1.5)
                                                .background(Capsule().fill(AppTheme.brandSoftFill))
                                        }
                                        if !profile.role.isEmpty {
                                            Text(profile.role)
                                                .font(.system(size: 11))
                                                .foregroundStyle(AppTheme.textSecondary)
                                        }
                                    }
                                    Text("已融合 \(profile.sampleCount) 份样本 · 自动同步至热词")
                                        .font(.system(size: 11))
                                        .foregroundStyle(AppTheme.textMuted)
                                }

                                Spacer()

                                Button {
                                    appState.deleteVoiceprint(id: profile.id)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 12))
                                        .foregroundStyle(AppTheme.textMuted)
                                        .frame(width: 26, height: 26)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help("删除声纹")
                            }
                        }
                    }
                }
            }

            SettingsCard(title: "匹配灵敏度") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        fieldLabel("余弦相似度阈值", hint: "越低越易命中，越高越防误认（推荐 0.56）")
                        Spacer()
                        Text(String(format: "%.2f", appState.settings.voiceprintMatchThreshold))
                            .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AppTheme.brandPrimary)
                    }
                    Slider(value: $appState.settings.voiceprintMatchThreshold, in: 0.45...0.75, step: 0.02)
                        .tint(AppTheme.brandPrimary)
                }
            }
        }
    }

    // MARK: - Page 4: 纪要模板与策略

    private var templatesPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(title: "实时提炼与默认风格") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        fieldLabel("默认场景模板", hint: "新建会议与导入音视频时默认采用")
                        Spacer()
                        Menu {
                            ForEach(MinutesTemplate.allCases) { tpl in
                                Button(tpl.displayName) { appState.settings.defaultMinutesTemplate = tpl }
                            }
                        } label: {
                            cleanMenuLabel(appState.settings.defaultMinutesTemplate.displayName)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }

                    Divider().overlay(AppTheme.divider)

                    SettingsToggleRow(
                        title: "会中自动增量提炼要点",
                        subtitle: "仅发送新增片段，相比全量总结节省 60%+ Token",
                        isOn: $appState.settings.liveSummaryEnabled
                    )

                    if appState.settings.liveSummaryEnabled {
                        Divider().overlay(AppTheme.divider)
                        HStack {
                            fieldLabel("实时刷新间隔")
                            Spacer()
                            HStack(spacing: 8) {
                                Text("每 \(appState.settings.liveSummaryIntervalSeconds) 秒")
                                    .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                                    .foregroundStyle(AppTheme.textPrimary)
                                Stepper("", value: $appState.settings.liveSummaryIntervalSeconds, in: 15...120, step: 5)
                                    .labelsHidden()
                            }
                        }
                    }

                    Divider().overlay(AppTheme.divider)

                    VStack(alignment: .leading, spacing: 5) {
                        fieldLabel("全局纪要偏好（可选）", hint: "附加到每次纪要生成提示词末尾")
                        CleanInputBox(placeholder: "例如：偏研发评审风格，重点列出技术方案对比与风险", text: $appState.settings.customMinutesPrompt)
                    }
                }
            }

            SettingsCard(title: "自定义纪要模板", subtitle: "新增后可在任意会议右上角的模板菜单中一键切换并重新生成") {
                VStack(alignment: .leading, spacing: 12) {
                    if !appState.settings.customTemplates.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(appState.settings.customTemplates) { tpl in
                                HStack(alignment: .top, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(tpl.name)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(AppTheme.textPrimary)
                                        Text(tpl.promptGuidance)
                                            .font(.system(size: 11.5))
                                            .foregroundStyle(AppTheme.textSecondary)
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                    Button {
                                        appState.deleteCustomTemplate(id: tpl.id)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 12))
                                            .foregroundStyle(AppTheme.textMuted)
                                            .frame(width: 24, height: 24)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(AppTheme.softCardBg))
                            }
                        }
                        Divider().overlay(AppTheme.divider)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        CleanInputBox(placeholder: "新模板名称（如：研发周会问题跟踪模板）", text: $newTemplateName)
                        CleanInputBox(placeholder: "提炼规则（如：按模块输出问题表、P0/P1 风险等级与流程决议）", text: $newTemplateGuidance)
                        HStack {
                            Spacer()
                            CleanPrimaryButton(
                                title: "新增模板",
                                icon: "plus",
                                disabled: newTemplateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    || newTemplateGuidance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ) {
                                appState.addCustomTemplate(name: newTemplateName, guidance: newTemplateGuidance)
                                newTemplateName = ""
                                newTemplateGuidance = ""
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Page 5: 自动检测与系统集成

    private var detectionPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(title: "自动提醒与系统集成") {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsToggleRow(
                        title: "开机自动登录启动",
                        subtitle: "登录 macOS 后静默驻留菜单栏守候线上会议",
                        isOn: Binding(
                            get: { launchAtLogin },
                            set: { enabled in
                                do {
                                    try LaunchAtLoginService.setEnabled(enabled)
                                    launchAtLogin = LaunchAtLoginService.isEnabled
                                } catch {
                                    launchAtLogin = LaunchAtLoginService.isEnabled
                                }
                            }
                        )
                    )

                    Divider().overlay(AppTheme.divider)

                    SettingsToggleRow(
                        title: "加入会议自动弹窗提醒",
                        subtitle: "基于 CoreAudio 音频活动检测，无需辅助功能或录屏权限",
                        isOn: $appState.settings.autoDetectMeetings
                    )

                    Divider().overlay(AppTheme.divider)

                    SettingsToggleRow(
                        title: "检测浏览器网页会议",
                        subtitle: "支持 Chrome / Safari / Arc / Edge 麦克风通话",
                        isOn: $appState.settings.detectBrowserCalls
                    )

                    Divider().overlay(AppTheme.divider)

                    SettingsToggleRow(
                        title: "会议结束后提示停止并生成纪要",
                        subtitle: "退出通话软件后自动提醒收尾",
                        isOn: $appState.settings.promptOnMeetingEnd
                    )

                    Divider().overlay(AppTheme.divider)

                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("联动 macOS 日历")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(AppTheme.textPrimary)
                                if calendarAuthorized {
                                    Text("已授权")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(AppTheme.successGreen)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1.5)
                                        .background(Capsule().fill(AppTheme.successGreen.opacity(0.12)))
                                } else {
                                    CleanSmallButton("授权日历") {
                                        Task {
                                            _ = await CalendarContextService.shared.requestAccessIfNeeded()
                                            refreshPermissions()
                                        }
                                    }
                                }
                            }
                            Text("自动带入当前日程标题并将参会人姓名注入热词")
                                .font(.system(size: 11.5))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        Spacer()
                        Toggle("", isOn: $appState.settings.enableCalendarIntegration)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .tint(AppTheme.brandPrimary)
                    }

                    Divider().overlay(AppTheme.divider)

                    HStack {
                        CleanSmallButton("模拟「加入腾讯会议」弹窗") {
                            appState.triggerSimulatedMeetingPrompt()
                        }
                        Text("测试桌面右上角悬浮卡片效果")
                            .font(.system(size: 11.5))
                            .foregroundStyle(AppTheme.textMuted)
                        Spacer()
                    }
                }
            }

            SettingsCard(title: "系统级全局快捷键", subtitle: "全屏开会时依然生效，无需辅助功能权限") {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsToggleRow(
                        title: "启用全局快捷键",
                        subtitle: {
                            let p = appState.settings.globalHotKeyPreset.symbolPrefix
                            return "\(p)R 启停录音  ·  \(p)M 呼出 / 收起 Sonote 窗口"
                        }(),
                        isOn: $appState.settings.enableGlobalHotKeys
                    )

                    if appState.settings.enableGlobalHotKeys {
                        Divider().overlay(AppTheme.divider)
                        HStack {
                            fieldLabel("修饰键组合")
                            Spacer()
                            Menu {
                                ForEach(GlobalHotKeyModifierPreset.allCases) { preset in
                                    Button(preset.displayName) { appState.settings.globalHotKeyPreset = preset }
                                }
                            } label: {
                                cleanMenuLabel(appState.settings.globalHotKeyPreset.symbolPrefix + "R / " + appState.settings.globalHotKeyPreset.symbolPrefix + "M")
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        }
                    }
                }
            }

            SettingsCard(title: "监控列表与忽略黑名单") {
                VStack(alignment: .leading, spacing: 11) {
                    // Ignored apps pills
                    VStack(alignment: .leading, spacing: 6) {
                        fieldLabel("忽略应用黑名单", hint: "以下 Bundle ID 的音频活动不会弹出会议提醒")
                        HStack(spacing: 6) {
                            CleanInputBox(placeholder: "输入 Bundle ID（如 com.example.app）", text: $newIgnoredBundleID)
                            CleanSmallButton("添加") {
                                let cleaned = newIgnoredBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !cleaned.isEmpty, !appState.settings.ignoredBundleIDs.contains(cleaned) else { return }
                                appState.settings.ignoredBundleIDs.append(cleaned)
                                newIgnoredBundleID = ""
                            }
                        }
                        if !appState.settings.ignoredBundleIDs.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(appState.settings.ignoredBundleIDs, id: \.self) { bid in
                                        HStack(spacing: 4) {
                                            Text(bid)
                                                .font(.system(size: 11, design: .monospaced))
                                            Button {
                                                appState.settings.ignoredBundleIDs.removeAll { $0 == bid }
                                            } label: {
                                                Image(systemName: "xmark")
                                                    .font(.system(size: 8, weight: .bold))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .foregroundStyle(AppTheme.textSecondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3.5)
                                        .background(Capsule().fill(AppTheme.softCardBg))
                                        .overlay(Capsule().strokeBorder(AppTheme.subtleBorder, lineWidth: 1))
                                    }
                                }
                            }
                        }
                    }

                    Divider().overlay(AppTheme.divider)

                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showAppMonitoringList.toggle()
                        }
                    } label: {
                        HStack {
                            Text("已启用监控的会议软件（\(appState.settings.monitoredBundleIDs.count) 款）")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(AppTheme.textPrimary)
                            Spacer()
                            Image(systemName: showAppMonitoringList ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10.5))
                                .foregroundStyle(AppTheme.textMuted)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if showAppMonitoringList {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                            ForEach(MeetingAppCatalog.all) { app in
                                Toggle(app.displayName, isOn: Binding(
                                    get: { appState.settings.monitoredBundleIDs.contains(app.bundleID) },
                                    set: { enabled in
                                        if enabled {
                                            if !appState.settings.monitoredBundleIDs.contains(app.bundleID) {
                                                appState.settings.monitoredBundleIDs.append(app.bundleID)
                                            }
                                        } else {
                                            appState.settings.monitoredBundleIDs.removeAll { $0 == app.bundleID }
                                        }
                                    }
                                ))
                                .toggleStyle(.checkbox)
                                .font(.system(size: 12))
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }
        }
    }

    // MARK: - Page 6: 协作推送与全库备份

    private var syncBackupPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(title: "飞书 / 钉钉 / Notion Webhook 一键推送", subtitle: "配置后可在任意会议纪要底部「导出 / 复制」菜单一键推送结构化卡片") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        ForEach(WebhookProvider.allCases) { provider in
                            let active = appState.settings.webhookProvider == provider
                            Button {
                                appState.settings.webhookProvider = provider
                            } label: {
                                Text(provider.displayName)
                                    .font(.system(size: 11.5, weight: active ? .semibold : .regular))
                                    .foregroundStyle(active ? AppTheme.brandPrimary : AppTheme.textSecondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(active ? AppTheme.brandSoftFill : AppTheme.softCardBg))
                                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        fieldLabel("Webhook 地址")
                        CleanInputBox(
                            placeholder: appState.settings.webhookProvider == .feishu
                                ? "https://open.feishu.cn/open-apis/bot/v2/hook/..."
                                : (appState.settings.webhookProvider == .dingtalk
                                   ? "https://oapi.dingtalk.com/robot/send?access_token=..."
                                   : "https://your-webhook.example.com/hook"),
                            text: $appState.settings.webhookURL
                        )
                    }

                    if appState.settings.webhookProvider != .customJSON {
                        VStack(alignment: .leading, spacing: 5) {
                            fieldLabel("加签密钥（可选）", hint: "开启机器人 HMAC-SHA256 签名校验时填写，加密存于钥匙串")
                            CleanSecureBox(placeholder: "留空表示未开启签名校验", text: $appState.settings.webhookSecret)
                        }
                    }

                    HStack(spacing: 10) {
                        CleanPrimaryButton(
                            title: appState.isPushingWebhook ? "发送中..." : "发送测试卡片",
                            icon: "paperplane.fill",
                            disabled: appState.settings.webhookURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || appState.isPushingWebhook
                        ) {
                            Task {
                                let res = await appState.sendTestWebhook()
                                webhookTestFeedback = res.message
                            }
                        }

                        if let msg = webhookTestFeedback {
                            Text(msg)
                                .font(.system(size: 11.5))
                                .foregroundStyle(msg.contains("失败") || msg.contains("错误") || msg.contains("尚未") ? AppTheme.recordingRed : AppTheme.successGreen)
                                .lineLimit(2)
                        }
                        Spacer()
                    }
                }
            }

            SettingsCard(title: "数据全库备份与换机迁移", subtitle: "打包所有会议纪要、逐字稿、声纹库、自定义模板、词典与 Token 账本（不含明文 API 密钥）") {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsToggleRow(
                        title: "备份时包含录音音频文件 (.m4a)",
                        subtitle: "关闭时备份包仅数百 KB；开启后可完整迁移音文同步回放录音",
                        isOn: $includeAudioInBackup
                    )

                    Divider().overlay(AppTheme.divider)

                    HStack(spacing: 10) {
                        CleanPrimaryButton(title: "导出全库备份 (.zip)", icon: "square.and.arrow.up") {
                            backupFeedback = appState.exportBackupArchiveWithSavePanel(includeAudio: includeAudioInBackup)
                        }
                        CleanSmallButton("从备份恢复并合并...") {
                            backupFeedback = appState.importBackupArchiveWithOpenPanel(restoreSettings: true)
                        }
                        Spacer()
                    }

                    if let msg = backupFeedback {
                        Text(msg)
                            .font(.system(size: 11.5))
                            .foregroundStyle(msg.contains("失败") ? AppTheme.recordingRed : AppTheme.brandPrimary)
                    }
                }
            }
        }
    }

    // MARK: - Clean Visual Helpers

    private func fieldLabel(_ title: String, hint: String? = nil) -> some View {
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

    private func cleanMenuLabel(_ text: String) -> some View {
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

    private func tokenStatTile(label: String, value: String, detail: String) -> some View {
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

    private func cleanPermissionRow(
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
                        Text(status ? "已授权" : "未授权")
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

    private func shortEngineName(_ engine: TranscriptionEngine) -> String {
        switch engine {
        case .mlxQwen3ASR: return "MLX Qwen3-ASR 本地（推荐）"
        case .appleSpeech: return "Apple 本机实时识别"
        case .openAITranscribe: return "OpenAI 转写 API"
        }
    }

    private var selectedMLXPresetShortLabel: String {
        if let match = MLXQwen3ModelPreset.all.first(where: { $0.repoID == appState.settings.mlxQwen3ModelID }) {
            return "\(match.repoID.split(separator: "/").last ?? "") · \(match.footprintHint)"
        }
        return appState.settings.mlxQwen3ModelID.split(separator: "/").last.map(String.init) ?? appState.settings.mlxQwen3ModelID
    }

    private var mlxCacheSummary: String {
        let cached = MLXQwen3ASREngine.isModelCachedLocally(modelID: appState.settings.mlxQwen3ModelID)
        if appState.mlxModelState == .idle && cached {
            return "本地已缓存权重，开始录音即可秒加载"
        }
        return appState.mlxModelState.statusText
    }

    // MARK: - Actions

    private func addGlossaryTerm() {
        let parts = newGlossaryTerm
            .components(separatedBy: CharacterSet(charactersIn: ",，、;；"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for part in parts where !appState.settings.glossaryTerms.contains(part) {
            appState.settings.glossaryTerms.append(part)
        }
        newGlossaryTerm = ""
    }

    private func pickAuthFile() {
        let panel = NSOpenPanel()
        panel.title = "选择本地 Auth 凭证文件（JSON / .env）"
        panel.showsHiddenFiles = true
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        if panel.runModal() == .OK, let url = panel.url {
            appState.settings.authFilePath = url.path
        }
    }

    private func pickAudioFileForVoiceprint() {
        let panel = NSOpenPanel()
        panel.title = "选择包含该说话人清晰人声的音频文件（建议 3~30 秒）"
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

    private func runConnectionTest() {
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

    private var codexModelOptions: [String] {
        var list = discoveredCodexModels.isEmpty ? AppSettings.suggestedCodexModels : discoveredCodexModels
        let current = appState.settings.codexModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !current.isEmpty && !list.contains(current) {
            list.insert(current, at: 0)
        }
        return list
    }

    private func refreshCodexModels() {
        let catalog = AuthManager.shared.discoverLocalCodexCatalog(authFilePath: appState.settings.authFilePath)
        discoveredCodexModels = catalog.availableModels
        if appState.settings.codexModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let def = catalog.defaultModel {
            appState.settings.codexModel = def
        }
    }

    private func refreshPermissions() {
        micStatus = MicrophoneCapture.authorizationStatus()
        speechStatus = SFSpeechRecognizer.authorizationStatus()
        calendarAuthorized = CalendarContextService.shared.isAuthorized()
        launchAtLogin = LaunchAtLoginService.isEnabled
    }
}

// MARK: - Minimalist Doubao-Style Setting Card & Controls

private struct SettingsCard<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.textMuted)
                }
            }
            .padding(.leading, 2)

            content()
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppTheme.elevatedSurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(AppTheme.subtleBorder, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.015), radius: 4, y: 1)
        }
    }
}

private struct SettingsToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.textPrimary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(AppTheme.brandPrimary)
        }
    }
}

private struct CleanInputBox: View {
    let placeholder: String
    @Binding var text: String
    var onSubmitAction: (() -> Void)? = nil

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 12.5))
            .foregroundStyle(AppTheme.textPrimary)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppTheme.softCardBg))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(AppTheme.subtleBorder, lineWidth: 1))
            .onSubmit { onSubmitAction?() }
    }
}

private struct CleanSecureBox: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        SecureField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 12.5))
            .foregroundStyle(AppTheme.textPrimary)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppTheme.softCardBg))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(AppTheme.subtleBorder, lineWidth: 1))
    }
}

private struct CleanMenuPicker: View {
    let title: String
    let options: [String]
    @Binding var selection: String

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { opt in
                Button {
                    selection = opt
                } label: {
                    if selection == opt {
                        Label(opt, systemImage: "checkmark")
                    } else {
                        Text(opt)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(title)
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
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

private struct CleanPrimaryButton: View {
    let title: String
    var icon: String? = nil
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .padding(.vertical, 6.5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(disabled ? AppTheme.brandPrimary.opacity(0.38) : AppTheme.brandPrimary)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

private struct CleanSmallButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5.5)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppTheme.softCardBg))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(AppTheme.subtleBorder, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct CleanChipButton: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    init(_ title: String, selected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.selected = selected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? AppTheme.brandPrimary : AppTheme.textSecondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(selected ? AppTheme.brandSoftFill : AppTheme.softCardBg))
                .overlay(Capsule().strokeBorder(selected ? Color.clear : AppTheme.subtleBorder, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
