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

// MARK: - Doubao-Style Clean Typographic Outline Reading View

struct DoubaoOutlineMinutesView: View {
    let meeting: MeetingSession
    @ObservedObject var appState: AppState
    @ObservedObject private var theme = ThemeManager.shared
    var onJumpToTimestamp: ((TimeInterval) -> Void)? = nil

    @State private var citationCache: [String: MinutesTimestampMatcher.Match] = [:]

    private var citationCacheKey: String {
        let m = meeting.minutes
        return "\(meeting.id.uuidString)|\(m.lastUpdatedAt.timeIntervalSince1970)|\(meeting.segments.count)|\(m.topics.count)|\(m.decisions.count)|\(m.actionItems.count)|\(m.openQuestions.count)|\(onJumpToTimestamp != nil)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let fallback = meeting.minutes.rawMarkdownFallback, !fallback.isEmpty {
                MarkdownContentView(markdown: fallback, fontSize: 13.5)
            } else {
                if !meeting.minutes.overview.isEmpty {
                    outlineSection(L("摘要", "Summary")) {
                        inlineMarkdownText(meeting.minutes.overview)
                            .font(.system(size: 13.5))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineSpacing(5)
                            .textSelection(.enabled)
                    }
                }

                if !meeting.minutes.topics.isEmpty {
                    outlineSection(L("核心要点", "Key Topics")) {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(meeting.minutes.topics) { topic in
                                VStack(alignment: .leading, spacing: 6) {
                                    inlineMarkdownText(topic.title)
                                        .font(.system(size: 13.5, weight: .semibold))
                                        .foregroundStyle(AppTheme.textPrimary)

                                    ForEach(Array(topic.points.enumerated()), id: \.offset) { _, point in
                                        citedBulletRow(
                                            text: point,
                                            bulletColor: AppTheme.textSecondary,
                                            textColor: AppTheme.textPrimary.opacity(0.9)
                                        )
                                    }
                                }
                            }
                        }
                    }
                }

                if !meeting.minutes.decisions.isEmpty {
                    outlineSection(L("会议决议", "Decisions")) {
                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(Array(meeting.minutes.decisions.enumerated()), id: \.offset) { _, decision in
                                citedBulletRow(
                                    text: decision,
                                    bulletColor: AppTheme.brandPrimary,
                                    textColor: AppTheme.textPrimary
                                )
                            }
                        }
                    }
                }

                if !meeting.minutes.actionItems.isEmpty {
                    outlineSection(L("待办事项", "Action Items")) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(meeting.minutes.actionItems) { item in
                                let citation = onJumpToTimestamp != nil ? citationCache[item.task] : nil
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

                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                                            inlineMarkdownText(citation?.displayText ?? item.task)
                                                .font(.system(size: 13))
                                                .strikethrough(item.isCompleted, color: AppTheme.textMuted)
                                                .foregroundStyle(item.isCompleted ? AppTheme.textSecondary : AppTheme.textPrimary)
                                                .textSelection(.enabled)

                                            if let citation, let jump = onJumpToTimestamp {
                                                timestampJumpPill(citation) { jump(citation.timestamp) }
                                            }
                                        }
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
                    }
                }

                if !meeting.minutes.openQuestions.isEmpty {
                    outlineSection(L("待确认问题", "Open Questions")) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(meeting.minutes.openQuestions.enumerated()), id: \.offset) { _, q in
                                citedBulletRow(
                                    text: q,
                                    bulletColor: AppTheme.textSecondary,
                                    textColor: AppTheme.textPrimary.opacity(0.9)
                                )
                            }
                        }
                    }
                }
            }
        }
        .task(id: citationCacheKey) {
            rebuildCitationCache()
        }
    }

    private func rebuildCitationCache() {
        guard onJumpToTimestamp != nil else {
            citationCache = [:]
            return
        }
        let segments = meeting.segments
        var candidates: [String] = []
        for topic in meeting.minutes.topics {
            candidates.append(contentsOf: topic.points)
        }
        candidates.append(contentsOf: meeting.minutes.decisions)
        candidates.append(contentsOf: meeting.minutes.actionItems.map(\.task))
        candidates.append(contentsOf: meeting.minutes.openQuestions)

        var map: [String: MinutesTimestampMatcher.Match] = [:]
        map.reserveCapacity(candidates.count)
        for text in candidates where map[text] == nil {
            if let match = MinutesTimestampMatcher.resolve(for: text, segments: segments) {
                map[text] = match
            }
        }
        citationCache = map
    }

    @ViewBuilder
    private func citedBulletRow(text: String, bulletColor: Color, textColor: Color) -> some View {
        let citation = onJumpToTimestamp != nil ? citationCache[text] : nil
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundStyle(bulletColor)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                inlineMarkdownText(citation?.displayText ?? text)
                    .font(.system(size: 13))
                    .foregroundStyle(textColor)
                    .lineSpacing(4)
                    .textSelection(.enabled)

                if let citation, let jump = onJumpToTimestamp {
                    timestampJumpPill(citation) {
                        jump(citation.timestamp)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func timestampJumpPill(_ match: MinutesTimestampMatcher.Match, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: "play.fill")
                    .font(.system(size: 7.5))
                Text(match.formattedTimestamp)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
            }
            .foregroundStyle(AppTheme.brandPrimary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(AppTheme.brandSoftFill.opacity(0.85)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(L("跳转到 \(match.formattedTimestamp) 查看原文并回放录音", "Jump to \(match.formattedTimestamp) in transcript & play audio"))
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
