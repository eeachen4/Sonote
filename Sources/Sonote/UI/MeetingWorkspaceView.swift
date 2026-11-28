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

    struct MeetingEditDraft: Equatable {
        var title: String
        var minutes: SmartMinutes
        var manualNotes: String
    }

    @StateObject var audioPlayer = MeetingAudioPlayer()
    @State var activeTab: DocTab = .summary
    @State var chatDraft: String = ""
    @State var copiedToast: String? = nil
    @State var showTokenPopover: Bool = false
    @State var isEditingSummary: Bool = false
    @State var editDraft: MeetingEditDraft? = nil
    @State var showQuickNotesInEditor: Bool = false
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
    @State var glossarySuggestions: [String] = []
    @State var pendingScrollSegmentID: UUID? = nil
    @State var showRetranscribeDialog: Bool = false
    @FocusState var isComposerFocused: Bool
    @FocusState var isTranscriptSearchFocused: Bool

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
                // Fixed Top Safe-Area / Editing Bar (keeps scrolled content clear of macOS traffic lights)
                topChromeBar

                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            Spacer().frame(height: 12)

                            // Editable Bold Title
                            if isEditingSummary {
                                TextField(L("会议标题", "Meeting Title"), text: Binding(
                                    get: { editDraft?.title ?? meeting.title },
                                    set: { editDraft?.title = $0 }
                                ))
                                .textFieldStyle(.plain)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(AppTheme.textPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(AppTheme.inputBackground)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .strokeBorder(AppTheme.inputBorder, lineWidth: 1)
                                )
                            } else {
                                TextField(L("新录音", "New Recording"), text: Binding(
                                    get: { meeting.title },
                                    set: { newTitle in
                                        appState.updateMeeting(id: meeting.id) { $0.title = newTitle }
                                    }
                                ))
                                .textFieldStyle(.plain)
                                .font(.system(size: 25, weight: .bold))
                                .foregroundStyle(AppTheme.textPrimary)
                            }

                            // Duration, Token Usage & Tags Subtitle
                            metadataHeaderRow
                                .padding(.top, 8)

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
                                        if meeting.minutes.isEmpty && !isEditingSummary {
                                            Text(L("暂无结构化总结，点击右上角「重新生成」即可由 AI 生成会议纪要。", "No summary yet. Click \"Regenerate\" in the top right to create AI minutes."))
                                                .font(.system(size: 14))
                                                .foregroundStyle(AppTheme.textSecondary)
                                        } else if isEditingSummary {
                                            StructuredMinutesEditorView(
                                                minutes: Binding(
                                                    get: { editDraft?.minutes ?? meeting.minutes },
                                                    set: { editDraft?.minutes = $0 }
                                                )
                                            )
                                        } else {
                                            DoubaoOutlineMinutesView(
                                                meeting: meeting,
                                                appState: appState,
                                                onJumpToTimestamp: meeting.segments.isEmpty ? nil : { ts in
                                                    jumpToTimestampCitation(ts)
                                                }
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
                                        DoubaoMindMapView(
                                            meeting: meeting,
                                            appState: appState,
                                            onJumpToTimestamp: meeting.segments.isEmpty ? nil : { ts in
                                                jumpToTimestampCitation(ts)
                                            },
                                            isExportable: true,
                                            onToast: { showToast($0) }
                                        )
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
                        .padding(.bottom, activeTab == .askAI ? 16 : 28)
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
                    .onChange(of: pendingScrollSegmentID) { _, targetID in
                        guard let targetID, activeTab == .transcript else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                scrollProxy.scrollTo(targetID, anchor: .center)
                            }
                            pendingScrollSegmentID = nil
                        }
                    }
                }

                // Synced Audio Playback Bar (when meeting has recorded/imported audio)
                if hasAudioFile && activeTab != .askAI {
                    AudioPlaybackStrip(
                        player: audioPlayer,
                        autoFollowTranscript: $autoFollowTranscript,
                        fallbackDuration: meeting.duration
                    )
                    .padding(.horizontal, 40)
                    .padding(.top, 4)
                    .padding(.bottom, isEditingSummary ? 12 : 2)
                }

                // Pinned AI Composer when on the "问 AI" tab
                if activeTab == .askAI && !hasNoRecognizedContent {
                    DoubaoAIComposerView(
                        text: $chatDraft,
                        isFocused: $isComposerFocused,
                        isSending: appState.isAskingAI,
                        customPrompts: appState.settings.customAskAIPrompts,
                        onAddCustomPrompt: { prompt in
                            appState.addCustomAskAIPrompt(prompt)
                            showToast(L("已保存自定义指令", "Saved Prompt"))
                        },
                        onRemoveCustomPrompt: { prompt in
                            appState.removeCustomAskAIPrompt(prompt)
                        },
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

                // Bottom Action Bar (hidden during focused minutes editing to maximize canvas space)
                if !isEditingSummary {
                    bottomActionBar
                        .padding(.horizontal, 40)
                        .padding(.vertical, 16)
                }
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

            // Native macOS workspace keyboard shortcuts (⌘1-4 tabs, ⌘E edit, ⌘F search transcript, ⌘[ back Home)
            Group {
                Button("") { switchTab(.summary) }.keyboardShortcut("1", modifiers: .command)
                Button("") { switchTab(.mindMap) }.keyboardShortcut("2", modifiers: .command)
                Button("") { switchTab(.transcript) }.keyboardShortcut("3", modifiers: .command)
                Button("") { switchTab(.askAI) }.keyboardShortcut("4", modifiers: .command)
                Button("") {
                    if isEditingSummary {
                        commitEditing()
                    } else if !meeting.minutes.isEmpty {
                        activeTab = .summary
                        beginEditing()
                    }
                }.keyboardShortcut("e", modifiers: .command)
                Button("") {
                    if isEditingSummary { commitEditing() }
                    activeTab = .transcript
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                        isTranscriptSearchFocused = true
                    }
                }.keyboardShortcut("f", modifiers: .command)
                Button("") {
                    if !isEditingSummary { onBackHome() }
                }.keyboardShortcut("[", modifiers: .command)
            }
            .opacity(0)
            .frame(width: 0, height: 0)
        }
        .onAppear {
            audioPlayer.loadIfNeeded(path: meeting.audioFilePath)
        }
        .onChange(of: meeting.audioFilePath) { _, newPath in
            audioPlayer.loadIfNeeded(path: newPath)
        }
        .onChange(of: meeting.id) { _, _ in
            isEditingSummary = false
            editDraft = nil
            selectedSpeakerFilter = nil
            starredOnlyFilter = false
            transcriptSearchQuery = ""
            renamingSegmentID = nil
            editingSegmentID = nil
            glossarySuggestions = []
            pendingScrollSegmentID = nil
            audioPlayer.loadIfNeeded(path: meeting.audioFilePath)
        }
        .onDisappear {
            audioPlayer.stop()
        }
    }

    // MARK: - Edit Lifecycle (Snapshot Draft + Auto-Clean + Obsidian Sync)

    func beginEditing() {
        editDraft = MeetingEditDraft(
            title: meeting.title,
            minutes: meeting.minutes,
            manualNotes: meeting.manualNotes
        )
        showQuickNotesInEditor = !meeting.manualNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        withAnimation(.easeInOut(duration: 0.16)) {
            isEditingSummary = true
        }
    }

    func cancelEditing() {
        withAnimation(.easeInOut(duration: 0.16)) {
            isEditingSummary = false
            editDraft = nil
        }
    }

    func commitEditing() {
        guard let draft = editDraft else {
            withAnimation(.easeInOut(duration: 0.16)) { isEditingSummary = false }
            return
        }
        let cleanedMinutes = draft.minutes.sanitizedForSave()
        let cleanedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        appState.updateMeeting(id: meeting.id) { m in
            if !cleanedTitle.isEmpty {
                m.title = cleanedTitle
            }
            m.minutes = cleanedMinutes
            m.manualNotes = draft.manualNotes
        }
        // Keep Obsidian / local Markdown folder in sync after manual edits if enabled
        if appState.settings.autoSyncMarkdownFolder,
           !appState.settings.obsidianVaultPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let updatedMeeting = appState.meetings.first(where: { $0.id == meeting.id }) {
            _ = appState.syncMeetingToMarkdownFolder(updatedMeeting)
        }
        withAnimation(.easeInOut(duration: 0.16)) {
            isEditingSummary = false
            editDraft = nil
        }
        showToast(L("已保存修改", "Saved"))
    }

    // MARK: - Tab Strip & Template Switcher

    private var tabStripHeader: some View {
        HStack(spacing: 8) {
            ForEach(DocTab.allCases) { tab in
                Button {
                    if isEditingSummary && tab != .summary {
                        commitEditing()
                    }
                    withAnimation(.easeInOut(duration: 0.14)) {
                        activeTab = tab
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
                if isEditingSummary {
                    // During active manual editing, hide Template & Regenerate to prevent accidental overwrite
                    HStack(spacing: 5) {
                        Circle()
                            .fill(AppTheme.brandPrimary)
                            .frame(width: 6, height: 6)
                        Text(L("编辑模式", "Editing"))
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(AppTheme.brandPrimary)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(AppTheme.brandSoftFill))
                } else {
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
                            beginEditing()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "pencil")
                                    .font(.system(size: 10.5, weight: .medium))
                                Text(L("编辑", "Edit"))
                                    .font(.system(size: 11.5, weight: .medium))
                            }
                            .foregroundStyle(AppTheme.textPrimary.opacity(0.85))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(AppTheme.softCardBg))
                            .overlay(Capsule().strokeBorder(AppTheme.subtleBorder, lineWidth: 0.8))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .help(L("编辑纪要内容与结构", "Edit minutes content & structure"))
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
    }

    func switchTab(_ tab: DocTab) {
        if isEditingSummary && tab != .summary {
            commitEditing()
        }
        withAnimation(.easeInOut(duration: 0.14)) {
            activeTab = tab
        }
    }

    func jumpToTimestampCitation(_ timestamp: TimeInterval) {
        selectedSpeakerFilter = nil
        starredOnlyFilter = false
        transcriptSearchQuery = ""
        let nearest = meeting.segments.min(by: { abs($0.timestamp - timestamp) < abs($1.timestamp - timestamp) })
        withAnimation(.easeInOut(duration: 0.16)) {
            activeTab = .transcript
        }
        if hasAudioFile {
            audioPlayer.seek(to: timestamp, autoPlay: true)
        }
        pendingScrollSegmentID = nearest?.id
        showToast(L("已定位至 \(MinutesTimestampMatcher.formatTimestamp(timestamp))", "Jumped to \(MinutesTimestampMatcher.formatTimestamp(timestamp))"))
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
