import SwiftUI
import AppKit
import SonoteCore

// MARK: - Global Action Items Aggregation + Apple Reminders Sync Sheet

struct GlobalActionItemsSheet: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var theme = ThemeManager.shared
    @Binding var isPresented: Bool
    var onSelectMeeting: (UUID) -> Void

    @State private var showCompleted: Bool = false
    @State private var selectedOwner: String? = nil
    @State private var searchQuery: String = ""
    @State private var syncFeedback: String? = nil
    @State private var isSyncingReminders: Bool = false

    private var filteredEntries: [GlobalActionItemEntry] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return appState.allActionItems.filter { entry in
            if !showCompleted && entry.item.isCompleted { return false }
            if let owner = selectedOwner, entry.item.owner != owner { return false }
            if !q.isEmpty {
                let matches = entry.item.task.localizedCaseInsensitiveContains(q)
                    || entry.item.owner.localizedCaseInsensitiveContains(q)
                    || entry.item.dueDate.localizedCaseInsensitiveContains(q)
                    || entry.meetingTitle.localizedCaseInsensitiveContains(q)
                if !matches { return false }
            }
            return true
        }
    }

    private var distinctOwners: [String] {
        var list: [String] = []
        for entry in appState.allActionItems {
            let o = entry.item.owner.trimmingCharacters(in: .whitespacesAndNewlines)
            if !o.isEmpty && !list.contains(o) {
                list.append(o)
            }
        }
        return list
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("全局待办清单", "Global Action Items"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(L("自动聚合所有会议的行动项，支持按负责人筛选并一键同步 Apple 提醒事项", "Aggregates action items across all meetings with owner filters & Apple Reminders sync"))
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Spacer()

                Button {
                    copyVisibleAsMarkdown()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                        Text(L("复制 Markdown", "Copy MD"))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(AppTheme.softCardBg))
                    .overlay(Capsule().strokeBorder(AppTheme.subtleBorder, lineWidth: 1))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(filteredEntries.isEmpty)

                Button {
                    Task { await syncVisibleOpenItems() }
                } label: {
                    HStack(spacing: 5) {
                        if isSyncingReminders {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "checklist")
                                .font(.system(size: 11.5))
                        }
                        Text(L("同步到提醒事项", "Sync Reminders"))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(AppTheme.brandPrimary))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isSyncingReminders || filteredEntries.filter { !$0.item.isCompleted }.isEmpty)

                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(AppTheme.softCardBg))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }

            if let syncFeedback {
                Text(syncFeedback)
                    .font(.system(size: 12))
                    .foregroundStyle(syncFeedback.contains("失败") || syncFeedback.contains("未获得") || syncFeedback.lowercased().contains("failed") ? AppTheme.recordingRed : AppTheme.brandPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.brandSoftFill.opacity(0.6)))
            }

            // Search + Filter Strip
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10.5))
                        .foregroundStyle(AppTheme.textMuted)
                    TextField(L("搜索待办、负责人或会议...", "Search tasks, owners, meetings..."), text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .frame(width: 175)
                    if !searchQuery.isEmpty {
                        Button { searchQuery = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10.5))
                                .foregroundStyle(AppTheme.textMuted)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4.5)
                .background(Capsule().fill(AppTheme.inputBackground))
                .overlay(Capsule().strokeBorder(AppTheme.inputBorder, lineWidth: 1))

                Toggle(L("显示已完成", "Show Completed"), isOn: $showCompleted)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))

                Divider().frame(height: 14)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ownerChip(L("全部负责人", "All Owners"), isSelected: selectedOwner == nil) {
                            selectedOwner = nil
                        }
                        ForEach(distinctOwners, id: \.self) { owner in
                            ownerChip(owner, isSelected: selectedOwner == owner) {
                                selectedOwner = (selectedOwner == owner) ? nil : owner
                            }
                        }
                    }
                }
            }

            Divider().overlay(AppTheme.divider)

            if filteredEntries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 28))
                        .foregroundStyle(AppTheme.textMuted)
                    Text(showCompleted ? L("暂无会议待办事项", "No action items yet") : L("太棒了，当前没有未完成的待办事项", "All caught up — no open action items"))
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(filteredEntries) { entry in
                            HStack(alignment: .top, spacing: 10) {
                                Button {
                                    appState.toggleActionItem(meetingID: entry.meetingID, actionID: entry.item.id)
                                } label: {
                                    Image(systemName: entry.item.isCompleted ? "checkmark.square.fill" : "square")
                                        .font(.system(size: 14.5))
                                        .foregroundStyle(entry.item.isCompleted ? AppTheme.brandPrimary : AppTheme.textMuted)
                                        .frame(width: 20, height: 20)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                VStack(alignment: .leading, spacing: 4) {
                                    inlineMarkdownText(entry.item.task)
                                        .font(.system(size: 13))
                                        .strikethrough(entry.item.isCompleted, color: AppTheme.textMuted)
                                        .foregroundStyle(entry.item.isCompleted ? AppTheme.textSecondary : AppTheme.textPrimary)

                                    HStack(spacing: 8) {
                                        if !entry.item.owner.isEmpty && entry.item.owner != "待定" && entry.item.owner != "TBD" {
                                            Text(entry.item.owner)
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundStyle(AppTheme.brandPrimary)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 1.5)
                                                .background(Capsule().fill(AppTheme.brandSoftFill))
                                        }
                                        if !entry.item.dueDate.isEmpty {
                                            Text(L("截止 \(entry.item.dueDate)", "Due \(entry.item.dueDate)"))
                                                .font(.system(size: 11))
                                                .foregroundStyle(AppTheme.textSecondary)
                                        }
                                        Button {
                                            isPresented = false
                                            onSelectMeeting(entry.meetingID)
                                        } label: {
                                            Text(L("来自：\(entry.meetingTitle)", "From: \(entry.meetingTitle)"))
                                                .font(.system(size: 11))
                                                .foregroundStyle(AppTheme.textMuted)
                                                .lineLimit(1)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }

                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(AppTheme.softCardBg))
                        }
                    }
                }
            }
        }
        .padding(22)
        .frame(width: 620, height: 480)
        .background(AppTheme.canvasWhite)
        .tint(AppTheme.brandPrimary)
        .preferredColorScheme(theme.preferredColorScheme)
    }

    private func ownerChip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? AppTheme.brandPrimary : AppTheme.textSecondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(isSelected ? AppTheme.brandSoftFill : AppTheme.softCardBg))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func copyVisibleAsMarkdown() {
        guard !filteredEntries.isEmpty else { return }
        let lines = filteredEntries.map { entry -> String in
            let box = entry.item.isCompleted ? "x" : " "
            var meta: [String] = []
            if !entry.item.owner.isEmpty && entry.item.owner != "待定" && entry.item.owner != "TBD" {
                meta.append("@\(entry.item.owner)")
            }
            if !entry.item.dueDate.isEmpty {
                meta.append(entry.item.dueDate)
            }
            meta.append(entry.meetingTitle)
            return "- [\(box)] \(entry.item.task)（\(meta.joined(separator: " · "))）"
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        syncFeedback = L("已复制 \(lines.count) 条待办为 Markdown 清单", "Copied \(lines.count) action items as Markdown")
    }

    private func syncVisibleOpenItems() async {
        let openItems = filteredEntries.filter { !$0.item.isCompleted }
        guard !openItems.isEmpty else { return }
        isSyncingReminders = true
        syncFeedback = await appState.exportActionItemsToReminders(openItems)
        isSyncingReminders = false
    }
}

