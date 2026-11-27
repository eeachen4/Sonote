import SwiftUI
import SonoteCore

/// Right-hand "实时总结" pane matching Doubao Work's exact minimalist aesthetic:
/// clean title + Mind-Map / Outline pill switch + pale-blue tree diagram or serene outline.
struct SmartMinutesPaneView: View {
    let meeting: MeetingSession
    @ObservedObject var appState: AppState
    @ObservedObject private var theme = ThemeManager.shared

    enum SummaryDisplayMode: String, CaseIterable {
        case mindMap
        case outline
    }

    @State private var displayMode: SummaryDisplayMode = .mindMap

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Minimal Header: "实时总结" + [ ⎇ | ≡ ] toggle pill
            HStack {
                Text(L("实时总结", "Live Summary"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                if appState.isGeneratingMinutes {
                    ProgressView()
                        .controlSize(.mini)
                        .padding(.leading, 4)
                }

                Spacer()

                // Manual refresh button (subtle, only visible when there is transcript text)
                if !meeting.segments.isEmpty && !appState.isGeneratingMinutes {
                    Button {
                        Task { await appState.refreshMinutesNow(for: meeting.id, isFinal: false) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(L("立即更新实时总结", "Refresh Live Summary"))
                }

                // Exact Doubao-style segmented view mode toggle (Mind-Map vs Outline)
                HStack(spacing: 2) {
                    modeToggleButton(icon: "arrow.branch", mode: .mindMap, help: L("思维导图视图", "Mind-Map View"))
                    modeToggleButton(icon: "list.bullet", mode: .outline, help: L("大纲列表视图", "Outline View"))
                }
                .padding(3)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppTheme.neutralPill)
                )

                // Collapse into top-left floating mini recording window
                if appState.activeRecordingMeetingID == meeting.id {
                    Button {
                        appState.collapseToTopLeftMiniWindow()
                    } label: {
                        Image(systemName: "pip.enter")
                            .font(.system(size: 12.5))
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(AppTheme.neutralPill)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help(L("收起为屏幕左上角悬浮小窗", "Collapse to Floating Capsule"))
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 20)
            .padding(.bottom, 16)

            // Main Summary Body
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if meeting.minutes.isEmpty {
                        waitingForSummaryPlaceholder
                    } else if displayMode == .mindMap {
                        DoubaoMindMapView(meeting: meeting, appState: appState)
                    } else {
                        DoubaoOutlineMinutesView(meeting: meeting, appState: appState)
                    }
                }
                .padding(.horizontal, 26)
                .padding(.bottom, 28)
            }
        }
        .background(AppTheme.canvasWhite)
    }

    private func modeToggleButton(icon: String, mode: SummaryDisplayMode, help: String) -> some View {
        let active = displayMode == mode
        return Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                displayMode = mode
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 12.5, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? AppTheme.textPrimary : AppTheme.textSecondary)
                .frame(width: 26, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(active ? AppTheme.elevatedSurface : Color.clear)
                        .shadow(color: active ? .black.opacity(0.06) : .clear, radius: 2, y: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// Exact match to Screenshot 1: pale-blue skeleton mind-map tree + "正在识别说话人和讨论内容..." card
    private var waitingForSummaryPlaceholder: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 110)

            // Pale-blue skeleton mind-map branch diagram
            VStack(alignment: .leading, spacing: 12) {
                SkeletonPill(width: 96, height: 32, fill: AppTheme.mindMapNodeFill, cornerRadius: 8)

                HStack(alignment: .top, spacing: 0) {
                    // Subtle tree branch lines
                    ZStack(alignment: .topLeading) {
                        Path { path in
                            path.move(to: CGPoint(x: 18, y: -12))
                            path.addLine(to: CGPoint(x: 18, y: 118))
                            // Branch 1
                            path.move(to: CGPoint(x: 18, y: 16))
                            path.addQuadCurve(to: CGPoint(x: 34, y: 20), control: CGPoint(x: 18, y: 20))
                            // Branch 2
                            path.move(to: CGPoint(x: 18, y: 66))
                            path.addQuadCurve(to: CGPoint(x: 34, y: 70), control: CGPoint(x: 18, y: 70))
                        }
                        .stroke(AppTheme.mindMapLine, lineWidth: 1.2)
                    }
                    .frame(width: 38, height: 112)

                    VStack(alignment: .leading, spacing: 14) {
                        SkeletonPill(width: 180, height: 34, fill: AppTheme.mindMapNodeFill, cornerRadius: 8)
                        SkeletonPill(width: 108, height: 34, fill: AppTheme.mindMapNodeFill, cornerRadius: 8)
                    }
                    .padding(.top, 2)
                }
            }

            // Status box matching Screenshot 1
            VStack(alignment: .leading, spacing: 12) {
                Text(waitingStatusLine)
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundStyle(AppTheme.textPrimary)

                if case .downloading(let progress, _) = appState.mlxModelState, progress > 0 {
                    ProgressView(value: progress)
                        .tint(AppTheme.brandPrimary)
                }

                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(AppTheme.waveformInactive)
                        .frame(width: 4, height: 4)
                        .padding(.top, 5)
                    VStack(alignment: .leading, spacing: 8) {
                        SkeletonPill(width: nil, height: 10, fill: AppTheme.skeletonBg, cornerRadius: 5)
                        SkeletonPill(width: 190, height: 10, fill: AppTheme.skeletonBg, cornerRadius: 5)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppTheme.softCardBg)
            )
            .padding(.top, 2)
        }
    }

    private var waitingStatusLine: String {
        if appState.mlxModelState.isBusy {
            return appState.mlxModelState.statusText
        }
        if appState.isGeneratingMinutes {
            return L("正在提炼会议核心要点...", "Synthesizing key takeaways...")
        }
        return L("正在识别说话人和讨论内容...", "Listening for speakers and discussion...")
    }
}

