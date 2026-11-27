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

    @State private var searchText: String = ""
    @State private var selectedTagFilter: String? = nil
    @State private var showPasteSheet: Bool = false
    @State private var showGlobalTodosSheet: Bool = false
    @State private var showCrossMeetingAISheet: Bool = false
    @State private var isDropTargeted: Bool = false

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
            CrossMeetingAskAISheet(appState: appState, isPresented: $showCrossMeetingAISheet)
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
                                    HStack(spacing: 6) {
                                        Image(systemName: "magnifyingglass")
                                            .font(.system(size: 11))
                                            .foregroundStyle(AppTheme.textMuted)
                                        TextField(L("搜索标题、逐字稿或待办...", "Search title, transcript, or todos..."), text: $searchText)
                                            .textFieldStyle(.plain)
                                            .font(.system(size: 12))
                                            .frame(width: 185)
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
                                    .background(Capsule().fill(AppTheme.elevatedSurface.opacity(0.92)))
                                    .overlay(Capsule().strokeBorder(AppTheme.subtleBorder, lineWidth: 1))
                                }
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
                                                        onSelect: {
                                                            withAnimation(.easeInOut(duration: 0.16)) {
                                                                appState.selectedMeetingID = meeting.id
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
                            Text("松手即可离线转写该音视频并生成纪要")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                        }
                    }
                    .padding(16)
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDroppedMediaProviders(providers)
        }
    }

    private func importProgressBanner(_ progress: AudioFileImportProgress) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(progress.message)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Text("\(Int(progress.fraction * 100))%")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(AppTheme.brandPrimary)
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
        panel.title = "选择本地音频或视频文件（离线 Qwen3-ASR 转写）"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio, .mpeg4Audio, .mp3, .wav, .mpeg4Movie, .quickTimeMovie, .movie]
        if panel.runModal() == .OK, let url = panel.url {
            Task { await appState.importMediaFile(url: url) }
        }
    }

    private func handleDroppedMediaProviders(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let direct = item as? URL {
                url = direct
            } else {
                url = nil
            }
            guard let fileURL = url else { return }
            let supportedExts = Set(["m4a", "mp3", "wav", "aac", "flac", "mp4", "mov", "mkv", "webm", "ogg", "aiff"])
            guard supportedExts.contains(fileURL.pathExtension.lowercased()) else { return }
            Task { @MainActor in
                await appState.importMediaFile(url: fileURL)
            }
        }
        return true
    }

    private func activeRecordingBanner(_ active: MeetingSession) -> some View {
        Button {
            appState.selectedMeetingID = active.id
        } label: {
            HStack(spacing: 10) {
                RecordingPulseDot(isActive: appState.isRecording, isPaused: appState.isPaused)
                Text("正在记录「\(active.title)」")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(active.formattedDuration)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(AppTheme.brandPrimary)
                Spacer()
                Text("返回实时窗口")
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
            Text(searchText.isEmpty ? "还没有会议记录" : "没有找到匹配的会议记录")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)

            if searchText.isEmpty {
                HStack(spacing: 12) {
                    Text("加入线上会议会自动弹窗提醒，或点击上方「开始新录音」立即记录")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.textMuted)
                }

                Button("查看一份示例会议纪要") {
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
        guard appState.authInspection.isValid else { return "未配置 AI" }
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
            return "离线 · \(m)"
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

    private var groupedMeetings: [MeetingGroup] {
        let cal = Calendar.current
        var today: [MeetingSession] = []
        var yesterday: [MeetingSession] = []
        var earlier: [MeetingSession] = []

        for m in filteredMeetings {
            if cal.isDateInToday(m.startedAt) {
                today.append(m)
            } else if cal.isDateInYesterday(m.startedAt) {
                yesterday.append(m)
            } else {
                earlier.append(m)
            }
        }

        var groups: [MeetingGroup] = []
        if !today.isEmpty { groups.append(MeetingGroup(title: L("今天", "Today"), items: today)) }
        if !yesterday.isEmpty { groups.append(MeetingGroup(title: L("昨天", "Yesterday"), items: yesterday)) }
        if !earlier.isEmpty { groups.append(MeetingGroup(title: L("更早", "Earlier"), items: earlier)) }
        return groups
    }

    private func closeCurrentWindow() {
        NSApp.keyWindow?.close()
    }
}

// MARK: - Clean Action Card Component

private struct HomeActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let isPrimary: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isPrimary ? AppTheme.brandPrimary : AppTheme.neutralPill)
                            .frame(width: 36, height: 36)
                        Image(systemName: icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(isPrimary ? Color.white : AppTheme.textPrimary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isPrimary ? AppTheme.brandPrimary.opacity(isHovering ? 1 : 0.6) : AppTheme.textMuted)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isPrimary ? AppTheme.mindMapNodeFill : AppTheme.elevatedSurface.opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isHovering
                            ? (isPrimary ? AppTheme.brandPrimary.opacity(0.35) : AppTheme.textMuted.opacity(0.45))
                            : (isPrimary ? AppTheme.mindMapLine : AppTheme.subtleBorder),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(isHovering ? 0.05 : 0.015), radius: isHovering ? 10 : 4, y: 2)
            .animation(.easeOut(duration: 0.15), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Clean Editorial Meeting Row

private struct HomeMeetingRow: View {
    let meeting: MeetingSession
    let isRecording: Bool
    let searchQuery: String
    let onSelect: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isRecording ? AppTheme.brandSoftFill : AppTheme.softCardBg)
                        .frame(width: 34, height: 34)
                    Image(systemName: isRecording ? "waveform" : "doc.text")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isRecording ? AppTheme.brandPrimary : AppTheme.textSecondary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(meeting.title)
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(1)

                        if isRecording {
                            Text("录音中")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(AppTheme.brandPrimary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(Capsule().fill(AppTheme.brandSoftFill))
                        }

                        ForEach(meeting.tags.prefix(3), id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.system(size: 10))
                                .foregroundStyle(AppTheme.textSecondary)
                                .padding(.horizontal, 5.5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(AppTheme.neutralPill))
                        }
                    }

                    Text(previewText)
                        .font(.system(size: 12))
                        .foregroundStyle(isShowingSearchSnippet ? AppTheme.brandPrimary.opacity(0.9) : AppTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                if isHovering {
                    HStack(spacing: 6) {
                        Button(action: onCopy) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.textSecondary)
                                .frame(width: 26, height: 26)
                                .background(Circle().fill(AppTheme.neutralPill))
                        }
                        .buttonStyle(.plain)
                        .help("复制 Markdown 纪要")

                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.textSecondary)
                                .frame(width: 26, height: 26)
                                .background(Circle().fill(AppTheme.neutralPill))
                        }
                        .buttonStyle(.plain)
                        .help("删除记录")
                    }
                } else {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(shortTime(meeting.startedAt))
                            .font(.system(size: 11.5))
                            .foregroundStyle(AppTheme.textSecondary)
                        HStack(spacing: 5) {
                            Text(meeting.duration > 0 ? meeting.chineseDurationText : meeting.sourceAppName)
                            if !meeting.tokenUsage.isEmpty {
                                Text("· \(meeting.tokenUsage.formattedCompact)t")
                            }
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.textMuted)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isHovering ? AppTheme.elevatedSurface : AppTheme.elevatedSurface.opacity(0.62))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isHovering ? AppTheme.subtleBorder : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("复制 Markdown 纪要", action: onCopy)
            Divider()
            Button("删除记录", role: .destructive, action: onDelete)
        }
    }

    private var matchedSnippet: String? {
        meeting.searchSnippet(for: searchQuery)
    }

    private var isShowingSearchSnippet: Bool {
        matchedSnippet != nil
    }

    private var previewText: String {
        if let snippet = matchedSnippet {
            return snippet
        }
        if !meeting.minutes.overview.isEmpty {
            return meeting.minutes.overview
        }
        if let firstSeg = meeting.segments.first {
            return firstSeg.text
        }
        return "未识别到文字内容"
    }

    private func shortTime(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "MM-dd HH:mm"
        return df.string(from: date)
    }
}

