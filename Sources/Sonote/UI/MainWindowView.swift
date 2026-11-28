import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SonoteCore

/// Ultra-clean Doubao Work main window:
/// - Home Page (default): calm white editorial home with quick actions, live detection status & grouped recent meetings
/// - Live Recording View: exact 2-column Doubao Work live transcript + real-time mind-map/outline summary
/// - Completed Document View: serene pure-white summary page with light backdrop & back navigation
struct MainWindowView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    @State private var searchText: String = ""
    @State private var selectedTagFilter: String? = nil
    @State private var showPasteSheet: Bool = false
    @State private var showGlobalTodosSheet: Bool = false
    @State private var showCrossMeetingAISheet: Bool = false
    @State private var isDropTargeted: Bool = false
    @State private var isBatchSelecting: Bool = false
    @State private var selectedMeetingIDs: Set<UUID> = []
    @State private var showBatchTagPopover: Bool = false
    @State private var batchTagDraft: String = ""
    @State private var showBatchDeleteConfirm: Bool = false
    @FocusState private var isHomeSearchFocused: Bool

    var body: some View {
        Group {
            if let meeting = appState.selectedMeeting {
                MeetingWorkspaceView(
                    meeting: meeting,
                    appState: appState,
                    onBackHome: {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            appState.selectedMeetingID = nil
                        }
                    },
                    onCloseWindow: { closeCurrentWindow() }
                )
            } else {
                homeView
            }
        }
        .frame(minWidth: 740, minHeight: 520)
        .tint(AppTheme.brandPrimary)
        .preferredColorScheme(theme.preferredColorScheme)
        .background(MainWindowAccessor { window in
            appState.registerMainWindow(window)
        })
        .onAppear {
            appState.swiftUIOpenMainWindow = { openWindow(id: "main") }
        }
        .sheet(isPresented: $showPasteSheet) {
            PasteTranscriptSheet(appState: appState, isPresented: $showPasteSheet)
        }
        .sheet(isPresented: $showGlobalTodosSheet) {
            GlobalActionItemsSheet(appState: appState, isPresented: $showGlobalTodosSheet) { meetingID in
                withAnimation(.easeInOut(duration: 0.16)) {
                    appState.selectedMeetingID = meetingID
                }
            }
        }
        .sheet(isPresented: $showCrossMeetingAISheet) {
            CrossMeetingAskAISheet(appState: appState, isPresented: $showCrossMeetingAISheet) { meetingID in
                withAnimation(.easeInOut(duration: 0.16)) {
                    appState.selectedMeetingID = meetingID
                }
            }
        }
    }

    // MARK: - Doubao-Style Serene Home Page

    private var homeView: some View {
        ZStack {
            DoubaoSoftLightBackdrop()

            VStack(spacing: 0) {
                // Minimal Top Bar (positioned cleanly to the right of traffic lights)
                HStack(spacing: 12) {
                    Spacer().frame(width: 68)

                    HStack(spacing: 7) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(AppTheme.brandSoftFill)
                                .frame(width: 22, height: 22)
                            Image(systemName: "waveform")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(AppTheme.brandPrimary)
                        }
                        Text("Sonote")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                        Text("声记")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(AppTheme.textMuted)
                    }

                    Spacer()

                    // Global Action Items Pill
                    if !appState.meetings.isEmpty {
                        Button {
                            showGlobalTodosSheet = true
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "checklist")
                                    .font(.system(size: 11))
                                Text(appState.openActionItemsCount > 0 ? "\(L("待办", "Todos")) \(appState.openActionItemsCount)" : L("待办", "Todos"))
                                    .font(.system(size: 11.5, weight: .medium))
                            }
                            .foregroundStyle(appState.openActionItemsCount > 0 ? AppTheme.brandPrimary : AppTheme.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(AppTheme.elevatedSurface.opacity(0.88)))
                            .overlay(Capsule().strokeBorder(AppTheme.subtleBorder, lineWidth: 1))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .help(L("查看全部会议待办并同步到 Apple 提醒事项", "View all action items and sync to Apple Reminders"))

                        // Cross-Meeting AI Synthesis Pill
                        Button {
                            showCrossMeetingAISheet = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 11))
                                Text(L("跨会议问答", "Ask Across"))
                                    .font(.system(size: 11.5, weight: .medium))
                            }
                            .foregroundStyle(AppTheme.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(AppTheme.elevatedSurface.opacity(0.88)))
                            .overlay(Capsule().strokeBorder(AppTheme.subtleBorder, lineWidth: 1))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .help(L("勾选多场会议进行跨周汇总、对比阻塞项进展", "Synthesize summaries and compare blockers across multiple meetings"))
                    }

                    // Quiet AI Auth & Today Token Pill -> Opens Settings
                    Button {
                        openSettings()
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(appState.authInspection.isValid ? AppTheme.successGreen : AppTheme.warningAmber)
                                .frame(width: 6, height: 6)
                            Text(activeModelBadge)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(AppTheme.textSecondary)
                            if !appState.todayTokenUsage.isEmpty {
                                Text(theme.isEnglish ? "· Today \(appState.todayTokenUsage.formattedCompact)t" : "· 今日 \(appState.todayTokenUsage.formattedCompact) tokens")
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppTheme.textMuted)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(AppTheme.elevatedSurface.opacity(0.88)))
                        .overlay(Capsule().strokeBorder(AppTheme.subtleBorder, lineWidth: 1))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(appState.totalTokenUsage.isEmpty ? L("点击配置 AI 凭证与模型", "Configure AI providers and models") : "\(L("历史累计：", "Total: "))\(appState.totalTokenUsage.formattedCompact) tokens（\(appState.totalTokenUsage.detailedSummary)）")

                    Button {
                        openSettings()
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 13.5))
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(AppTheme.elevatedSurface.opacity(0.82)))
                            .overlay(Circle().strokeBorder(AppTheme.subtleBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help(L("偏好设置", "Settings"))
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)

                // Centered Editorial Content Column
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        // Active recording banner if a recording is running while browsing Home
                        if let active = appState.activeRecordingMeeting {
                            activeRecordingBanner(active)
                        }

                        // Crash-recovery banner if a prior recording was abnormally interrupted
                        if let interruptedID = appState.recoveredInterruptedMeetingID,
                           let recovered = appState.meetings.first(where: { $0.id == interruptedID }) {
                            interruptedRecoveryBanner(recovered)
                        }

                        // Live local audio/video import progress banner
                        if let progress = appState.importProgress {
                            importProgressBanner(progress)
                        }

                        // Greeting & Live Meeting Auto-Detection Pill
                        VStack(alignment: .leading, spacing: 10) {
                            Text(timeGreeting)
                                .font(.system(size: 26, weight: .bold))
                                .foregroundStyle(AppTheme.textPrimary)

                            HStack(spacing: 8) {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(appState.settings.autoDetectMeetings ? AppTheme.brandPrimary : AppTheme.textMuted)
                                        .frame(width: 6, height: 6)
                                    Text(appState.settings.autoDetectMeetings
                                         ? L("已开启自动检测 · 加入腾讯会议 / 飞书 / Zoom / 网页会议时自动提醒", "Auto-detection on · Prompts automatically when joining Zoom, Teams, Feishu, or Meet")
                                         : L("自动会议检测已关闭", "Auto meeting detection is off"))
                                        .font(.system(size: 12))
                                        .foregroundStyle(AppTheme.textSecondary)
                                }

                                Button(L("预览提醒", "Preview Prompt")) {
                                    appState.triggerSimulatedMeetingPrompt()
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(AppTheme.brandPrimary)
                            }
                        }
                        .padding(.top, 14)

                        // First-Launch 3-Step Onboarding Card (dismissible)
                        if !appState.settings.hasCompletedOnboarding {
                            OnboardingCardView(appState: appState) {
                                openSettings()
                            }
                        }

                        // Today's Upcoming Calendar Schedule (one-click scheduled recording)
                        if !appState.upcomingCalendarEvents.isEmpty && !appState.isRecordingOrPaused {
                            upcomingCalendarStrip
                        }

                        // Three Clean Primary Action Cards
                        HStack(spacing: 12) {
                            HomeActionCard(
                                icon: "mic.fill",
                                title: L("开始新录音", "Start Recording"),
                                subtitle: L("双轨采集系统与麦声音，会中同步总结", "Dual-track system & mic capture with live minutes"),
                                isPrimary: true
                            ) {
                                Task { await appState.startNewMeeting() }
                            }

                            HomeActionCard(
                                icon: "waveform.badge.plus",
                                title: L("导入音视频", "Import Media"),
                                subtitle: L("支持 .m4a / .mp3 / .mp4 拖入离线转写", "Drop .m4a / .mp3 / .mp4 for offline transcription"),
                                isPrimary: false
                            ) {
                                pickAndImportMediaFile()
                            }

                            HomeActionCard(
                                icon: "doc.text.fill",
                                title: L("文本生成纪要", "Paste Transcript"),
                                subtitle: L("粘贴会议记录或文稿，一键整理导图", "Paste notes or transcripts to generate structured minutes"),
                                isPrimary: false
                            ) {
                                showPasteSheet = true
                            }
                        }

                        // Recent Meetings Section
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .center) {
                                Text(L("最近记录", "Recent Meetings"))
                                    .font(.system(size: 14.5, weight: .semibold))
                                    .foregroundStyle(AppTheme.textPrimary)

                                if !appState.meetings.isEmpty {
                                    Text("\(appState.meetings.count)")
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundStyle(AppTheme.textSecondary)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(AppTheme.neutralPill))
                                }

                                Spacer()

                                if !appState.meetings.isEmpty {
                                    HStack(spacing: 8) {
                                        Button {
                                            withAnimation(.easeInOut(duration: 0.14)) {
                                                isBatchSelecting.toggle()
                                                if !isBatchSelecting { selectedMeetingIDs.removeAll() }
                                            }
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: isBatchSelecting ? "checkmark.circle.fill" : "checklist")
                                                    .font(.system(size: 11))
                                                Text(isBatchSelecting ? L("完成", "Done") : L("批量管理", "Select"))
                                                    .font(.system(size: 11.5, weight: .medium))
                                            }
                                            .foregroundStyle(isBatchSelecting ? AppTheme.brandPrimary : AppTheme.textSecondary)
                                            .padding(.horizontal, 9)
                                            .padding(.vertical, 5)
                                            .background(Capsule().fill(isBatchSelecting ? AppTheme.brandSoftFill : AppTheme.elevatedSurface.opacity(0.88)))
                                            .overlay(Capsule().strokeBorder(isBatchSelecting ? Color.clear : AppTheme.subtleBorder, lineWidth: 1))
                                            .contentShape(Capsule())
                                        }
                                        .buttonStyle(.plain)

                                        HStack(spacing: 6) {
                                            Image(systemName: "magnifyingglass")
                                                .font(.system(size: 11))
                                                .foregroundStyle(AppTheme.textMuted)
                                            TextField(L("搜索标题、逐字稿或待办...", "Search title, transcript, or todos..."), text: $searchText)
                                                .textFieldStyle(.plain)
                                                .font(.system(size: 12))
                                                .focused($isHomeSearchFocused)
                                                .frame(width: theme.isEnglish ? 215 : 175)
                                            if !searchText.isEmpty {
                                                Button {
                                                    searchText = ""
                                                } label: {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .font(.system(size: 11))
                                                        .foregroundStyle(AppTheme.textMuted)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Capsule().fill(AppTheme.inputBackground))
                                        .overlay(Capsule().strokeBorder(AppTheme.inputBorder, lineWidth: 1))
                                    }
                                }
                            }

                            if isBatchSelecting && !filteredMeetings.isEmpty {
                                batchSelectionToolbar
                            }

                            // Tag Filter Bar (visible whenever user has tagged meetings)
                            if !appState.allMeetingTags.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        homeTagFilterPill(L("全部", "All"), isSelected: selectedTagFilter == nil) {
                                            selectedTagFilter = nil
                                        }
                                        ForEach(appState.allMeetingTags, id: \.self) { tag in
                                            homeTagFilterPill("#\(tag)", isSelected: selectedTagFilter == tag) {
                                                selectedTagFilter = (selectedTagFilter == tag) ? nil : tag
                                            }
                                        }
                                    }
                                }
                            }

                            if filteredMeetings.isEmpty {
                                emptyMeetingsCard
                            } else {
                                VStack(alignment: .leading, spacing: 18) {
                                    ForEach(groupedMeetings, id: \.title) { group in
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(group.title)
                                                .font(.system(size: 11.5, weight: .medium))
                                                .foregroundStyle(AppTheme.textMuted)
                                                .padding(.leading, 4)

                                            VStack(spacing: 4) {
                                                ForEach(group.items) { meeting in
                                                    HomeMeetingRow(
                                                        meeting: meeting,
                                                        isRecording: appState.activeRecordingMeetingID == meeting.id,
                                                        searchQuery: searchText,
                                                        isSelectionMode: isBatchSelecting,
                                                        isSelected: selectedMeetingIDs.contains(meeting.id),
                                                        onSelect: {
                                                            if isBatchSelecting {
                                                                if selectedMeetingIDs.contains(meeting.id) {
                                                                    selectedMeetingIDs.remove(meeting.id)
                                                                } else {
                                                                    selectedMeetingIDs.insert(meeting.id)
                                                                }
                                                            } else {
                                                                withAnimation(.easeInOut(duration: 0.16)) {
                                                                    appState.selectedMeetingID = meeting.id
                                                                }
                                                            }
                                                        },
                                                        onTogglePin: {
                                                            withAnimation(.easeInOut(duration: 0.16)) {
                                                                appState.togglePinMeeting(id: meeting.id)
                                                            }
                                                        },
                                                        onCopy: {
                                                            appState.copyMarkdownToClipboard(for: meeting)
                                                        },
                                                        onDelete: {
                                                            appState.deleteMeeting(meeting)
                                                        }
                                                    )
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: 740, alignment: .leading)
                    .padding(.horizontal, 36)
                    .padding(.bottom, 36)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(AppTheme.brandPrimary, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                    .background(AppTheme.brandSoftFill.opacity(0.45).clipShape(RoundedRectangle(cornerRadius: 16)))
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "waveform.badge.plus")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(AppTheme.brandPrimary)
                            Text(L("松手即可离线转写该音视频并生成纪要", "Drop to transcribe offline and generate minutes"))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                        }
                    }
                    .padding(16)
            }
        }
        .onAppear {
            appState.refreshUpcomingCalendarEvents()
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDroppedMediaProviders(providers)
        }
        .background {
            Button("") {
                isHomeSearchFocused = true
            }
            .keyboardShortcut("f", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
        }
    }

    private var upcomingCalendarStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(AppTheme.brandPrimary)
                Text(L("今日待开日程", "Today's Schedule"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
                Button {
                    appState.refreshUpcomingCalendarEvents()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10.5))
                        .foregroundStyle(AppTheme.textMuted)
                }
                .buttonStyle(.plain)
                .help(L("刷新今日日程", "Refresh schedule"))
            }

            VStack(spacing: 6) {
                ForEach(appState.upcomingCalendarEvents) { event in
                    HStack(spacing: 10) {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(event.isInProgressNow ? AppTheme.successGreen : AppTheme.brandPrimary.opacity(0.65))
                                .frame(width: 6, height: 6)
                            Text(event.formattedTimeRange)
                                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        .frame(width: 98, alignment: .leading)

                        VStack(alignment: .leading, spacing: 1.5) {
                            HStack(spacing: 6) {
                                Text(event.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(AppTheme.textPrimary)
                                    .lineLimit(1)
                                if event.isInProgressNow {
                                    Text(L("进行中", "Now"))
                                        .font(.system(size: 9.5, weight: .semibold))
                                        .foregroundStyle(AppTheme.successGreen)
                                        .padding(.horizontal, 5.5)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(AppTheme.successGreen.opacity(0.14)))
                                }
                            }
                            if !event.attendees.isEmpty {
                                Text(L("参会人：\(event.attendees.prefix(4).joined(separator: "、"))", "Attendees: \(event.attendees.prefix(4).joined(separator: ", "))"))
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppTheme.textMuted)
                                    .lineLimit(1)
                            }
                        }

                        Spacer(minLength: 8)

                        Button {
                            Task { await appState.startNewMeeting(calendarEvent: event) }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "mic.fill")
                                    .font(.system(size: 10))
                                Text(L("开始记录", "Record"))
                                    .font(.system(size: 11.5, weight: .medium))
                            }
                            .foregroundStyle(AppTheme.brandPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(AppTheme.brandSoftFill))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(AppTheme.elevatedSurface.opacity(0.9)))
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(AppTheme.subtleBorder, lineWidth: 1))
                }
            }
        }
    }

    private func importProgressBanner(_ progress: AudioFileImportProgress) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(progress.message)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                Spacer()
                Text("\(Int(progress.fraction * 100))%")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(AppTheme.brandPrimary)
                Button {
                    appState.cancelMediaImport()
                } label: {
                    Text(L("取消", "Cancel"))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(AppTheme.recordingRed)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(AppTheme.recordingRed.opacity(0.10)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            ProgressView(value: progress.fraction)
                .tint(AppTheme.brandPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppTheme.brandSoftFill.opacity(0.75)))
    }

    private func pickAndImportMediaFile() {
        let panel = NSOpenPanel()
        panel.title = L("选择本地音频或视频文件（支持多选批量离线转写）", "Select Local Audio or Video Files (Batch Offline Qwen3-ASR)")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio, .mpeg4Audio, .mp3, .wav, .mpeg4Movie, .quickTimeMovie, .movie]
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            let urls = panel.urls
            Task { await appState.importMediaFiles(urls: urls) }
        }
    }

    private func handleDroppedMediaProviders(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else { return false }

        let supportedExts = Set(["m4a", "mp3", "wav", "aac", "flac", "mp4", "mov", "mkv", "webm", "ogg", "aiff"])
        let group = DispatchGroup()
        let lock = NSLock()
        var collected: [URL] = []

        for provider in fileProviders {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let direct = item as? URL {
                    url = direct
                } else {
                    url = nil
                }
                if let fileURL = url, supportedExts.contains(fileURL.pathExtension.lowercased()) {
                    lock.withLock { collected.append(fileURL) }
                }
            }
        }

        group.notify(queue: .main) {
            guard !collected.isEmpty else { return }
            Task { @MainActor in
                await appState.importMediaFiles(urls: collected)
            }
        }
        return true
    }

    private func interruptedRecoveryBanner(_ recovered: MeetingSession) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.counterclockwise.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(AppTheme.warningAmber)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("检测到上次意外中断的录音「\(recovered.title)」", "Recovered interrupted recording \"\(recovered.title)\""))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                Text(L("已保留 \(recovered.segments.count) 段逐字稿，可一键补生成完整会议纪要", "Preserved \(recovered.segments.count) transcript segments — ready to finalize minutes"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Spacer()
            Button(L("补生成纪要", "Summarize")) {
                appState.recoverInterruptedMeeting(generateSummary: true)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(AppTheme.brandPrimary))

            Button(L("查看", "Open")) {
                appState.recoverInterruptedMeeting(generateSummary: false)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(AppTheme.textPrimary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(AppTheme.elevatedSurface))
            .overlay(Capsule().strokeBorder(AppTheme.subtleBorder, lineWidth: 1))

            Button {
                appState.dismissInterruptedMeetingRecovery()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(AppTheme.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppTheme.warningAmber.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AppTheme.warningAmber.opacity(0.32), lineWidth: 1))
    }

    private func activeRecordingBanner(_ active: MeetingSession) -> some View {
        Button {
            appState.selectedMeetingID = active.id
        } label: {
            HStack(spacing: 10) {
                RecordingPulseDot(isActive: appState.isRecording, isPaused: appState.isPaused)
                Text(L("正在记录「\(active.title)」", "Recording \"\(active.title)\""))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(active.formattedDuration)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(AppTheme.brandPrimary)
                Spacer()
                Text(L("返回实时窗口", "Return to Live View"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.brandPrimary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.brandPrimary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppTheme.brandSoftFill))
        }
        .buttonStyle(.plain)
    }

    private var emptyMeetingsCard: some View {
        VStack(spacing: 10) {
            Text(searchText.isEmpty ? L("还没有会议记录", "No meetings yet") : L("没有找到匹配的会议记录", "No matching meetings found"))
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)

            if searchText.isEmpty {
                HStack(spacing: 12) {
                    Text(L("加入线上会议会自动弹窗提醒，或点击上方「开始新录音」立即记录", "Joining a call triggers an auto-prompt, or click \"Start Recording\" above"))
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.textMuted)
                }

                Button(L("查看一份示例会议纪要", "Load a Sample Meeting")) {
                    appState.createSampleMeetingForDemo()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.brandPrimary)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.elevatedSurface.opacity(0.8))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AppTheme.subtleBorder, lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private var timeGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return L("早上好，准备记录会议", "Good morning, ready to capture")
        case 12..<14: return L("中午好，准备记录会议", "Good afternoon, ready to capture")
        case 14..<18: return L("下午好，准备记录会议", "Good afternoon, ready to capture")
        default: return L("晚上好，准备记录会议", "Good evening, ready to capture")
        }
    }

    private var activeModelBadge: String {
        guard appState.authInspection.isValid else { return L("未配置 AI", "AI Not Configured") }
        switch appState.settings.authMode {
        case .localAuthFile:
            let m = appState.settings.codexModel.isEmpty ? "Codex Auth" : appState.settings.codexModel
            return "GPT · \(m)"
        case .apiKey:
            let m = appState.settings.model.isEmpty ? "API" : appState.settings.model
            let prefix = AuthManager.isLocalhostEndpoint(appState.settings.apiBaseURL) ? L("本地", "Local") : "GPT"
            return "\(prefix) · \(m)"
        case .deepSeek:
            let m = appState.settings.deepSeekModel.isEmpty ? "deepseek-chat" : appState.settings.deepSeekModel
            return "DeepSeek · \(m)"
        case .qwenDashScope:
            let m = appState.settings.qwenModel.isEmpty ? "qwen-plus" : appState.settings.qwenModel
            return "Qwen · \(m)"
        case .domesticCloud:
            let m = appState.settings.domesticModel.isEmpty ? appState.settings.domesticProvider.defaultModel : appState.settings.domesticModel
            let shortModel = m.split(separator: "/").last.map(String.init) ?? m
            return "\(appState.settings.domesticProvider.shortName) · \(shortModel)"
        case .anthropicClaude:
            let m = appState.settings.claudeModel.isEmpty ? "Claude" : appState.settings.claudeModel
            return "Claude · \(m)"
        case .googleGemini:
            let m = appState.settings.geminiModel.isEmpty ? "Gemini" : appState.settings.geminiModel
            return "Gemini · \(m)"
        case .localMLX:
            let m = appState.settings.localMLXLLMModelID.split(separator: "/").last.map(String.init) ?? "Qwen2.5"
            return "\(L("离线", "Offline")) · \(m)"
        }
    }

    private func homeTagFilterPill(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? AppTheme.brandPrimary : AppTheme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(isSelected ? AppTheme.brandSoftFill : AppTheme.elevatedSurface.opacity(0.88)))
                .overlay(Capsule().strokeBorder(isSelected ? Color.clear : AppTheme.subtleBorder, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var filteredMeetings: [MeetingSession] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return appState.meetings.filter { m in
            if let tag = selectedTagFilter, !m.tags.contains(tag) {
                return false
            }
            return q.isEmpty || m.matchesSearchQuery(q)
        }
    }

    private struct MeetingGroup {
        let title: String
        let items: [MeetingSession]
    }

    private var batchSelectionToolbar: some View {
        let allVisibleIDs = Set(filteredMeetings.map(\.id))
        let allSelected = !allVisibleIDs.isEmpty && allVisibleIDs.isSubset(of: selectedMeetingIDs)
        let selectedCount = selectedMeetingIDs.count

        return HStack(spacing: 10) {
            Button {
                if allSelected {
                    selectedMeetingIDs.subtract(allVisibleIDs)
                } else {
                    selectedMeetingIDs.formUnion(allVisibleIDs)
                }
            } label: {
                Text(allSelected ? L("取消全选", "Deselect All") : L("全选当前 (\(allVisibleIDs.count))", "Select All (\(allVisibleIDs.count))"))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(AppTheme.brandPrimary)
            }
            .buttonStyle(.plain)

            Text(L("已选 \(selectedCount) 场", "\(selectedCount) selected"))
                .font(.system(size: 11.5))
                .foregroundStyle(AppTheme.textSecondary)

            Spacer()

            Button {
                batchTagDraft = ""
                showBatchTagPopover = true
            } label: {
                Label(L("打标签", "Add Tag"), systemImage: "tag")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(selectedCount > 0 ? AppTheme.textPrimary : AppTheme.textMuted)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4.5)
                    .background(Capsule().fill(AppTheme.elevatedSurface))
                    .overlay(Capsule().strokeBorder(AppTheme.subtleBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(selectedCount == 0)
            .popover(isPresented: $showBatchTagPopover, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("为已选 \(selectedCount) 场会议添加标签", "Tag \(selectedCount) Selected Meetings"))
                        .font(.system(size: 12, weight: .semibold))
                    HStack(spacing: 6) {
                        CleanInputBox(placeholder: L("标签名称...", "Tag name..."), text: $batchTagDraft) {
                            appState.batchAddTag(batchTagDraft, to: selectedMeetingIDs)
                            showBatchTagPopover = false
                        }
                        CleanPrimaryButton(
                            title: L("应用", "Apply"),
                            disabled: batchTagDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ) {
                            appState.batchAddTag(batchTagDraft, to: selectedMeetingIDs)
                            showBatchTagPopover = false
                        }
                    }
                }
                .padding(12)
                .frame(width: 245)
                .background(AppTheme.elevatedSurface)
                .preferredColorScheme(theme.preferredColorScheme)
            }

            Button {
                appState.batchExportMarkdownToFolder(ids: selectedMeetingIDs)
            } label: {
                Label(L("导出 .md", "Export .md"), systemImage: "square.and.arrow.up")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(selectedCount > 0 ? AppTheme.textPrimary : AppTheme.textMuted)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4.5)
                    .background(Capsule().fill(AppTheme.elevatedSurface))
                    .overlay(Capsule().strokeBorder(AppTheme.subtleBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(selectedCount == 0)

            Button {
                showBatchDeleteConfirm = true
            } label: {
                Label(L("删除", "Delete"), systemImage: "trash")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(selectedCount > 0 ? AppTheme.recordingRed : AppTheme.textMuted)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4.5)
                    .background(Capsule().fill(selectedCount > 0 ? AppTheme.recordingRed.opacity(0.10) : AppTheme.elevatedSurface))
            }
            .buttonStyle(.plain)
            .disabled(selectedCount == 0)
            .alert(L("确认删除已选会议？", "Delete Selected Meetings?"), isPresented: $showBatchDeleteConfirm) {
                Button(L("取消", "Cancel"), role: .cancel) {}
                Button(L("删除 (\(selectedCount))", "Delete (\(selectedCount))"), role: .destructive) {
                    appState.batchDeleteMeetings(ids: selectedMeetingIDs)
                    selectedMeetingIDs.removeAll()
                    isBatchSelecting = false
                }
            } message: {
                Text(L("将永久删除选中的 \(selectedCount) 场会议及其本地音频文件，此操作不可撤销。", "This permanently removes \(selectedCount) meetings and their local audio files."))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(AppTheme.brandSoftFill.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(AppTheme.brandPrimary.opacity(0.22), lineWidth: 1))
    }

    private var groupedMeetings: [MeetingGroup] {
        let cal = Calendar.current
        var pinned: [MeetingSession] = []
        var today: [MeetingSession] = []
        var yesterday: [MeetingSession] = []
        var earlier: [MeetingSession] = []

        for m in filteredMeetings {
            if m.isPinned {
                pinned.append(m)
            } else if cal.isDateInToday(m.startedAt) {
                today.append(m)
            } else if cal.isDateInYesterday(m.startedAt) {
                yesterday.append(m)
            } else {
                earlier.append(m)
            }
        }

        var groups: [MeetingGroup] = []
        if !pinned.isEmpty { groups.append(MeetingGroup(title: L("置顶会议", "Pinned"), items: pinned)) }
        if !today.isEmpty { groups.append(MeetingGroup(title: L("今天", "Today"), items: today)) }
        if !yesterday.isEmpty { groups.append(MeetingGroup(title: L("昨天", "Yesterday"), items: yesterday)) }
        if !earlier.isEmpty { groups.append(MeetingGroup(title: L("更早", "Earlier"), items: earlier)) }
        return groups
    }

    private func closeCurrentWindow() {
        NSApp.keyWindow?.close()
    }
}
