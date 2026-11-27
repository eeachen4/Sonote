import SwiftUI
import SonoteCore

// MARK: - Page 5: Meeting Auto-Detection, Calendar & Global Hotkeys

extension SettingsView {

    var detectionPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(title: L("自动提醒与系统集成", "Auto-Detection & Calendar")) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsToggleRow(
                        title: L("加入会议自动弹窗提醒", "Prompt When Joining a Meeting"),
                        subtitle: L("基于 CoreAudio 音频活动检测，无需辅助功能或录屏权限", "Uses CoreAudio detection without Accessibility or Screen Recording"),
                        isOn: $appState.settings.autoDetectMeetings
                    )

                    Divider().overlay(AppTheme.divider)

                    SettingsToggleRow(
                        title: L("检测浏览器网页会议", "Detect Browser Calls"),
                        subtitle: L("支持 Chrome / Safari / Arc / Edge 麦克风通话", "Detects Google Meet / Zoom web calls in Chrome, Safari, Arc & Edge"),
                        isOn: $appState.settings.detectBrowserCalls
                    )

                    Divider().overlay(AppTheme.divider)

                    SettingsToggleRow(
                        title: L("会议结束后提示停止并生成纪要", "Prompt to Stop When Call Ends"),
                        subtitle: L("退出通话软件后自动提醒收尾", "Suggests wrapping up when your meeting app exits"),
                        isOn: $appState.settings.promptOnMeetingEnd
                    )

                    Divider().overlay(AppTheme.divider)

                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(L("联动 macOS 日历", "macOS Calendar Sync"))
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(AppTheme.textPrimary)
                                if calendarAuthorized {
                                    Text(L("已授权", "Granted"))
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(AppTheme.successGreen)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1.5)
                                        .background(Capsule().fill(AppTheme.successGreen.opacity(0.12)))
                                } else {
                                    CleanSmallButton(L("授权日历", "Grant Access")) {
                                        Task {
                                            _ = await CalendarContextService.shared.requestAccessIfNeeded()
                                            refreshPermissions()
                                        }
                                    }
                                }
                            }
                            Text(L("自动带入当前日程标题并将参会人姓名注入热词", "Pulls active event titles & attendee names into ASR hotwords"))
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
                        CleanSmallButton(L("模拟「加入腾讯会议」弹窗", "Test Meeting Prompt")) {
                            appState.triggerSimulatedMeetingPrompt()
                        }
                        Text(L("测试桌面右上角悬浮卡片效果", "Preview the top-right floating HUD prompt"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(AppTheme.textMuted)
                        Spacer()
                    }
                }
            }

            SettingsCard(
                title: L("系统级全局快捷键", "Global Hotkeys"),
                subtitle: L("全屏开会时依然生效，无需辅助功能权限", "Works even in fullscreen calls without Accessibility permission")
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsToggleRow(
                        title: L("启用全局快捷键", "Enable Global Hotkeys"),
                        subtitle: {
                            let p = appState.settings.globalHotKeyPreset.symbolPrefix
                            return theme.isEnglish
                                ? "\(p)R Toggle Recording  ·  \(p)M Show / Hide Sonote"
                                : "\(p)R 启停录音  ·  \(p)M 呼出 / 收起 Sonote 窗口"
                        }(),
                        isOn: $appState.settings.enableGlobalHotKeys
                    )

                    if appState.settings.enableGlobalHotKeys {
                        Divider().overlay(AppTheme.divider)
                        HStack {
                            fieldLabel(L("修饰键组合", "Modifier Preset"))
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

            SettingsCard(title: L("监控列表与忽略黑名单", "Monitored & Ignored Apps")) {
                VStack(alignment: .leading, spacing: 11) {
                    VStack(alignment: .leading, spacing: 6) {
                        fieldLabel(L("忽略应用黑名单", "Ignored Bundle IDs"), hint: L("以下 Bundle ID 的音频活动不会弹出会议提醒", "Audio activity from these apps will never trigger prompts"))
                        HStack(spacing: 6) {
                            CleanInputBox(placeholder: L("输入 Bundle ID（如 com.example.app）", "Enter Bundle ID (e.g. com.example.app)"), text: $newIgnoredBundleID)
                            CleanSmallButton(L("添加", "Add")) {
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
                            Text(theme.isEnglish ? "Monitored Meeting Apps (\(appState.settings.monitoredBundleIDs.count))" : "已启用监控的会议软件（\(appState.settings.monitoredBundleIDs.count) 款）")
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
}