// MARK: - Doubao-Style Clean Vertical Branching Mind-Map View

struct DoubaoMindMapView: View {
    let meeting: MeetingSession
    @ObservedObject var appState: AppState
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let fallback = meeting.minutes.rawMarkdownFallback, !fallback.isEmpty {
                MarkdownContentView(markdown: fallback, fontSize: 13.5)
            } else {
                // Root node
                Text(meeting.minutes.suggestedTitle.isEmpty ? meeting.title : meeting.minutes.suggestedTitle)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(AppTheme.brandSoftFill)
                    )

                // Child branches connected by clean vertical spine
                VStack(alignment: .leading, spacing: 14) {
                    if !meeting.minutes.overview.isEmpty {
                        mindMapBranch(title: L("会议概览", "Overview"), items: [meeting.minutes.overview])
                    }

                    ForEach(meeting.minutes.topics) { topic in
                        mindMapBranch(title: topic.title, items: topic.points)
                    }

                    if !meeting.minutes.decisions.isEmpty {
                        mindMapBranch(title: L("关键决议", "Key Decisions"), items: meeting.minutes.decisions)
                    }

                    if !meeting.minutes.actionItems.isEmpty {
                        mindMapActionBranch(items: meeting.minutes.actionItems)
                    }

                    if !meeting.minutes.openQuestions.isEmpty {
                        mindMapBranch(title: L("待确认问题", "Open Questions"), items: meeting.minutes.openQuestions)
                    }
                }
                .padding(.leading, 18)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(AppTheme.mindMapLine)
                        .frame(width: 1.5)
                        .padding(.leading, 7)
                        .padding(.vertical, 4)
                }
            }
        }
    }

    private func mindMapBranch(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(AppTheme.mindMapLine)
                    .frame(width: 12, height: 1.5)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(AppTheme.mindMapNodeFill)
                    )
            }

            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(items, id: \.self) { point in
                        HStack(alignment: .top, spacing: 7) {
                            Circle()
                                .fill(AppTheme.brandPrimary.opacity(0.5))
                                .frame(width: 4.5, height: 4.5)
                                .padding(.top, 6)
                            inlineMarkdownText(point)
                                .font(.system(size: 13))
                                .foregroundStyle(AppTheme.textPrimary.opacity(0.9))
                                .lineSpacing(4)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.leading, 26)
            }
        }
    }

    private func mindMapActionBranch(items: [ActionItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(AppTheme.mindMapLine)
                    .frame(width: 12, height: 1.5)
                Text(L("待办事项", "Action Items"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(AppTheme.mindMapNodeFill)
                    )
            }

            VStack(alignment: .leading, spacing: 7) {
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Button {
                            appState.toggleActionItem(meetingID: meeting.id, actionID: item.id)
                        } label: {
                            Image(systemName: item.isCompleted ? "checkmark.square.fill" : "square")
                                .font(.system(size: 13.5))
                                .foregroundStyle(item.isCompleted ? AppTheme.brandPrimary : AppTheme.textMuted)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 1)

                        inlineMarkdownText(actionItemDisplayText(item))
                            .font(.system(size: 13))
                            .strikethrough(item.isCompleted, color: AppTheme.textMuted)
                            .foregroundStyle(item.isCompleted ? AppTheme.textSecondary : AppTheme.textPrimary)
                            .lineSpacing(3)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(.leading, 26)
        }
    }

    private func actionItemDisplayText(_ item: ActionItem) -> String {
        var suffix: [String] = []
        if !item.owner.isEmpty && item.owner != "待定" { suffix.append(item.owner) }
        if !item.dueDate.isEmpty { suffix.append(item.dueDate) }
        return suffix.isEmpty ? item.task : "\(item.task)（\(suffix.joined(separator: " · "))）"
    }
}

