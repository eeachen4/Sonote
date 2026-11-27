import SwiftUI
import SonoteCore

// MARK: - Page 3: Local ECAPA-TDNN Voiceprint Library

extension SettingsView {

    var voiceprintLibraryPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(
                title: L("录入新声纹", "Enroll New Voiceprint"),
                subtitle: L("本地提取 192 维 ECAPA-TDNN 向量，数据仅保存在本机", "Extracts 192-dim ECAPA-TDNN embeddings 100% offline on your Mac")
            ) {
                VStack(alignment: .leading, spacing: 11) {
                    HStack(spacing: 8) {
                        CleanInputBox(placeholder: L("姓名（如：林致远 / Alex）", "Name (e.g. Alex)"), text: $newVoiceprintName)
                        CleanInputBox(placeholder: L("角色备注（可选）", "Role (Optional)"), text: $newVoiceprintRole)
                            .frame(width: 150)
                    }

                    Toggle(L("标记为本人声纹（自动同步为本机发言人名称）", "Mark as my voice (syncs to local speaker name)"), isOn: $newVoiceprintIsSelf)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.textSecondary)

                    HStack(spacing: 8) {
                        CleanPrimaryButton(
                            title: appState.isEnrollingVoiceprint ? L("正在录入...", "Enrolling...") : L("麦克风录音 5 秒建档", "Record 5s via Mic"),
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

                        CleanSmallButton(L("从音频文件建档...", "Import Audio Sample...")) {
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
                                Text(theme.isEnglish ? "Capturing \(Int(appState.voiceprintEnrollProgress * 100))%" : "采集中 \(Int(appState.voiceprintEnrollProgress * 100))%")
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppTheme.textSecondary)
                                Spacer()
                                Text(theme.isEnglish ? "Level \(Int(min(100, appState.voiceprintEnrollLevel * 100)))%" : "音量 \(Int(min(100, appState.voiceprintEnrollLevel * 100)))%")
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

            SettingsCard(
                title: theme.isEnglish ? "Enrolled Voiceprints (\(appState.voiceprints.count))" : "已建档声纹（\(appState.voiceprints.count) 人）",
                subtitle: L("也可在历史会议逐字稿中点击说话人改名并勾选「记住声纹」持续优化", "You can also rename any speaker in past transcripts and check 'Remember voiceprint'")
            ) {
                if appState.voiceprints.isEmpty {
                    Text(L("暂无已录入声纹。录入后，开会或导入音视频时将自动识别并标出真实姓名。", "No voiceprints yet. Enrolled speakers are automatically identified across meetings."))
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
                                            Text(L("本人", "Me"))
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
                                    Text(theme.isEnglish ? "\(profile.sampleCount) sample(s) · Synced to ASR hotwords" : "已融合 \(profile.sampleCount) 份样本 · 自动同步至热词")
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
                                .help(L("删除声纹", "Delete Voiceprint"))
                            }
                        }
                    }
                }
            }

            SettingsCard(title: L("匹配灵敏度", "Matching Sensitivity")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        fieldLabel(L("余弦相似度阈值", "Cosine Similarity Threshold"), hint: L("越低越易命中，越高越防误认（推荐 0.56）", "Lower matches more easily, higher avoids false positives (0.56 recommended)"))
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
}
