import SwiftUI
import SonoteCore

struct MenuBarView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    private var statusBadgeText: String {
        guard appState.authInspection.isValid else { return L("待配置", "Setup Required") }
        switch appState.settings.authMode {
        case .localAuthFile: return L("Codex 已就绪", "Codex Ready")
        case .apiKey:
            return AuthManager.isLocalhostEndpoint(appState.settings.apiBaseURL)
                ? L("本地服务就绪", "Local Ready")
                : L("OpenAI 已就绪", "OpenAI Ready")
        case .deepSeek: return L("DeepSeek 已就绪", "DeepSeek Ready")
        case .qwenDashScope: return L("通义千问已就绪", "Qwen Ready")
        case .domesticCloud:
            let name = appState.settings.domesticProvider.shortName
            return theme.isEnglish ? "\(name) Ready" : "\(name) 已就绪"
        case .anthropicClaude: return L("Claude 已就绪", "Claude Ready")
        case .googleGemini: return L("Gemini 已就绪", "Gemini Ready")
        case .localMLX: return L("离线 MLX 就绪", "Offline MLX")
        }
    }

    private var recordShortcutLabel: String {
        if appState.settings.enableGlobalHotKeys {
            return "\(appState.settings.globalHotKeyPreset.symbolPrefix)R"
        }
        return "⌘⇧R"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(appState.isRecording ? AppTheme.brandPrimary : AppTheme.successGreen)
                    .frame(width: 8, height: 8)
                Text("Sonote")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text("声记")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(AppTheme.textMuted)
                Spacer()
                Text(statusBadgeText)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            if let active = appState.activeRecordingMeeting {
                HStack(spacing: 10) {
                    Text(active.formattedDuration)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppTheme.textPrimary)
                    Spacer()
                    Button {
                        appState.toggleSubtitleBar()
                    } label: {
                        Image(systemName: appState.isSubtitleBarVisible ? "captions.bubble.fill" : "captions.bubble")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(appState.isSubtitleBarVisible ? AppTheme.brandPrimary : AppTheme.textSecondary)
                            .frame(width: 34, height: 28)
                            .background(Capsule().fill(appState.isSubtitleBarVisible ? AppTheme.brandSoftFill : AppTheme.neutralPill))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(appState.isSubtitleBarVisible ? L("隐藏桌面悬浮字幕条", "Hide Live Subtitle Bar") : L("开启桌面悬浮字幕条", "Show Live Subtitle Bar"))

                    Button {
                        appState.togglePauseRecording()
                    } label: {
                        Image(systemName: appState.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppTheme.brandPrimary)
                            .frame(width: 42, height: 28)
                            .background(Capsule().fill(AppTheme.brandSoftFill))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task { await appState.stopRecordingAndFinalize(generateFinalSummary: true) }
                    } label: {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(AppTheme.textPrimary)
                            .frame(width: 9, height: 9)
                            .frame(width: 42, height: 28)
                            .background(Capsule().fill(AppTheme.neutralPill))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(AppTheme.softCardBg))
            } else {
                Button {
                    Task {
                        await appState.startNewMeeting()
                        if !appState.settings.showFloatingCapsuleWhileRecording {
                            openMainWorkspace()
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 12))
                        Text(L("开始新录音", "Start Recording"))
                        Spacer()
                        Text(recordShortcutLabel)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.brandPrimary))
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }

            // Quiet quick-glance stats strip (open todos & today token usage)
            if appState.openActionItemsCount > 0 || !appState.todayTokenUsage.isEmpty {
                HStack(spacing: 8) {
                    if appState.openActionItemsCount > 0 {
                        Label(
                            theme.isEnglish ? "Todos \(appState.openActionItemsCount)" : "待办 \(appState.openActionItemsCount)",
                            systemImage: "checklist"
                        )
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.brandPrimary)
                    }
                    Spacer()
                    if !appState.todayTokenUsage.isEmpty {
                        Text(theme.isEnglish ? "Today \(appState.todayTokenUsage.formattedCompact)t" : "今日 \(appState.todayTokenUsage.formattedCompact)t")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(AppTheme.textMuted)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7).fill(AppTheme.softCardBg))
            }

            Divider().overlay(AppTheme.divider)

            VStack(spacing: 2) {
                menuRow(title: L("打开主窗口", "Open Sonote"), icon: "macwindow") {
                    if appState.isRecordingOrPaused {
                        appState.expandFromMiniWindowToMain()
                    } else {
                        openMainWorkspace()
                    }
                }
                if appState.isRecordingOrPaused {
                    menuRow(title: appState.isCapsuleVisible ? L("展开为双栏大窗", "Expand Workspace") : L("收起为左上角小窗", "Minimize to Capsule"), icon: "pip") {
                        if appState.isCapsuleVisible {
                            appState.expandFromMiniWindowToMain()
                        } else {
                            appState.collapseToTopLeftMiniWindow()
                        }
                    }
                }
                menuRow(title: L("模拟加入会议提醒", "Simulate Meeting Prompt"), icon: "bell") {
                    appState.triggerSimulatedMeetingPrompt()
                }
                menuRow(title: L("偏好设置...", "Settings..."), icon: "gearshape") {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }
            }

            Divider().overlay(AppTheme.divider)

            HStack {
                Text(appState.settings.autoDetectMeetings ? L("自动检测会议中", "Auto-detecting meetings") : L("自动检测已关闭", "Auto-detect off"))
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
                Button(L("退出", "Quit")) { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(12)
        .frame(width: 256)
        .background(AppTheme.elevatedSurface)
        .tint(AppTheme.brandPrimary)
        .preferredColorScheme(theme.preferredColorScheme)
        .onAppear {
            appState.swiftUIOpenMainWindow = { openWindow(id: "main") }
        }
    }

    private func openMainWorkspace() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
    }

    private func menuRow(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .frame(width: 16)
                    .foregroundStyle(AppTheme.textSecondary)
                Text(title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
