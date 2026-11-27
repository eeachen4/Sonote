import SwiftUI
import AppKit
import SonoteCore

/// Switches cleanly between:
/// 1. In-Meeting Live View (exact 2-column Doubao Work layout from Screenshot 1)
/// 2. Post-Meeting Minimal Document View (exact white light-wash layout from Screenshot 2)
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
    let onBackHome: () -> Void
    let onCloseWindow: () -> Void

    enum DocTab: String, CaseIterable, Identifiable {
        case summary = "总结"
        case mindMap = "导图"
        case transcript = "逐字稿"
        case askAI = "问 AI"
        var id: String { rawValue }
    }

    @StateObject private var audioPlayer = MeetingAudioPlayer()
    @State private var activeTab: DocTab = .summary
    @State private var chatDraft: String = ""
    @State private var copiedToast: String? = nil
    @State private var showTokenPopover: Bool = false
    @State private var isEditingSummary: Bool = false
    @State private var selectedSpeakerFilter: String? = nil
    @State private var starredOnlyFilter: Bool = false
    @State private var renamingSegmentID: UUID? = nil
    @State private var editingSegmentID: UUID? = nil
    @State private var editingSegmentDraft: String = ""
    @State private var showAddTagPopover: Bool = false
    @State private var newTagDraft: String = ""
    @FocusState private var isComposerFocused: Bool

    private var hasNoRecognizedContent: Bool {
        meeting.segments.isEmpty
            && meeting.minutes.isEmpty
            && meeting.manualNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasAudioFile: Bool {
        guard let path = meeting.audioFilePath else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    private var activePlayingSegmentID: UUID? {
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

                            // Editable Bold Title ("新录音" / AI Title)
                            TextField("新录音", text: Binding(
                                get: { meeting.title },
                                set: { newTitle in
                                    appState.updateMeeting(id: meeting.id) { $0.title = newTitle }
                                }
                            ))
                            .textFieldStyle(.plain)
                            .font(.system(size: 25, weight: .bold))
                            .foregroundStyle(AppTheme.textPrimary)

                            // Subtle Duration & Token Usage Subtitle ("3分27秒 · 4.2k tokens")
                            HStack(spacing: 8) {
                                Text(meeting.chineseDurationText)
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
                                        TokenUsagePopoverView(title: "本场会议 Token 消耗", usage: meeting.tokenUsage)
                                    }
                                }

                                // Subtle Meeting Tags Strip
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
                                        Text(meeting.tags.isEmpty ? "添加标签" : "+")
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
                                        Text("添加会议标签")
                                            .font(.system(size: 12.5, weight: .semibold))
                                        HStack(spacing: 6) {
                                            TextField("例如：产品周会、技术评审", text: $newTagDraft)
                                                .textFieldStyle(.roundedBorder)
                                                .font(.system(size: 12))
                                                .onSubmit {
                                                    appState.addTag(newTagDraft, to: meeting.id)
                                                    showAddTagPopover = false
                                                }
                                            Button("添加") {
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
                                    .frame(width: 240)
                                    .preferredColorScheme(.light)
                                }
                            }
                            .padding(.top, 6)

                            // Document Content
                            if meeting.status == .summarizing || appState.isGeneratingMinutes {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack(spacing: 8) {
                                        ProgressView().controlSize(.small)
                                        Text("正在整理会议纪要...")
                                            .font(.system(size: 14))
                                            .foregroundStyle(AppTheme.textSecondary)
                                    }
                                    SkeletonPill(width: 280, height: 12)
                                    SkeletonPill(width: 420, height: 12)
                                    SkeletonPill(width: 220, height: 12)
                                }
                                .padding(.top, 32)
                            } else if hasNoRecognizedContent {
                                Text("未识别到文字内容")
                                    .font(.system(size: 14.5))
                                    .foregroundStyle(AppTheme.textPrimary.opacity(0.85))
                                    .padding(.top, 36)
                            } else {
                                // Minimalist ghost tab strip (full hit-testable tab area)
                                HStack(spacing: 8) {
                                    ForEach(DocTab.allCases) { tab in
                                        Button {
                                            withAnimation(.easeInOut(duration: 0.14)) {
                                                activeTab = tab
                                                if tab != .summary { isEditingSummary = false }
                                            }
                                        } label: {
                                            VStack(spacing: 7) {
                                                Text(tab.rawValue)
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
                                        .help("切换场景纪要模板并重新生成")

                                        if activeTab == .summary && !meeting.minutes.isEmpty {
                                            Button {
                                                isEditingSummary.toggle()
                                            } label: {
                                                Text(isEditingSummary ? "完成" : "编辑")
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
                                            Text("重新生成")
                                                .font(.system(size: 12))
                                                .foregroundStyle(AppTheme.textSecondary)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 6)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.top, 20)

                                Divider()
                                    .overlay(AppTheme.divider)
                                    .padding(.bottom, 22)

                                switch activeTab {
                                case .summary:
                                    VStack(alignment: .leading, spacing: 22) {
                                        if meeting.minutes.isEmpty {
                                            Text("暂无结构化总结，点击右上角「重新生成」即可由 GPT 生成会议纪要。")
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
                                        Text("暂无导图内容")
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
                }

                // Minimal Synced Audio Playback Bar (when meeting has recorded/imported audio)
                if hasAudioFile && activeTab != .askAI {
                    AudioPlaybackStrip(player: audioPlayer)
                        .padding(.horizontal, 40)
                        .padding(.top, 4)
                        .padding(.bottom, 2)
                }

                // Pinned Doubao-style AI Composer when on the "问 AI" tab
                if activeTab == .askAI && !hasNoRecognizedContent {
                    DoubaoAIComposerView(
                        text: $chatDraft,
                        isFocused: $isComposerFocused,
                        isSending: appState.isAskingAI,
                        onQuickPrompt: { label in
                            let prompt = "请基于本次会议记录，\(label)。"
                            Task { await appState.askAI(meetingID: meeting.id, question: prompt) }
                        },
                        onSend: { sendChat() },
                        onStop: { appState.cancelAskAI() }
                    )
                    .padding(.horizontal, 40)
                    .padding(.top, 6)
                    .padding(.bottom, 4)
                }

                // Bottom Bar
                HStack(spacing: 10) {
                    Button(action: onCloseWindow) {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .medium))
                            Text("关闭窗口")
                                .font(.system(size: 12.5, weight: .regular))
                        }
                        .foregroundStyle(AppTheme.textPrimary.opacity(0.85))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.9))
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
                            Button("复制富文本（直接粘贴飞书 / 邮件）") {
                                appState.copyRichTextToClipboard(for: meeting)
                                showToast("已复制富文本")
                            }
                            Button("复制完整 Markdown 纪要") {
                                appState.copyMarkdownToClipboard(for: meeting)
                                showToast("已复制 Markdown")
                            }
                            if !meeting.minutes.isEmpty {
                                Button("复制 Mermaid 思维导图代码") {
                                    appState.copyMermaidMindMapToClipboard(for: meeting)
                                    showToast("已复制导图代码")
                                }
                            }
                            Divider()
                            Button("推送到 \(appState.settings.webhookProvider.displayName)") {
                                Task {
                                    let res = await appState.pushMeetingToWebhook(meeting)
                                    showToast(res.success ? "已推送 Webhook" : "推送失败")
                                }
                            }
                            .disabled(appState.settings.webhookURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || appState.isPushingWebhook)
                            Divider()
                            Button("导出为 .pdf 文件...") {
                                appState.exportPDFWithSavePanel(for: meeting)
                            }
                            Button("导出为 .md 文件...") {
                                appState.exportMarkdownWithSavePanel(for: meeting)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(copiedToast ?? "导出 / 复制")
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
                            Text("返回主页")
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
                        Text("开始新录音")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.brandPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(AppTheme.brandSoftFill))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 16)
            }
        }
        .onAppear {
            audioPlayer.loadIfNeeded(path: meeting.audioFilePath)
        }
        .onChange(of: meeting.id) { _, _ in
            isEditingSummary = false
            selectedSpeakerFilter = nil
            starredOnlyFilter = false
            renamingSegmentID = nil
            editingSegmentID = nil
            audioPlayer.loadIfNeeded(path: meeting.audioFilePath)
        }
        .onDisappear {
            audioPlayer.stop()
        }
    }

    // MARK: - Post-Meeting Manual Notes Section

    private var manualNotesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "note.text")
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppTheme.brandPrimary)
                Text("会中随手记")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                if isEditingSummary {
                    Text("修改后可点击右上角「重新生成」融入纪要")
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
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white))
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

    // MARK: - Audio-Synced Click-to-Seek, Speaker Rename & Filter Transcript View

    private var hasGenericSpeakers: Bool {
        meeting.distinctSpeakerNames.contains { $0 == "发言人" || $0.hasPrefix("发言人 ") }
    }

    private var filteredTranscriptSegments: [TranscriptSegment] {
        meeting.segments.filter { seg in
            if starredOnlyFilter && !seg.isStarred { return false }
            if let spk = selectedSpeakerFilter, seg.resolvedSpeakerName != spk { return false }
            return true
        }
    }

    private var syncedTranscriptView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top Controls: Speaker Filter Pills + Diarization & AI Name Inference
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(hasAudioFile ? "点击段落跳转回听 · 点击说话人改名或记住声纹" : "点击说话人标签可改名 · 双击文字可修正错字")
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppTheme.textMuted)
                    Spacer()

                    if hasGenericSpeakers {
                        Button {
                            Task { await appState.inferSpeakerNamesWithAI(for: meeting.id) }
                        } label: {
                            HStack(spacing: 4) {
                                if appState.isInferringSpeakers {
                                    ProgressView().controlSize(.mini)
                                } else {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 10.5))
                                }
                                Text(appState.isInferringSpeakers ? "推断中..." : "AI 猜姓名")
                                    .font(.system(size: 11.5, weight: .medium))
                            }
                            .foregroundStyle(AppTheme.textSecondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(AppTheme.softCardBg))
                            .overlay(Capsule().strokeBorder(AppTheme.subtleBorder, lineWidth: 1))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(appState.isInferringSpeakers || appState.isDiarizing)
                        .help("根据对话上下文和日程参会人自动推断「发言人 1 / 2」的真实姓名")
                    }

                    if hasAudioFile {
                        Button {
                            Task { await appState.runSpeakerDiarization(for: meeting.id) }
                        } label: {
                            HStack(spacing: 5) {
                                if appState.isDiarizing {
                                    ProgressView().controlSize(.mini)
                                } else {
                                    Image(systemName: "person.2.wave.2")
                                        .font(.system(size: 11))
                                }
                                Text(appState.isDiarizing ? "正在识别声纹..." : "声纹认人")
                                    .font(.system(size: 11.5, weight: .medium))
                            }
                            .foregroundStyle(AppTheme.brandPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(AppTheme.brandSoftFill))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(appState.isDiarizing)
                        .help("通过 Sortformer 分离多说话人，并自动匹配本地 ECAPA 声纹库")
                    }
                }

                // Speaker & Star Filter Bar
                let speakers = meeting.distinctSpeakerNames
                let hasStarred = meeting.segments.contains(where: \.isStarred)
                if speakers.count > 1 || hasStarred {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            transcriptFilterPill(
                                title: "全部 (\(meeting.segments.count))",
                                isSelected: selectedSpeakerFilter == nil && !starredOnlyFilter
                            ) {
                                selectedSpeakerFilter = nil
                                starredOnlyFilter = false
                            }

                            ForEach(speakers, id: \.self) { name in
                                let count = meeting.segments.filter { $0.resolvedSpeakerName == name }.count
                                transcriptFilterPill(
                                    title: "\(name) (\(count))",
                                    isSelected: selectedSpeakerFilter == name
                                ) {
                                    selectedSpeakerFilter = (selectedSpeakerFilter == name) ? nil : name
                                }
                            }

                            if hasStarred {
                                transcriptFilterPill(
                                    title: "⭐ 重点",
                                    isSelected: starredOnlyFilter
                                ) {
                                    starredOnlyFilter.toggle()
                                }
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 4)

            ForEach(filteredTranscriptSegments) { seg in
                let isActive = activePlayingSegmentID == seg.id
                let isEditingRow = editingSegmentID == seg.id
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        // Clickable Speaker Name Pill -> Opens Rename & Voiceprint Enrollment Popover
                        Button {
                            renamingSegmentID = seg.id
                        } label: {
                            HStack(spacing: 4) {
                                Text(seg.resolvedSpeakerName)
                                    .font(.system(size: 12, weight: .semibold))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .medium))
                                    .opacity(0.65)
                            }
                            .foregroundStyle(seg.speaker == .me ? AppTheme.brandPrimary : AppTheme.textPrimary.opacity(0.8))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Capsule().fill(seg.speaker == .me ? AppTheme.brandSoftFill : AppTheme.softCardBg))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("点击修改说话人姓名或记住声纹")
                        .popover(
                            isPresented: Binding(
                                get: { renamingSegmentID == seg.id },
                                set: { if !$0 && renamingSegmentID == seg.id { renamingSegmentID = nil } }
                            ),
                            arrowEdge: .bottom
                        ) {
                            SpeakerRenamePopoverView(
                                currentName: seg.resolvedSpeakerName,
                                hasAudioFile: hasAudioFile,
                                candidateNames: speakerCandidateNames,
                                onConfirm: { newName, applyAll, updateMinutes, enrollVP in
                                    renamingSegmentID = nil
                                    Task {
                                        await appState.renameSpeaker(
                                            meetingID: meeting.id,
                                            oldName: seg.resolvedSpeakerName,
                                            newName: newName,
                                            onlySegmentID: applyAll ? nil : seg.id,
                                            updateMinutes: updateMinutes,
                                            enrollVoiceprint: enrollVP
                                        )
                                    }
                                },
                                onCancel: { renamingSegmentID = nil }
                            )
                        }

                        // Timestamp seek pill
                        Button {
                            if hasAudioFile {
                                audioPlayer.seek(to: seg.timestamp, autoPlay: true)
                            }
                        } label: {
                            HStack(spacing: 3) {
                                if hasAudioFile {
                                    Image(systemName: isActive && audioPlayer.isPlaying ? "speaker.wave.2.fill" : "play.fill")
                                        .font(.system(size: 8.5))
                                }
                                Text(seg.formattedTimestamp)
                                    .font(.system(size: 11, design: .monospaced))
                            }
                            .foregroundStyle(isActive ? AppTheme.brandPrimary : AppTheme.textMuted)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        // Star key quote button
                        Button {
                            appState.toggleStarSegment(meetingID: meeting.id, segmentID: seg.id)
                        } label: {
                            Image(systemName: seg.isStarred ? "star.fill" : "star")
                                .font(.system(size: 11))
                                .foregroundStyle(seg.isStarred ? AppTheme.warningAmber : AppTheme.textMuted.opacity(0.65))
                                .frame(width: 22, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(seg.isStarred ? "取消标星重点" : "标星为重点发言")

                        // Edit transcript typo button
                        Button {
                            if isEditingRow {
                                appState.updateSegmentText(meetingID: meeting.id, segmentID: seg.id, newText: editingSegmentDraft)
                                editingSegmentID = nil
                            } else {
                                editingSegmentDraft = seg.text
                                editingSegmentID = seg.id
                            }
                        } label: {
                            Image(systemName: isEditingRow ? "checkmark" : "pencil")
                                .font(.system(size: 10.5))
                                .foregroundStyle(isEditingRow ? AppTheme.brandPrimary : AppTheme.textMuted.opacity(0.65))
                                .frame(width: 22, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(isEditingRow ? "保存修改" : "修正转写错字")
                    }

                    if isEditingRow {
                        HStack(spacing: 6) {
                            TextField("修正逐字稿文本", text: $editingSegmentDraft)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 13))
                                .onSubmit {
                                    appState.updateSegmentText(meetingID: meeting.id, segmentID: seg.id, newText: editingSegmentDraft)
                                    editingSegmentID = nil
                                }
                            Button("取消") {
                                editingSegmentID = nil
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11.5))
                            .foregroundStyle(AppTheme.textSecondary)
                        }
                    } else {
                        Text(seg.text)
                            .font(.system(size: 13.5))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineSpacing(4)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .onTapGesture(count: 2) {
                                editingSegmentDraft = seg.text
                                editingSegmentID = seg.id
                            }
                            .onTapGesture {
                                if hasAudioFile {
                                    audioPlayer.seek(to: seg.timestamp, autoPlay: true)
                                }
                            }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isActive ? AppTheme.mindMapNodeFill : (seg.isStarred ? AppTheme.warningAmber.opacity(0.06) : Color.clear))
                )
            }
        }
    }

    private var speakerCandidateNames: [String] {
        var list: [String] = []
        let local = appState.settings.localUserName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !local.isEmpty { list.append(local) }
        for vp in appState.voiceprints where !list.contains(vp.name) {
            list.append(vp.name)
        }
        for att in meeting.calendarAttendees where !list.contains(att) {
            list.append(att)
        }
        return list
    }

    private func transcriptFilterPill(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? AppTheme.brandPrimary : AppTheme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(isSelected ? AppTheme.brandSoftFill : AppTheme.softCardBg))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Ask AI Conversation View

    private var minimalAskAIView: some View {
        VStack(alignment: .leading, spacing: 14) {
            if meeting.chatHistory.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("基于本次会议内容随时提问")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("可在下方直接输入问题，或点击快捷指令一键生成周报、邮件、待办与风险清单。")
                        .font(.system(size: 12.5))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding(.vertical, 12)
            }

            ForEach(meeting.chatHistory) { msg in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(msg.role == .user ? "我" : "AI 总结")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(AppTheme.textSecondary)
                        Spacer()
                        if msg.role == .assistant && !msg.content.isEmpty {
                            if let msgUsage = msg.tokenUsage, !msgUsage.isEmpty {
                                Text("\(msgUsage.formattedCompact) tokens")
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppTheme.textMuted)
                                    .help(msgUsage.detailedSummary)
                            }
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(msg.content, forType: .string)
                                showToast("已复制回答")
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 10.5))
                                    Text("复制")
                                        .font(.system(size: 11))
                                }
                                .foregroundStyle(AppTheme.textSecondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if msg.content.isEmpty {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text("思考中...")
                                .font(.system(size: 13))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    } else if msg.role == .assistant {
                        MarkdownContentView(markdown: msg.content, fontSize: 13.5)
                    } else {
                        Text(msg.content)
                            .font(.system(size: 13.5))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(msg.role == .user ? AppTheme.brandSoftFill.opacity(0.6) : AppTheme.softCardBg)
                )
            }
        }
    }

    private func sendChat() {
        let q = chatDraft
        chatDraft = ""
        Task { await appState.askAI(meetingID: meeting.id, question: q) }
    }

    private func showToast(_ text: String) {
        copiedToast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            if copiedToast == text { copiedToast = nil }
        }
    }
}