// MARK: - Paste Transcript -> Smart Minutes Sheet

private struct PasteTranscriptSheet: View {
    @ObservedObject var appState: AppState
    @Binding var isPresented: Bool

    @State private var title: String = ""
    @State private var rawText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("粘贴文本生成智能纪要")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }

            TextField("会议主题（留空由 GPT 自动命名）", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 9).fill(AppTheme.softCardBg))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(AppTheme.subtleBorder))

            TextEditor(text: $rawText)
                .font(.system(size: 13))
                .padding(8)
                .frame(minHeight: 210)
                .background(RoundedRectangle(cornerRadius: 10).fill(AppTheme.softCardBg))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(AppTheme.subtleBorder))

            HStack {
                Text("支持直接粘贴逐字稿、聊天讨论或零散笔记")
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
                Button("取消") { isPresented = false }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5))
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal, 10)

                Button {
                    let t = title
                    let body = rawText
                    isPresented = false
                    Task { await appState.createMeetingFromPastedText(title: t, rawText: body) }
                } label: {
                    Text("生成智能纪要")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(AppTheme.brandPrimary))
                }
                .buttonStyle(.plain)
                .disabled(rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 500)
        .background(AppTheme.canvasWhite)
        .tint(AppTheme.brandPrimary)
        .preferredColorScheme(ThemeManager.shared.preferredColorScheme)
    }
}
