import SwiftUI
import SonoteCore

// MARK: - Page 6: Webhooks & Portable Archive Backup / Restore

extension SettingsView {

    var syncBackupPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(
                title: L("飞书 / 钉钉 / Notion Webhook 一键推送", "Feishu / DingTalk / Custom JSON Webhooks"),
                subtitle: L("配置后可在任意会议纪要底部「导出 / 复制」菜单一键推送结构化卡片", "Push structured meeting cards directly from any meeting's Export menu")
            ) {
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
                        fieldLabel(L("Webhook 地址", "Webhook URL"))
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
                            fieldLabel(L("加签密钥（可选）", "Signing Secret (Optional)"), hint: L("开启机器人 HMAC-SHA256 签名校验时填写，加密存于钥匙串", "HMAC-SHA256 secret stored securely in macOS Keychain"))
                            CleanSecureBox(placeholder: L("留空表示未开启签名校验", "Leave blank if signing is disabled"), text: $appState.settings.webhookSecret)
                        }
                    }

                    HStack(spacing: 10) {
                        CleanPrimaryButton(
                            title: appState.isPushingWebhook ? L("发送中...", "Sending...") : L("发送测试卡片", "Send Test Card"),
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

            SettingsCard(
                title: L("数据全库备份与换机迁移", "Full Library Backup & Migration"),
                subtitle: L("打包所有会议纪要、逐字稿、声纹库、自定义模板、词典与 Token 账本（不含明文 API 密钥）", "Exports meetings, voiceprints, templates, glossary & ledger (never includes API keys)")
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsToggleRow(
                        title: L("备份时包含录音音频文件 (.m4a)", "Include Recorded Audio Files (.m4a)"),
                        subtitle: L("关闭时备份包仅数百 KB；开启后可完整迁移音文同步回放录音", "Off keeps archives tiny (~KB); On preserves synced playback audio"),
                        isOn: $includeAudioInBackup
                    )

                    Divider().overlay(AppTheme.divider)

                    HStack(spacing: 10) {
                        CleanPrimaryButton(title: L("导出全库备份 (.zip)", "Export Backup (.zip)"), icon: "square.and.arrow.up") {
                            backupFeedback = appState.exportBackupArchiveWithSavePanel(includeAudio: includeAudioInBackup)
                        }
                        CleanSmallButton(L("从备份恢复并合并...", "Restore & Merge...")) {
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
}