// MARK: - Minimal Synced Audio Playback Bar

private struct AudioPlaybackStrip: View {
    @ObservedObject var player: MeetingAudioPlayer

    var body: some View {
        HStack(spacing: 10) {
            Button {
                player.togglePlayPause()
            } label: {
                ZStack {
                    Circle()
                        .fill(AppTheme.brandSoftFill)
                        .frame(width: 28, height: 28)
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppTheme.brandPrimary)
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)

            Text(MeetingAudioPlayer.formatTime(player.currentTime))
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 42, alignment: .trailing)

            Slider(
                value: Binding(
                    get: { player.currentTime },
                    set: { player.seek(to: $0, autoPlay: false) }
                ),
                in: 0...max(0.1, player.duration)
            )
            .tint(AppTheme.brandPrimary)
            .controlSize(.small)

            Text(MeetingAudioPlayer.formatTime(player.duration))
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(AppTheme.textMuted)
                .frame(width: 42, alignment: .leading)

            Button {
                player.cycleRate()
            } label: {
                Text(String(format: "%.2gx", player.playbackRate))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(AppTheme.neutralPill))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("切换播放倍速")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(AppTheme.subtleBorder, lineWidth: 1)
        )
    }
}

// MARK: - Doubao-Style Elevated AI Composer Input Card (With Stop Generation)