// MARK: - Doubao-Style Clean Typographic Outline View (With Optional Inline Editing)

struct DoubaoOutlineMinutesView: View {
    let meeting: MeetingSession
    @ObservedObject var appState: AppState
    @ObservedObject private var theme = ThemeManager.shared
    var isEditing: Bool = false

    @State private var newActionTask: String = ""
    @State private var newActionOwner: String = ""
    @State private var newActionDue: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let fallback = meeting.minutes.rawMarkdownFallback, !fallback.isEmpty {
                MarkdownContentView(markdown: fallback, fontSize: 13.5)
            } else {
                if !meeting.minutes.overview.isEmpty || isEditing {
                    outlineSection(L("摘要", "Summary")) {
                        if isEditing {
                            TextEditor(text: Binding(
                                get: { meeting.minutes.overview },
                                set: { val in appState.updateMeeting(id: meeting.id) { $0.minutes.overview = val } }
                            ))
                            .font(.system(size: 13))
                            .frame(minHeight: 68)
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.softCardBg))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(AppTheme.subtleBorder))
                        } else {
                            inlineMarkdownText(meeting.minutes.overview)
                                .font(.system(size: 13.5))
                                .foregroundStyle(AppTheme.textPrimary)
                                .lineSpacing(5)
                                .textSelection(.enabled)
                        }
                    }
                }

                if !meeting.minutes.topics.isEmpty {
                    outlineSection(L("核心要点", "Key Topics")) {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(Array(meeting.minutes.topics.enumerated()), id: \.element.id) { tIdx, topic in
                                VStack(alignment: .leading, spacing: 6) {
                                    if isEditing {
                                        TextField(L("议题标题", "Topic title"), text: Binding(
                                            get: { topic.title },
                                            set: { val in
                                                appState.updateMeeting(id: meeting.id) { m in
                                                    if tIdx < m.minutes.topics.count { m.minutes.topics[tIdx].title = val }
                                                }
                                            }
                                        ))
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 13, weight: .semibold))
                                    } else {
                                        inlineMarkdownText(topic.title)
                                            .font(.system(size: 13.5, weight: .semibold))
                                            .foregroundStyle(AppTheme.textPrimary)
                                    }

                                    ForEach(Array(topic.points.enumerated()), id: \.offset) { pIdx, point in
                                        HStack(alignment: .top, spacing: 8) {
                                            Text("•")
                                                .foregroundStyle(AppTheme.textSecondary)
                                            if isEditing {
                                                TextField(L("要点内容", "Key point"), text: Binding(
                                                    get: { point },
                                                    set: { val in
                                                        appState.updateMeeting(id: meeting.id) { m in
                                                            if tIdx < m.minutes.topics.count && pIdx < m.minutes.topics[tIdx].points.count {
                                                                m.minutes.topics[tIdx].points[pIdx] = val
                                                            }
                                                        }
                                                    }
                                                ))
                                                .textFieldStyle(.roundedBorder)
                                                .font(.system(size: 12.5))
                                            } else {
                                                inlineMarkdownText(point)
                                                    .font(.system(size: 13))
                                                    .foregroundStyle(AppTheme.textPrimary.opacity(0.9))
                                                    .lineSpacing(4)
                                                    .textSelection(.enabled)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                if !meeting.minutes.decisions.isEmpty {
                    outlineSection(L("会议决议", "Decisions")) {
                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(Array(meeting.minutes.decisions.enumerated()), id: \.offset) { dIdx, decision in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("•")
                                        .foregroundStyle(AppTheme.brandPrimary)
                                    if isEditing {
                                        TextField(L("决议内容", "Decision"), text: Binding(
                                            get: { decision },
                                            set: { val in
                                                appState.updateMeeting(id: meeting.id) { m in
                                                    if dIdx < m.minutes.decisions.count { m.minutes.decisions[dIdx] = val }
                                                }
                                            }
                                        ))
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 12.5))
                                    } else {
                                        inlineMarkdownText(decision)
                                            .font(.system(size: 13))
                                            .foregroundStyle(AppTheme.textPrimary)
                                            .lineSpacing(4)
                                            .textSelection(.enabled)
                                    }
                                }
                            }
                        }
                    }
                }

                if !meeting.minutes.actionItems.isEmpty || isEditing {
                    outlineSection(L("待办事项", "Action Items")) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(meeting.minutes.actionItems.enumerated()), id: \.element.id) { aIdx, item in
                                HStack(alignment: .top, spacing: 8) {
                                    Button {
                                        appState.toggleActionItem(meetingID: meeting.id, actionID: item.id)
                                    } label: {
                                        Image(systemName: item.isCompleted ? "checkmark.square.fill" : "square")
                                            .font(.system(size: 14))
                                            .foregroundStyle(item.isCompleted ? AppTheme.brandPrimary : AppTheme.textMuted)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.top, 1)

                                    if isEditing {
                                        HStack(spacing: 6) {
                                            TextField(L("待办事项", "Task"), text: Binding(
                                                get: { item.task },
                                                set: { val in
                                                    appState.updateMeeting(id: meeting.id) { m in
                                                        if aIdx < m.minutes.actionItems.count { m.minutes.actionItems[aIdx].task = val }
                                                    }
                                                }
                                            ))
                                            .textFieldStyle(.roundedBorder)
                                            .font(.system(size: 12.5))

                                            TextField(L("负责人", "Owner"), text: Binding(
                                                get: { item.owner },
                                                set: { val in
                                                    appState.updateMeeting(id: meeting.id) { m in
                                                        if aIdx < m.minutes.actionItems.count { m.minutes.actionItems[aIdx].owner = val }
                                                    }
                                                }
                                            ))
                                            .textFieldStyle(.roundedBorder)
                                            .font(.system(size: 12))
                                            .frame(width: 72)

                                            TextField(L("截止时间", "Due"), text: Binding(
                                                get: { item.dueDate },
                                                set: { val in
                                                    appState.updateMeeting(id: meeting.id) { m in
                                                        if aIdx < m.minutes.actionItems.count { m.minutes.actionItems[aIdx].dueDate = val }
                                                    }
                                                }
                                            ))
                                            .textFieldStyle(.roundedBorder)
                                            .font(.system(size: 12))
                                            .frame(width: 78)

                                            Button {
                                                appState.updateMeeting(id: meeting.id) { m in
                                                    m.minutes.actionItems.removeAll { $0.id == item.id }
                                                }
                                            } label: {
                                                Image(systemName: "minus.circle")
                                                    .foregroundStyle(AppTheme.recordingRed.opacity(0.8))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    } else {
                                        VStack(alignment: .leading, spacing: 2) {
                                            inlineMarkdownText(item.task)
                                                .font(.system(size: 13))
                                                .strikethrough(item.isCompleted, color: AppTheme.textMuted)
                                                .foregroundStyle(item.isCompleted ? AppTheme.textSecondary : AppTheme.textPrimary)
                                                .textSelection(.enabled)
                                            let meta = [item.owner, item.dueDate].filter { !$0.isEmpty && $0 != "待定" && $0 != "TBD" }.joined(separator: " · ")
                                            if !meta.isEmpty {
                                                Text(meta)
                                                    .font(.system(size: 11.5))
                                                    .foregroundStyle(AppTheme.textSecondary)
                                            }
                                        }
                                    }
                                }
                            }

                            if isEditing {
                                HStack(spacing: 6) {
                                    TextField(L("新增待办...", "New action item..."), text: $newActionTask)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 12.5))
                                    TextField(L("负责人", "Owner"), text: $newActionOwner)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 12))
                                        .frame(width: 72)
                                    TextField(L("截止", "Due"), text: $newActionDue)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 12))
                                        .frame(width: 72)
                                    Button(L("添加", "Add")) {
                                        let t = newActionTask.trimmingCharacters(in: .whitespacesAndNewlines)
                                        guard !t.isEmpty else { return }
                                        let owner = newActionOwner.trimmingCharacters(in: .whitespacesAndNewlines)
                                        let due = newActionDue.trimmingCharacters(in: .whitespacesAndNewlines)
                                        appState.updateMeeting(id: meeting.id) { m in
                                            m.minutes.actionItems.append(ActionItem(
                                                task: t,
                                                owner: owner.isEmpty ? L("待定", "TBD") : owner,
                                                dueDate: due
                                            ))
                                        }
                                        newActionTask = ""
                                        newActionOwner = ""
                                        newActionDue = ""
                                    }
                                    .controlSize(.small)
                                }
                                .padding(.top, 4)
                            }
                        }
                    }
                }

                if !meeting.minutes.openQuestions.isEmpty {
                    outlineSection(L("待确认问题", "Open Questions")) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(meeting.minutes.openQuestions, id: \.self) { q in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("•")
                                        .foregroundStyle(AppTheme.textSecondary)
                                    inlineMarkdownText(q)
                                        .font(.system(size: 13))
                                        .foregroundStyle(AppTheme.textPrimary.opacity(0.9))
                                        .lineSpacing(4)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func outlineSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)
            content()
        }
    }
}
