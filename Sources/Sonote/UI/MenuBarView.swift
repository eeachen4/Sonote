import SwiftUI
import SonoteCore

struct MenuBarView: View {
    @ObservedObject var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    private var statusBadgeText: String {
        guard appState.authInspection.isValid else { return "待配置" }
        switch appState.settings.authMode {
        case .localAuthFile: return "Codex 已就绪"
        case .apiKey:
            return AuthManager.isLocalhostEndpoint(appState.settings.apiBaseURL) ? "本地服务就绪" : "OpenAI 已就绪"
        case .anthropicClaude: return "Claude 已就绪"
        case .googleGemini: return "Gemini 已就绪"
        case .localMLX: return "离线 MLX 就绪"
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
                        Text("开始新录音")
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
                        Label("待办 \(appState.openActionItemsCount)", systemImage: "checklist")
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.brandPrimary)
                    }
                    Spacer()
                    if !appState.todayTokenUsage.isEmpty {
                        Text("今日 \(appState.todayTokenUsage.formattedCompact)t")
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
                menuRow(title: "打开主窗口", icon: "macwindow") {
                    if appState.isRecordingOrPaused {
                        appState.expandFromMiniWindowToMain()
                    } else {
                        openMainWorkspace()
                    }
                }
                if appState.isRecordingOrPaused {
                    menuRow(title: appState.isCapsuleVisible ? "展开为双栏大窗" : "收起为左上角小窗", icon: "pip") {
                        if appState.isCapsuleVisible {
                            appState.expandFromMiniWindowToMain()
                        } else {
                            appState.collapseToTopLeftMiniWindow()
                        }
                    }
                }
                menuRow(title: "模拟加入会议提醒", icon: "bell") {
                    appState.triggerSimulatedMeetingPrompt()
                }
                menuRow(title: "偏好设置...", icon: "gearshape") {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }
            }

            Divider().overlay(AppTheme.divider)

            HStack {
                Text(appState.settings.autoDetectMeetings ? "自动检测会议中" : "自动检测已关闭")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(12)
        .frame(width: 256)
        .background(Color.white)
        .preferredColorScheme(.light)
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