private struct DoubaoAIComposerView: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let isSending: Bool
    let onQuickPrompt: (String) -> Void
    let onSend: () -> Void
    let onStop: () -> Void

    private let quickTags = ["整理为邮件", "提炼周报", "列出待办", "风险与分歧"]

    private var canSend: Bool {
        !isSending && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(
                "向 AI 追问会议细节，或直接输入整理指令...",
                text: $text,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.system(size: 13.5))
            .foregroundStyle(AppTheme.textPrimary)
            .lineLimit(1...5)
            .focused(isFocused)
            .onSubmit {
                if canSend { onSend() }
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)

            HStack(spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(quickTags, id: \.self) { tag in
                            ComposerQuickChip(label: tag, disabled: isSending) {
                                onQuickPrompt(tag)
                            }
                        }
                    }
                }

                Spacer(minLength: 8)

                if canSend {
                    Text("⏎ 发送")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.textMuted)
                }

                if isSending {
                    Button(action: onStop) {
                        ZStack {
                            Circle()
                                .fill(AppTheme.neutralPill)
                                .frame(width: 30, height: 30)
                            RoundedRectangle(cornerRadius: 2.5)
                                .fill(AppTheme.textPrimary)
                                .frame(width: 10, height: 10)
                        }
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("停止生成")
                } else {
                    Button {
                        if canSend { onSend() }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(canSend ? AppTheme.brandPrimary : AppTheme.neutralPill)
                                .frame(width: 30, height: 30)
                            Image(systemName: "arrow.up")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(canSend ? Color.white : AppTheme.textMuted)
                        }
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .help("发送 (Return)")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    isFocused.wrappedValue ? AppTheme.brandPrimary.opacity(0.45) : AppTheme.subtleBorder,
                    lineWidth: isFocused.wrappedValue ? 1.5 : 1
                )
        )
        .shadow(
            color: isFocused.wrappedValue ? AppTheme.brandPrimary.opacity(0.10) : Color.black.opacity(0.05),
            radius: isFocused.wrappedValue ? 12 : 8,
            x: 0,
            y: 3
        )
        .animation(.easeOut(duration: 0.16), value: isFocused.wrappedValue)
        .onTapGesture {
            isFocused.wrappedValue = true
        }
    }
}

