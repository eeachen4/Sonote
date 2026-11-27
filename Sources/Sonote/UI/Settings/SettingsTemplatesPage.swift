import SwiftUI
import SonoteCore

// MARK: - Page 4: Summary Templates & Live Cadence

extension SettingsView {

    var templatesPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(title: L("实时提炼与默认风格", "Live Summary & Default Style")) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        fieldLabel(L("默认场景模板", "Default Template"), hint: L("新建会议与导入音视频时默认采用", "Applied to new recordings and imported files"))
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

                    HStack {
                        fieldLabel(
                            L("纪要输出语言", "Summary Output Language"),
                            hint: L("支持英文会议直接输出简体中文纪要，或中文会议输出英文纪要", "Summarize English calls in Chinese, or Chinese calls in English")
                        )
                        Spacer()
                        Menu {
                            ForEach(MinutesOutputLanguage.allCases) { lang in
                                Button(lang.displayName) { appState.settings.minutesOutputLanguage = lang }
                            }
                        } label: {
                            cleanMenuLabel(appState.settings.minutesOutputLanguage.displayName)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }

                    Divider().overlay(AppTheme.divider)

                    SettingsToggleRow(
                        title: L("会中自动增量提炼要点", "Incremental Live Summarization"),
                        subtitle: L("仅发送新增片段，相比全量总结节省 60%+ Token", "Sends only new segments, saving 60%+ tokens"),
                        isOn: $appState.settings.liveSummaryEnabled
                    )

                    if appState.settings.liveSummaryEnabled {
                        Divider().overlay(AppTheme.divider)
                        HStack {
                            fieldLabel(L("实时刷新间隔", "Refresh Interval"))
                            Spacer()
                            HStack(spacing: 8) {
                                Text(theme.isEnglish ? "Every \(appState.settings.liveSummaryIntervalSeconds)s" : "每 \(appState.settings.liveSummaryIntervalSeconds) 秒")
                                    .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                                    .foregroundStyle(AppTheme.textPrimary)
                                Stepper("", value: $appState.settings.liveSummaryIntervalSeconds, in: 15...120, step: 5)
                                    .labelsHidden()
                            }
                        }
                    }

                    Divider().overlay(AppTheme.divider)

                    VStack(alignment: .leading, spacing: 5) {
                        fieldLabel(L("全局纪要偏好（可选）", "Global Style Preference (Optional)"), hint: L("附加到每次纪要生成提示词末尾", "Appended to every summary prompt"))
                        CleanInputBox(placeholder: L("例如：偏研发评审风格，重点列出技术方案对比与风险", "e.g. Focus on architecture tradeoffs, milestones & risks"), text: $appState.settings.customMinutesPrompt)
                    }
                }
            }

            SettingsCard(
                title: L("自定义纪要模板", "Custom Summary Templates"),
                subtitle: L("新增后可在任意会议右上角的模板菜单中一键切换并重新生成", "Switch templates anytime in a meeting's top-right menu")
            ) {
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
                        CleanInputBox(placeholder: L("新模板名称（如：研发周会问题跟踪模板）", "Template name (e.g. Weekly Engineering Sync)"), text: $newTemplateName)
                        CleanInputBox(placeholder: L("提炼规则（如：按模块输出问题表、P0/P1 风险等级与流程决议）", "Prompt instructions (e.g. Output blockers by module & P0/P1 risks)"), text: $newTemplateGuidance)
                        HStack {
                            Spacer()
                            CleanPrimaryButton(
                                title: L("新增模板", "Add Template"),
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
}
