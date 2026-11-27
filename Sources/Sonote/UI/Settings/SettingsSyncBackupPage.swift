import SwiftUI
import AppKit
import SonoteCore

// MARK: - Page 6: Obsidian/Markdown Sync, Webhooks & Portable Archive Backup / Restore

extension SettingsView {

    var syncBackupPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(
                title: L("Obsidian / 本地 Markdown 目录同步", "Obsidian / Local Markdown Folder Sync"),
                subtitle: L("自动将会议纪要以带 YAML Frontmatter 的 .md 文件写入 Obsidian Vault、Logseq 或任意本地笔记目录", "Automatically write structured .md notes with YAML frontmatter to your Obsidian Vault or local folder")
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        CleanInputBox(
                            placeholder: L("~/Documents/ObsidianVault/Meetings", "~/Documents/ObsidianVault/Meetings"),
                            text: $appState.settings.obsidianVaultPath
                        )
                        CleanSmallButton(L("选择文件夹...", "Choose Folder...")) {
                            pickObsidianVaultFolder()
                        }
                    }

                    SettingsToggleRow(
                        title: L("会议总结完成后自动同步 .md 笔记", "Auto-Sync .md Note After Meeting Summary"),
                        subtitle: L("同场会议重新生成纪要时按 meeting_id 原地更新，不产生重复文件", "Updates existing note in-place by meeting_id when regenerating minutes"),
                        isOn: $appState.settings.autoSyncMarkdownFolder
                    )

                    Divider().overlay(AppTheme.divider)

                    HStack(spacing: 10) {
                        CleanPrimaryButton(
                            title: L("立即同步全部会议", "Sync All Meetings Now"),
                            icon: "folder.badge.plus",
                            disabled: appState.settings.obsidianVaultPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || appState.meetings.isEmpty
                        ) {
                            let res = appState.syncAllMeetingsToMarkdownFolder()
                            if let err = res.errorMessage {
                                obsidianSyncFeedback = L("同步失败：\(err)", "Sync failed: \(err)")
                            } else {
                                obsidianSyncFeedback = L("已同步 \(res.syncedCount) 场会议到目标目录", "Synced \(res.syncedCount) meetings to folder")
                            }
                        }

                        if !appState.settings.obsidianVaultPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            CleanSmallButton(L("在访达中打开", "Reveal in Finder")) {
                                let path = (appState.settings.obsidianVaultPath as NSString).expandingTildeInPath
                                NSWorkspace.shared.open(URL(fileURLWithPath: path))
                            }
                        }
                        Spacer()
                    }

                    if let msg = obsidianSyncFeedback {
                        Text(msg)
                            .font(.system(size: 11.5))
                            .foregroundStyle(msg.contains("失败") || msg.lowercased().contains("failed") ? AppTheme.recordingRed : AppTheme.successGreen)
                    }
                }
            }

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

    private func pickObsidianVaultFolder() {
        let panel = NSOpenPanel()
        panel.title = L("选择 Obsidian Vault 或本地 Markdown 笔记目录", "Choose Obsidian Vault or Markdown Folder")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            appState.settings.obsidianVaultPath = url.path
        }
    }
}
