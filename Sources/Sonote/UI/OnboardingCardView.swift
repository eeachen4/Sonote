import SwiftUI
import AVFoundation
import SonoteCore

/// Minimalist 3-step First-Launch Onboarding Card shown on Home until dismissed:
/// 1. Permissions (Mic & System Audio)
/// 2. Local MLX Qwen3-ASR Engine & optional CN Mirror
/// 3. AI Summary Provider (DeepSeek / Qwen / Built-in Offline MLX)
struct OnboardingCardView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var theme = ThemeManager.shared
    let onOpenSettings: () -> Void

    @State private var micStatus: AVAuthorizationStatus = MicrophoneCapture.authorizationStatus()

    private var isASRCached: Bool {
        MLXQwen3ASREngine.isModelCachedLocally(modelID: appState.settings.mlxQwen3ModelID)
    }

    private var isMicGranted: Bool {
        micStatus == .authorized
    }

    private var isAIReady: Bool {
        appState.authInspection.isValid
    }

    private var completedSteps: Int {
        (isMicGranted ? 1 : 0) + (isASRCached ? 1 : 0) + (isAIReady ? 1 : 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppTheme.brandSoftFill)
                        .frame(width: 28, height: 28)
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.brandPrimary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(L("欢迎使用 Sonote · 3 步快速就绪 (\(completedSteps)/3)", "Welcome to Sonote · Quick Setup (\(completedSteps)/3)"))
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(L("首次使用完成权限、语音引擎与 AI 模型配置后，开会即可自动弹出记录", "Finish permissions, local ASR & AI model once for zero-friction meeting minutes"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        appState.settings.hasCompletedOnboarding = true
                    }
                } label: {
                    Text(completedSteps == 3 ? L("完成引导", "Done") : L("跳过", "Dismiss"))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(completedSteps == 3 ? AppTheme.brandPrimary : AppTheme.textMuted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(completedSteps == 3 ? AppTheme.brandSoftFill : AppTheme.softCardBg))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                // Step 1: Permissions
                stepTile(
                    index: "1",
                    title: L("音频权限", "Audio Access"),
                    detail: isMicGranted
                        ? L("麦克风已授权 · 开始录音时授权系统声音", "Mic ready · System audio prompts on start")
                        : L("需要麦克风与「仅系统音频录制」权限", "Grant Mic & System Audio Recording"),
                    done: isMicGranted
                ) {
                    HStack(spacing: 6) {
                        if !isMicGranted {
                            onboardingButton(L("授权麦克风", "Grant Mic"), primary: true) {
                                Task {
                                    _ = await MicrophoneCapture.requestPermission()
                                    micStatus = MicrophoneCapture.authorizationStatus()
                                }
                            }
                        }
                        onboardingButton(L("系统音频", "Audio Prefs"), primary: false) {
                            appState.openPrivacySettings("Privacy_AudioCapture")
                        }
                    }
                }

                // Step 2: Local MLX ASR
                stepTile(
                    index: "2",
                    title: L("本地语音模型", "Local MLX ASR"),
                    detail: isASRCached
                        ? L("Qwen3-ASR 权重已缓存，离线秒开", "Qwen3-ASR weights cached locally")
                        : (appState.mlxModelState.isBusy ? appState.mlxModelState.statusText : L("首次使用建议预下载（可选国内镜像）", "Preload Qwen3-ASR weights once")),
                    done: isASRCached
                ) {
                    HStack(spacing: 6) {
                        if !isASRCached {
                            onboardingButton(
                                appState.mlxModelState.isBusy ? L("下载中...", "Loading...") : L("预下载模型", "Preload"),
                                primary: true,
                                disabled: appState.mlxModelState.isBusy
                            ) {
                                Task { await appState.preloadMLXQwen3Model() }
                            }
                            onboardingButton(
                                appState.settings.mlxHuggingFaceHost.contains("hf-mirror") ? L("已切国内镜像", "CN Mirror On") : L("国内镜像", "CN Mirror"),
                                primary: false
                            ) {
                                let useMirror = !appState.settings.mlxHuggingFaceHost.contains("hf-mirror")
                                appState.settings.mlxHuggingFaceHost = useMirror ? "https://hf-mirror.com" : "https://huggingface.co"
                            }
                        } else {
                            onboardingButton(L("调整模型", "Configure"), primary: false) {
                                onOpenSettings()
                            }
                        }
                    }
                }

                // Step 3: AI Summary Model
                stepTile(
                    index: "3",
                    title: L("AI 纪要模型", "Summary AI"),
                    detail: isAIReady
                        ? L("已就绪 · \(appState.settings.authMode.displayName)", "Ready · \(appState.settings.authMode.displayName)")
                        : L("配置 DeepSeek / 千问，或零门槛启用离线 MLX", "Add DeepSeek / Qwen or use offline MLX"),
                    done: isAIReady
                ) {
                    HStack(spacing: 6) {
                        onboardingButton(L("配置模型", "Configure"), primary: !isAIReady) {
                            onOpenSettings()
                        }
                        if appState.settings.authMode != .localMLX {
                            onboardingButton(L("离线 MLX", "Offline MLX"), primary: false) {
                                appState.settings.authMode = .localMLX
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.elevatedSurface.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AppTheme.mindMapLine, lineWidth: 1)
        )
        .onAppear {
            micStatus = MicrophoneCapture.authorizationStatus()
        }
    }

    private func stepTile<Actions: View>(
        index: String,
        title: String,
        detail: String,
        done: Bool,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: done ? "checkmark.circle.fill" : "\(index).circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(done ? AppTheme.successGreen : AppTheme.brandPrimary)
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
            }

            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(2)
                .frame(minHeight: 28, alignment: .topLeading)

            actions()
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(AppTheme.softCardBg))
    }

    private func onboardingButton(_ title: String, primary: Bool, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(primary ? Color.white : AppTheme.textPrimary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4.5)
                .background(
                    Capsule().fill(primary ? AppTheme.brandPrimary : AppTheme.elevatedSurface)
                )
                .overlay(
                    Capsule().strokeBorder(primary ? Color.clear : AppTheme.subtleBorder, lineWidth: 1)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.55 : 1)
    }
}
