import SwiftUI
import AppKit
import SonoteCore

/// Switches cleanly between:
/// 1. In-Meeting Live View (2-column live transcript + real-time mind-map/outline summary)
/// 2. Post-Meeting Minimal Document View (adaptive Light/Dark document canvas)
struct MeetingWorkspaceView: View {
    let meeting: MeetingSession
    @ObservedObject var appState: AppState
    let onBackHome: () -> Void
    let onCloseWindow: () -> Void

    private var isLiveRecording: Bool {
        appState.activeRecordingMeetingID == meeting.id
    }

    var body: some View {
        if isLiveRecording {
            liveRecordingLayout
        } else {
            completedDocumentLayout
        }
    }

    private var liveRecordingLayout: some View {
        HStack(spacing: 0) {
            TranscriptPaneView(meeting: meeting, appState: appState)
                .frame(minWidth: 340, idealWidth: 390, maxWidth: 440)

            Rectangle()
                .fill(AppTheme.divider)
                .frame(width: 1)

            SmartMinutesPaneView(meeting: meeting, appState: appState)
                .frame(maxWidth: .infinity)
        }
        .background(AppTheme.canvasWhite)
    }

    private var completedDocumentLayout: some View {
        CompletedMeetingDocumentView(
            meeting: meeting,
            appState: appState,
            onBackHome: onBackHome,
            onCloseWindow: onCloseWindow
        )
    }
}

struct CompletedMeetingDocumentView: View {
    let meeting: MeetingSession
    @ObservedObject var appState: AppState
    @ObservedObject var theme = ThemeManager.shared
    let onBackHome: () -> Void
    let onCloseWindow: () -> Void

    enum DocTab: String, CaseIterable, Identifiable {
        case summary = "总结"
        case mindMap = "导图"
        case transcript = "逐字稿"
        case askAI = "问 AI"
        var id: String { rawValue }

        @MainActor
        var localizedTitle: String {
            switch self {
            case .summary: return L("总结", "Summary")
            case .mindMap: return L("导图", "Mind Map")
            case .transcript: return L("逐字稿", "Transcript")
            case .askAI: return L("问 AI", "Ask AI")
            }
        }
    }

    @StateObject var audioPlayer = MeetingAudioPlayer()
    @State var activeTab: DocTab = .summary
    @State var chatDraft: String = ""
    @State var copiedToast: String? = nil
    @State var showTokenPopover: Bool = false
    @State var isEditingSummary: Bool = false
    @State var selectedSpeakerFilter: String? = nil
    @State var starredOnlyFilter: Bool = false
    @State var transcriptSearchQuery: String = ""
    @State var autoFollowTranscript: Bool = true
    @State var renamingSegmentID: UUID? = nil
    @State var editingSegmentID: UUID? = nil
    @State var editingSegmentDraft: String = ""
    @State var showAddTagPopover: Bool = false
    @State var newTagDraft: String = ""
    @State var showStreamingPreview: Bool = true
    @FocusState var isComposerFocused: Bool