private struct ComposerQuickChip: View {
    let label: String
    let disabled: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(isHovering ? AppTheme.brandPrimary : AppTheme.textMuted)
                Text(label)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(isHovering ? AppTheme.brandPrimary : AppTheme.textSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(isHovering ? AppTheme.brandSoftFill : AppTheme.softCardBg)
            )
            .overlay(
                Capsule()
                    .strokeBorder(isHovering ? AppTheme.mindMapLine : AppTheme.subtleBorder.opacity(0.7), lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { isHovering = $0 }
    }
}

private struct TokenUsagePopoverView: View {
    let title: String
    let usage: TokenUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                if usage.isEstimated {
                    Text("估算")
                        .font(.system(size: 10.5))
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(AppTheme.neutralPill))
                }
            }

            Divider().overlay(AppTheme.divider)

            VStack(spacing: 6) {
                statRow("总计 Tokens", TokenUsage.formatNumber(usage.totalTokens), bold: true)
                statRow("输入 (Input)", TokenUsage.formatNumber(usage.inputTokens))
                statRow("输出 (Output)", TokenUsage.formatNumber(usage.outputTokens))
                if usage.cachedTokens > 0 {
                    statRow("缓存命中 (Cached)", TokenUsage.formatNumber(usage.cachedTokens))
                }
                if usage.reasoningTokens > 0 {
                    statRow("推理思考 (Reasoning)", TokenUsage.formatNumber(usage.reasoningTokens))
                }
                statRow("AI 调用次数", "\(usage.requestCount) 次")
            }
        }
        .padding(14)
        .frame(width: 230)
        .background(Color.white)
        .preferredColorScheme(.light)
    }

    private func statRow(_ label: String, _ value: String, bold: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: bold ? .semibold : .medium, design: .monospaced))
                .foregroundStyle(AppTheme.textPrimary)
        }
    }
}

