import SwiftUI
import AppKit
import SonoteCore

// MARK: - Page 0: General (Language, Appearance, Accent Color, Typography, Startup & Updates)

extension SettingsView {

    var generalPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Card 1: Appearance & Accent Theme
            SettingsCard(
                title: L("外观与主题", "Appearance & Theme"),
                subtitle: L("实时切换浅色、深色或跟随系统，并自定义全局主题强调色", "Switch Light, Dark, or Auto appearance and customize your global accent color in real time")
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel(L("主题模式", "Appearance"))
                        HStack(spacing: 10) {
                            ForEach(AppAppearanceMode.allCases) { mode in
                                appearancePreviewCard(mode)
                            }
                        }
                    }

                    Divider().overlay(AppTheme.divider)

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

                    Divider().overlay(AppTheme.divider)

                    HStack(spacing: 12) {
                        fieldLabel(
                            L("新手快速设置引导", "Quick Setup Guide"),
                            hint: L("重新在主页显示权限、本地模型与 AI 配置体检卡片", "Show the 3-step permissions, ASR & AI checklist card on Home")
                        )
                        Spacer()
                        CleanSmallButton(L("重新显示引导", "Show Guide")) {
                            appState.settings.hasCompletedOnboarding = false
                        }
                        .disabled(!appState.settings.hasCompletedOnboarding)
                    }
                }
            }

            // Card 4: About Sonote & GitHub Release Update Checker
            SettingsCard(title: L("关于与更新", "About & Updates")) {
                VStack(alignment: .leading, spacing: 12) {
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
                                Text("v\(UpdateCheckerService.installedVersion)")
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

                        CleanSmallButton(isCheckingUpdates ? L("检查中...", "Checking...") : L("检查更新", "Check Updates")) {
                            checkForAppUpdates()
                        }
                        .disabled(isCheckingUpdates)

                        CleanSmallButton(L("数据目录", "Data")) {
                            NSWorkspace.shared.open(MeetingStore.shared.baseDirectory)
                        }

                        CleanSmallButton("GitHub") {
                            if let url = URL(string: "https://github.com/eeachen4/Sonote") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }

                    if let updateResult {
                        HStack(spacing: 8) {
                            Image(systemName: updateResult.hasUpdate ? "arrow.down.circle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(updateResult.hasUpdate ? AppTheme.brandPrimary : AppTheme.successGreen)
                            Text(
                                updateResult.hasUpdate
                                    ? L("发现新版本 v\(updateResult.latestVersion)（当前 v\(updateResult.currentVersion)）", "Update available: v\(updateResult.latestVersion) (current v\(updateResult.currentVersion))")
                                    : L("当前已是最新版本 v\(updateResult.currentVersion)", "You're up to date (v\(updateResult.currentVersion))")
                            )
                            .font(.system(size: 11.5))
                            .foregroundStyle(AppTheme.textPrimary)
                            Spacer()
                            if updateResult.hasUpdate, let url = URL(string: updateResult.releaseURL) {
                                CleanPrimaryButton(title: L("前往下载", "Download"), icon: "arrow.up.right") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppTheme.softCardBg))
                    } else if let updateError {
                        Text(updateError)
                            .font(.system(size: 11.5))
                            .foregroundStyle(AppTheme.recordingRed)
                    }
                }
            }
        }
    }

    func appearancePreviewCard(_ mode: AppAppearanceMode) -> some View {
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

    func miniWindowMock(isDark: Bool, accent: Color) -> some View {
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
}