    var hasNoRecognizedContent: Bool {
        meeting.segments.isEmpty
            && meeting.minutes.isEmpty
            && meeting.manualNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasAudioFile: Bool {
        guard let path = meeting.audioFilePath else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    var activePlayingSegmentID: UUID? {
        guard audioPlayer.isPlaying || audioPlayer.currentTime > 0 else { return nil }
        let t = audioPlayer.currentTime
        return meeting.segments.last(where: { $0.timestamp <= t + 0.4 })?.id
    }

    var body: some View {
        ZStack {
            DoubaoSoftLightBackdrop()

            VStack(alignment: .leading, spacing: 0) {
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            Spacer().frame(height: 54)

                            // Editable Bold Title
                            TextField(L("新录音", "New Recording"), text: Binding(
                                get: { meeting.title },
                                set: { newTitle in
                                    appState.updateMeeting(id: meeting.id) { $0.title = newTitle }
                                }
                            ))
                            .textFieldStyle(.plain)
                            .font(.system(size: 25, weight: .bold))
                            .foregroundStyle(AppTheme.textPrimary)

                            // Duration, Token Usage & Tags Subtitle
                            metadataHeaderRow
                                .padding(.top, 6)

                            // Document Content
                            if meeting.status == .summarizing || appState.isGeneratingMinutes {
                                summarizingProgressCard
                                    .padding(.top, 28)
                            } else if hasNoRecognizedContent {
                                Text(L("未识别到文字内容", "No transcript content recognized"))
                                    .font(.system(size: 14.5))
                                    .foregroundStyle(AppTheme.textPrimary.opacity(0.85))
                                    .padding(.top, 36)
                            } else {
                                tabStripHeader
                                    .padding(.top, 20)

                                Divider()
                                    .overlay(AppTheme.divider)
                                    .padding(.bottom, 22)

                                switch activeTab {
                                case .summary:
                                    VStack(alignment: .leading, spacing: 22) {
                                        if meeting.minutes.isEmpty {
                                            Text(L("暂无结构化总结，点击右上角「重新生成」即可由 AI 生成会议纪要。", "No summary yet. Click \"Regenerate\" in the top right to create AI minutes."))
                                                .font(.system(size: 14))
                                                .foregroundStyle(AppTheme.textSecondary)
                                        } else {
                                            DoubaoOutlineMinutesView(
                                                meeting: meeting,
                                                appState: appState,
                                                isEditing: isEditingSummary
                                            )
                                        }

                                        if !meeting.manualNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isEditingSummary {
                                            manualNotesCard
                                        }
                                    }

                                case .mindMap:
                                    if meeting.minutes.isEmpty {
                                        Text(L("暂无导图内容", "No mind-map yet"))
                                            .font(.system(size: 14))
                                            .foregroundStyle(AppTheme.textSecondary)
                                    } else {
                                        DoubaoMindMapView(meeting: meeting, appState: appState)
                                    }

                                case .transcript:
                                    syncedTranscriptView

                                case .askAI:
                                    minimalAskAIView
                                }

                                Color.clear.frame(height: 1).id("doc-bottom")
                            }
                        }
                        .padding(.horizontal, 44)
                        .padding(.bottom, activeTab == .askAI ? 16 : 24)
                    }
                    .onChange(of: meeting.chatHistory.count) { _, _ in
                        if activeTab == .askAI {
                            withAnimation(.easeOut(duration: 0.2)) {
                                scrollProxy.scrollTo("doc-bottom", anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: meeting.chatHistory.last?.content.count ?? 0) { _, _ in
                        if activeTab == .askAI && appState.isAskingAI {
                            scrollProxy.scrollTo("doc-bottom", anchor: .bottom)
                        }
                    }
                    .onChange(of: activePlayingSegmentID) { _, newSegID in
                        if activeTab == .transcript && autoFollowTranscript && audioPlayer.isPlaying, let segID = newSegID {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                scrollProxy.scrollTo(segID, anchor: .center)
                            }
                        }
                    }
                }

                // Synced Audio Playback Bar (when meeting has recorded/imported audio)
                if hasAudioFile && activeTab != .askAI {
                    AudioPlaybackStrip(player: audioPlayer, autoFollowTranscript: $autoFollowTranscript)
                        .padding(.horizontal, 40)
                        .padding(.top, 4)
                        .padding(.bottom, 2)
                }

                // Pinned AI Composer when on the "问 AI" tab
                if activeTab == .askAI && !hasNoRecognizedContent {
                    DoubaoAIComposerView(
                        text: $chatDraft,
                        isFocused: $isComposerFocused,
                        isSending: appState.isAskingAI,
                        onQuickPrompt: { prompt in
                            Task { await appState.askAI(meetingID: meeting.id, question: prompt) }
                        },
                        onSend: { sendChat() },
                        onStop: { appState.cancelAskAI() }
                    )
                    .padding(.horizontal, 40)
                    .padding(.top, 6)
                    .padding(.bottom, 4)
                }

                // Bottom Action Bar
                bottomActionBar
                    .padding(.horizontal, 40)
                    .padding(.vertical, 16)
            }

            // Hidden Spacebar shortcut for audio play/pause when not typing in a text field
            if hasAudioFile && activeTab != .askAI && !isEditingSummary && editingSegmentID == nil && !showAddTagPopover {
                Button("") {
                    audioPlayer.togglePlayPause()
                }
                .keyboardShortcut(.space, modifiers: [])
                .opacity(0)
                .frame(width: 0, height: 0)
            }
        }
        .onAppear {
            audioPlayer.loadIfNeeded(path: meeting.audioFilePath)
        }
        .onChange(of: meeting.id) { _, _ in
            isEditingSummary = false
            selectedSpeakerFilter = nil
            starredOnlyFilter = false
            transcriptSearchQuery = ""
            renamingSegmentID = nil
            editingSegmentID = nil
            audioPlayer.loadIfNeeded(path: meeting.audioFilePath)
        }
        .onDisappear {
            audioPlayer.stop()
        }
    }

    // MARK: - Header Metadata & Tags Row

    private var metadataHeaderRow: some View {
        HStack(spacing: 8) {
            Text(theme.isEnglish ? meeting.formattedDuration : meeting.chineseDurationText)
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.textSecondary)

            if !meeting.tokenUsage.isEmpty {
                Text("·")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.textMuted)

                Button {
                    showTokenPopover.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 10))
                        Text("\(meeting.tokenUsage.formattedCompact) tokens")
                            .font(.system(size: 12.5))
                    }
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(AppTheme.softCardBg))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(meeting.tokenUsage.detailedSummary)
                .popover(isPresented: $showTokenPopover, arrowEdge: .bottom) {
                    TokenUsagePopoverView(title: L("本场会议 Token 消耗", "Meeting Token Usage"), usage: meeting.tokenUsage)
                }
            }

            // Meeting Tags Strip
            ForEach(meeting.tags, id: \.self) { tag in
                HStack(spacing: 3) {
                    Text("#\(tag)")
                        .font(.system(size: 11))
                    Button {
                        appState.removeTag(tag, from: meeting.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(AppTheme.brandPrimary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(AppTheme.brandSoftFill))
            }

            Button {
                newTagDraft = ""
                showAddTagPopover.toggle()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "tag")
                        .font(.system(size: 9.5))
                    Text(meeting.tags.isEmpty ? L("添加标签", "Add Tag") : "+")
                        .font(.system(size: 11))
                }
                .foregroundStyle(AppTheme.textMuted)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(AppTheme.softCardBg))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showAddTagPopover, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("添加会议标签", "Add Meeting Tag"))
                        .font(.system(size: 12.5, weight: .semibold))
                    HStack(spacing: 6) {
                        TextField(L("例如：产品周会、技术评审", "e.g. Weekly Sync, Design"), text: $newTagDraft)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                            .onSubmit {
                                appState.addTag(newTagDraft, to: meeting.id)
                                showAddTagPopover = false
                            }
                        Button(L("添加", "Add")) {
                            appState.addTag(newTagDraft, to: meeting.id)
                            showAddTagPopover = false
                        }
                        .controlSize(.small)
                        .disabled(newTagDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    let existing = appState.allMeetingTags.filter { !meeting.tags.contains($0) }
                    if !existing.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 5) {
                                ForEach(existing.prefix(8), id: \.self) { t in
                                    Button("#\(t)") {
                                        appState.addTag(t, to: meeting.id)
                                        showAddTagPopover = false
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                }
                            }
                        }
                    }
                }
                .padding(12)
                .frame(width: 245)
                .background(AppTheme.elevatedSurface)
                .preferredColorScheme(theme.preferredColorScheme)
            }
        }
    }

    // MARK: - Tab Strip & Template Switcher

    private var tabStripHeader: some View {
        HStack(spacing: 8) {
            ForEach(DocTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.14)) {
                        activeTab = tab
                        if tab != .summary { isEditingSummary = false }
                    }
                } label: {
                    VStack(spacing: 7) {
                        Text(tab.localizedTitle)
                            .font(.system(size: 13.5, weight: activeTab == tab ? .semibold : .regular))
                            .foregroundStyle(activeTab == tab ? AppTheme.textPrimary : AppTheme.textSecondary)
                            .padding(.top, 6)
                        Rectangle()
                            .fill(activeTab == tab ? AppTheme.brandPrimary : Color.clear)
                            .frame(height: 2)
                            .cornerRadius(1)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if activeTab == .summary || activeTab == .mindMap {
                Menu {
                    ForEach(MinutesTemplate.allCases) { tpl in
                        Button {
                            appState.setTemplate(tpl, for: meeting.id, regenerate: true)
                        } label: {
                            if meeting.customTemplateID == nil && meeting.template == tpl {
                                Label(tpl.displayName, systemImage: "checkmark")
                            } else {
                                Text(tpl.displayName)
                            }
                        }
                    }
                    if !appState.settings.customTemplates.isEmpty {
                        Divider()
                        ForEach(appState.settings.customTemplates) { custom in
                            Button {
                                appState.setCustomTemplate(custom, for: meeting.id, regenerate: true)
                            } label: {
                                if meeting.customTemplateID == custom.id {
                                    Label(custom.name, systemImage: "checkmark")
                                } else {
                                    Text(custom.name)
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(GPTClient.resolveTemplate(for: meeting, settings: appState.settings).name)
                            .font(.system(size: 11.5))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9))
                    }
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(AppTheme.softCardBg))
                    .contentShape(Capsule())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(L("切换场景纪要模板并重新生成", "Switch template and regenerate"))

                if activeTab == .summary && !meeting.minutes.isEmpty {
                    Button {
                        isEditingSummary.toggle()
                    } label: {
                        Text(isEditingSummary ? L("完成", "Done") : L("编辑", "Edit"))
                            .font(.system(size: 12, weight: isEditingSummary ? .medium : .regular))
                            .foregroundStyle(isEditingSummary ? AppTheme.brandPrimary : AppTheme.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    Task { await appState.refreshMinutesNow(for: meeting.id, isFinal: true) }
                } label: {
                    Text(L("重新生成", "Regenerate"))
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Bottom Bar & Export Menu

    private var bottomActionBar: some View {
        HStack(spacing: 10) {
            Button(action: onCloseWindow) {
                HStack(spacing: 6) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                    Text(L("关闭窗口", "Close"))
                        .font(.system(size: 12.5, weight: .regular))
                }
                .foregroundStyle(AppTheme.textPrimary.opacity(0.85))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppTheme.elevatedSurface.opacity(0.92))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(AppTheme.subtleBorder, lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            if !hasNoRecognizedContent {
                Menu {
                    Button(L("复制富文本（直接粘贴飞书 / 邮件）", "Copy Rich Text (Feishu / Mail)")) {
                        appState.copyRichTextToClipboard(for: meeting)
                        showToast(L("已复制富文本", "Copied Rich Text"))
                    }
                    Button(L("复制完整 Markdown 纪要", "Copy Full Markdown")) {
                        appState.copyMarkdownToClipboard(for: meeting)
                        showToast(L("已复制 Markdown", "Copied Markdown"))
                    }
                    if !meeting.minutes.isEmpty {
                        Button(L("复制 Mermaid 思维导图代码", "Copy Mermaid Mind-Map")) {
                            appState.copyMermaidMindMapToClipboard(for: meeting)
                            showToast(L("已复制导图代码", "Copied Mermaid"))
                        }
                    }
                    Divider()
                    Button(L("推送到 \(appState.settings.webhookProvider.displayName)", "Push to \(appState.settings.webhookProvider.displayName)")) {
                        Task {
                            let res = await appState.pushMeetingToWebhook(meeting)
                            showToast(res.success ? L("已推送 Webhook", "Pushed Webhook") : L("推送失败", "Push Failed"))
                        }
                    }
                    .disabled(appState.settings.webhookURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || appState.isPushingWebhook)

                    if !appState.settings.obsidianVaultPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button(L("同步到 Obsidian / 本地 Markdown 目录", "Sync to Obsidian / Markdown Folder")) {
                            let res = appState.syncMeetingToMarkdownFolder(meeting)
                            showToast(res.isSuccess ? L("已同步 .md 笔记", "Synced .md Note") : L("同步失败", "Sync Failed"))
                        }
                    }
                    Divider()
                    Button(L("导出为 .pdf 文件...", "Export as .pdf...")) {
                        appState.exportPDFWithSavePanel(for: meeting)
                    }
                    Button(L("导出为 .md 文件...", "Export as .md...")) {
                        appState.exportMarkdownWithSavePanel(for: meeting)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(copiedToast ?? L("导出 / 复制", "Export"))
                            .font(.system(size: 12))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9))
                    }
                    .foregroundStyle(copiedToast != nil ? AppTheme.brandPrimary : AppTheme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            Button(action: onBackHome) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10.5, weight: .semibold))
                    Text(L("返回主页", "Home"))
                }
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                Task { await appState.startNewMeeting() }
            } label: {
                Text(L("开始新录音", "New Recording"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.brandPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(AppTheme.brandSoftFill))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Live AI Streaming Progress Card

    private var summarizingProgressCard: some View {
        let raw = appState.aiStreamingPreview
        let isReasoning = raw.contains("<think>") && !raw.contains("</think>")
        let charCount = raw.count
        let tailPreview: String = {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count <= 320 { return trimmed }
            return "…" + String(trimmed.suffix(320))
        }()

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(
                    isReasoning
                        ? L("深度推理思考中...", "Reasoning through meeting context...")
                        : L("正在整理结构化会议纪要...", "Generating structured meeting minutes...")
                )
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.textPrimary)

                if charCount > 0 {
                    Text(L("已生成 \(charCount) 字", "\(charCount) chars"))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppTheme.brandPrimary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(AppTheme.brandSoftFill))
                }

                Spacer()

                if charCount > 0 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.14)) {
                            showStreamingPreview.toggle()
                        }
                    } label: {
                        Text(showStreamingPreview ? L("隐藏流式预览", "Hide Stream") : L("查看流式预览", "Show Stream"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if charCount > 0 && showStreamingPreview {
                Text(tailPreview)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineSpacing(3.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(AppTheme.softCardBg))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(AppTheme.subtleBorder, lineWidth: 1))
            } else {
                SkeletonPill(width: 280, height: 12)
                SkeletonPill(width: 420, height: 12)
                SkeletonPill(width: 220, height: 12)
            }
        }
    }

    // MARK: - Post-Meeting Manual Notes Section

    private var manualNotesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "note.text")
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppTheme.brandPrimary)
                Text(L("会中随手记", "Quick Notes"))
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                if isEditingSummary {
                    Text(L("修改后可点击右上角「重新生成」融入纪要", "Click \"Regenerate\" after editing to fold notes into minutes"))
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.textMuted)
                }
            }

            if isEditingSummary {
                TextEditor(text: Binding(
                    get: { meeting.manualNotes },
                    set: { newVal in
                        appState.updateMeeting(id: meeting.id) { $0.manualNotes = newVal }
                    }
                ))
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 72)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppTheme.elevatedSurface))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(AppTheme.subtleBorder, lineWidth: 1))
            } else {
                Text(meeting.manualNotes)
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(AppTheme.softCardBg))
            }
        }
    }

    func sendChat() {
        let q = chatDraft
        chatDraft = ""
        Task { await appState.askAI(meetingID: meeting.id, question: q) }
    }

    func showToast(_ text: String) {
        copiedToast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            if copiedToast == text { copiedToast = nil }
        }
    }
}