// MARK: - Speaker Rename & Voiceprint Enrollment Popover

private struct SpeakerRenamePopoverView: View {
    let currentName: String
    let hasAudioFile: Bool
    let candidateNames: [String]
    let onConfirm: (_ newName: String, _ applyAll: Bool, _ updateMinutes: Bool, _ enrollVoiceprint: Bool) -> Void
    let onCancel: () -> Void

    @State private var nameDraft: String = ""
    @State private var applyToAll: Bool = true
    @State private var updateMinutes: Bool = true
    @State private var enrollVoiceprint: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("修改说话人姓名")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)

            TextField("输入姓名（如：林致远）", text: $nameDraft)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12.5))
                .onSubmit { submitIfValid() }

            if !candidateNames.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("快捷选择（声纹库 / 日程参会人）")
                        .font(.system(size: 10.5))
                        .foregroundStyle(AppTheme.textMuted)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(candidateNames.prefix(10), id: \.self) { candidate in
                                Button {
                                    nameDraft = candidate
                                } label: {
                                    Text(candidate)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(nameDraft == candidate ? AppTheme.brandPrimary : AppTheme.textSecondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3.5)
                                        .background(Capsule().fill(nameDraft == candidate ? AppTheme.brandSoftFill : AppTheme.softCardBg))
                                        .contentShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            Divider().overlay(AppTheme.divider)

            VStack(alignment: .leading, spacing: 7) {
                Toggle("同步替换本场所有「\(currentName)」", isOn: $applyToAll)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))

                if applyToAll {
                    Toggle("同步替换纪要与待办中的对应称呼", isOn: $updateMinutes)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))
                }

                if hasAudioFile {
                    Toggle("记住该说话人声纹（跨会议自动认人）", isOn: $enrollVoiceprint)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))
                }
            }

            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())

                Button("确定") {
                    submitIfValid()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AppTheme.brandPrimary.opacity(0.35) : AppTheme.brandPrimary)
                )
                .contentShape(Rectangle())
                .disabled(nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .frame(width: 280)
        .background(Color.white)
        .preferredColorScheme(.light)
        .onAppear {
            nameDraft = (currentName == "发言人" || currentName.hasPrefix("发言人 ")) ? "" : currentName
            enrollVoiceprint = hasAudioFile
        }
    }

    private func submitIfValid() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onConfirm(trimmed, applyToAll, applyToAll && updateMinutes, hasAudioFile && enrollVoiceprint)
    }
}