// MARK: - Cross-Meeting AI Synthesis & Q&A Sheet

struct CrossMeetingAskAISheet: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var theme = ThemeManager.shared
    @Binding var isPresented: Bool
    var onOpenSavedMeeting: ((UUID) -> Void)? = nil

    @State private var selectedIDs: Set<UUID> = []
    @State private var questionDraft: String = ""
    @State private var lastPromptLabel: String = ""
    @State private var answerText: String = ""
    @State private var lastUsage: TokenUsage? = nil
    @State private var isAsking: Bool = false
    @State private var copiedAnswer: Bool = false
    @State private var savedMeetingID: UUID? = nil

    private var quickQuestions: [(label: String, prompt: String)] {
        [
            (L("汇总阶段周报", "Weekly Digest"), L("请综合选中的多场会议，按时间线和模块提炼一份结构清晰的阶段工作周报/月报。", "Synthesize the selected meetings into a clear chronological weekly/period status report grouped by workstream.")),
            (L("对比未闭环阻塞项", "Compare Blockers"), L("请对比这些会议中反复提到的风险、问题与未闭环阻塞项，整理成表格并标明当前责任人。", "Compare recurring risks, issues, and open blockers across these meetings in a table with current owners.")),
            (L("合并全部决议与待办", "Merge Decisions & Tasks"), L("请将选中会议中的全部关键决议与待办事项去重合并，按负责人分组列出。", "Deduplicate and merge all key decisions and action items from the selected meetings, grouped by owner."))
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("跨会议 AI 问答与汇总", "Cross-Meeting AI Q&A"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(L("勾选多场会议（或按标签一键全选），对比阻塞项进展、生成跨周汇报", "Select multiple meetings (or filter by tag) to compare blockers and draft cross-week reports"))
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(AppTheme.softCardBg))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .top, spacing: 16) {
                // Left: Meeting Selector
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L("选择会议（已选 \(selectedIDs.count)）", "Meetings (\(selectedIDs.count) selected)"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                        Spacer()
                        Button(selectedIDs.count == appState.meetings.count ? L("取消全选", "Clear") : L("全选最近5场", "Latest 5")) {
                            if selectedIDs.count == appState.meetings.count {
                                selectedIDs.removeAll()
                            } else {
                                selectedIDs = Set(appState.meetings.prefix(5).map(\.id))
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.brandPrimary)
                    }

                    // Date-range quick-select pills (This Week / Last 7d / Last 30d)
                    HStack(spacing: 5) {
                        dateRangePill(L("本周", "This Week")) { selectMeetingsInCurrentWeek() }
                        dateRangePill(L("近 7 天", "Last 7d")) { selectMeetings(withinDays: 7) }
                        dateRangePill(L("近 30 天", "Last 30d")) { selectMeetings(withinDays: 30) }
                    }

                    // Tag quick-select pills
                    if !appState.allMeetingTags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 5) {
                                ForEach(appState.allMeetingTags, id: \.self) { tag in
                                    Button {
                                        let matching = appState.meetings.filter { $0.tags.contains(tag) }.map(\.id)
                                        selectedIDs = Set(matching)
                                    } label: {
                                        Text("#\(tag)")
                                            .font(.system(size: 11))
                                            .foregroundStyle(AppTheme.brandPrimary)
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .background(Capsule().fill(AppTheme.brandSoftFill))
                                            .contentShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    ScrollView {
                        VStack(spacing: 5) {
                            ForEach(appState.meetings) { m in
                                let checked = selectedIDs.contains(m.id)
                                Button {
                                    if checked { selectedIDs.remove(m.id) }
                                    else { selectedIDs.insert(m.id) }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: checked ? "checkmark.square.fill" : "square")
                                            .font(.system(size: 13))
                                            .foregroundStyle(checked ? AppTheme.brandPrimary : AppTheme.textMuted)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(m.title)
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundStyle(AppTheme.textPrimary)
                                                .lineLimit(1)
                                            Text(shortDate(m.startedAt))
                                                .font(.system(size: 10.5))
                                                .foregroundStyle(AppTheme.textMuted)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(checked ? AppTheme.mindMapNodeFill : AppTheme.softCardBg))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .frame(width: 225)

                Divider().overlay(AppTheme.divider)

                // Right: Answer & Composer
                VStack(alignment: .leading, spacing: 10) {
                    // Quick Prompt Pills
                    HStack(spacing: 6) {
                        ForEach(quickQuestions, id: \.label) { item in
                            Button {
                                lastPromptLabel = item.label
                                runQuestion(item.prompt)
                            } label: {
                                Text(item.label)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4.5)
                                    .background(Capsule().fill(AppTheme.softCardBg))
                                    .overlay(Capsule().strokeBorder(AppTheme.subtleBorder, lineWidth: 1))
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(selectedIDs.isEmpty || isAsking)
                        }
                        Spacer()
                    }

                    // Answer Area
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            if answerText.isEmpty && !isAsking {
                                Text(L("在左侧勾选 2 场或以上会议，然后点击上方快捷指令或直接输入问题。", "Select 2 or more meetings on the left, then pick a quick prompt or ask a question below."))
                                    .font(.system(size: 13))
                                    .foregroundStyle(AppTheme.textMuted)
                                    .padding(.top, 24)
                            } else {
                                if isAsking && answerText.isEmpty {
                                    HStack(spacing: 8) {
                                        ProgressView().controlSize(.small)
                                        Text(L("正在综合分析 \(selectedIDs.count) 场会议...", "Analyzing \(selectedIDs.count) meetings..."))
                                            .font(.system(size: 13))
                                            .foregroundStyle(AppTheme.textSecondary)
                                    }
                                } else {
                                    MarkdownContentView(markdown: answerText, fontSize: 13)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(AppTheme.softCardBg.opacity(0.65)))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(AppTheme.subtleBorder, lineWidth: 1))

                    if !answerText.isEmpty && !isAsking {
                        HStack(spacing: 10) {
                            if let usage = lastUsage, !usage.isEmpty {
                                Text(L("本次消耗 \(usage.formattedCompact) tokens", "Used \(usage.formattedCompact) tokens"))
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppTheme.textMuted)
                                    .help(usage.detailedSummary)
                            }
                            Spacer()
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(answerText, forType: .string)
                                copiedAnswer = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedAnswer = false }
                            } label: {
                                Label(copiedAnswer ? L("已复制", "Copied") : L("复制 Markdown", "Copy MD"), systemImage: "doc.on.doc")
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4.5)
                                    .background(Capsule().fill(AppTheme.softCardBg))
                                    .overlay(Capsule().strokeBorder(AppTheme.subtleBorder, lineWidth: 1))
                            }
                            .buttonStyle(.plain)

                            if let savedID = savedMeetingID {
                                Button {
                                    isPresented = false
                                    onOpenSavedMeeting?(savedID)
                                } label: {
                                    Label(L("打开已存纪要", "Open Saved"), systemImage: "arrow.up.right.square")
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4.5)
                                        .background(Capsule().fill(AppTheme.successGreen))
                                }
                                .buttonStyle(.plain)
                            } else {
                                Button {
                                    saveAnswerAsMeeting()
                                } label: {
                                    Label(L("存为新纪要", "Save as Minutes"), systemImage: "square.and.arrow.down")
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4.5)
                                        .background(Capsule().fill(AppTheme.brandPrimary))
                                }
                                .buttonStyle(.plain)
                                .help(L("将本次汇总归档为独立会议纪要，支持导出 PDF 与 Obsidian 同步", "Archive this digest as a standalone meeting note"))
                            }
                        }
                    }

                    // Input Bar
                    HStack(spacing: 8) {
                        TextField(L("例如：对比过去三周研发周会里性能优化任务的推进进展...", "e.g., Compare performance milestone progress across the last 3 engineering syncs..."), text: $questionDraft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .onSubmit {
                                let q = questionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !q.isEmpty else { return }
                                questionDraft = ""
                                runQuestion(q)
                            }
                        Button {
                            let q = questionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !q.isEmpty else { return }
                            questionDraft = ""
                            runQuestion(q)
                        } label: {
                            Text(isAsking ? L("分析中...", "Analyzing...") : L("提问", "Ask"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(selectedIDs.isEmpty || isAsking ? AppTheme.brandPrimary.opacity(0.35) : AppTheme.brandPrimary))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(selectedIDs.isEmpty || isAsking || questionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppTheme.inputBackground))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AppTheme.inputBorder, lineWidth: 1))
                }
            }
        }
        .padding(22)
        .frame(width: 780, height: 540)
        .background(AppTheme.canvasWhite)
        .tint(AppTheme.brandPrimary)
        .preferredColorScheme(theme.preferredColorScheme)
        .onAppear {
            if selectedIDs.isEmpty {
                selectedIDs = Set(appState.meetings.prefix(3).map(\.id))
            }
        }
    }

    private func dateRangePill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.horizontal, 7.5)
                .padding(.vertical, 3.5)
                .background(Capsule().fill(AppTheme.softCardBg))
                .overlay(Capsule().strokeBorder(AppTheme.subtleBorder, lineWidth: 0.8))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func selectMeetingsInCurrentWeek() {
        let cal = Calendar.current
        let now = Date()
        guard let startOfWeek = cal.dateInterval(of: .weekOfYear, for: now)?.start else { return }
        selectedIDs = Set(appState.meetings.filter { $0.startedAt >= startOfWeek }.map(\.id))
    }

    private func selectMeetings(withinDays days: Int) {
        let cutoff = Date().addingTimeInterval(-Double(days) * 24 * 3600)
        selectedIDs = Set(appState.meetings.filter { $0.startedAt >= cutoff }.map(\.id))
    }

    private func saveAnswerAsMeeting() {
        guard !answerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let sourceTitles = appState.meetings
            .filter { selectedIDs.contains($0.id) }
            .map(\.title)
        let df = DateFormatter()
        df.dateFormat = "MM-dd"
        let prefix = lastPromptLabel.isEmpty ? L("跨会议汇总", "Cross-Meeting Digest") : lastPromptLabel
        let title = "\(prefix) · \(df.string(from: Date()))"
        let saved = appState.saveCrossMeetingReportAsMeeting(
            title: title,
            markdownContent: answerText,
            sourceMeetingTitles: sourceTitles,
            usage: lastUsage
        )
        savedMeetingID = saved.id
    }

    private func runQuestion(_ prompt: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !selectedIDs.isEmpty, !isAsking else { return }
        if lastPromptLabel.isEmpty { lastPromptLabel = String(trimmed.prefix(16)) }
        isAsking = true
        answerText = ""
        lastUsage = nil
        savedMeetingID = nil
        let ids = Array(selectedIDs)
        Task {
            let result = await appState.askAcrossMeetings(meetingIDs: ids, question: prompt) { delta in
                Task { @MainActor in
                    answerText += delta
                }
            }
            if let result {
                answerText = result.text
                lastUsage = result.usage
            }
            isAsking = false
        }
    }

    private func shortDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "MM-dd HH:mm"
        return df.string(from: date)
    }
}
