import SwiftUI
import AppKit
import UniformTypeIdentifiers
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

// MARK: - Doubao-Style Interactive Collapsible Vertical Branching Mind-Map View

struct DoubaoMindMapView: View {
    let meeting: MeetingSession
    @ObservedObject var appState: AppState
    @ObservedObject private var theme = ThemeManager.shared
    var onJumpToTimestamp: ((TimeInterval) -> Void)? = nil
    var isExportable: Bool = false
    var onToast: ((String) -> Void)? = nil

    @State private var collapsedBranches: Set<String> = []
    @State private var citationCache: [String: MinutesTimestampMatcher.Match] = [:]

    private var citationCacheKey: String {
        let m = meeting.minutes
        return "mm|\(meeting.id.uuidString)|\(m.lastUpdatedAt.timeIntervalSince1970)|\(meeting.segments.count)|\(m.topics.count)|\(m.decisions.count)|\(m.actionItems.count)|\(m.openQuestions.count)|\(onJumpToTimestamp != nil)"
    }

    private var allBranchKeys: [String] {
        var keys: [String] = []
        if !meeting.minutes.overview.isEmpty { keys.append("overview") }
        for topic in meeting.minutes.topics { keys.append("topic-\(topic.id.uuidString)") }
        if !meeting.minutes.decisions.isEmpty { keys.append("decisions") }
        if !meeting.minutes.actionItems.isEmpty { keys.append("actions") }
        if !meeting.minutes.openQuestions.isEmpty { keys.append("questions") }
        return keys
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if isExportable && meeting.minutes.rawMarkdownFallback == nil && !allBranchKeys.isEmpty {
                mindMapToolbar
            }

            mindMapCanvas(interactive: true)
        }
        .task(id: citationCacheKey) {
            rebuildCitationCache()
        }
    }

    private var mindMapToolbar: some View {
        let allCollapsed = !allBranchKeys.isEmpty && allBranchKeys.allSatisfy { collapsedBranches.contains($0) }
        return HStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    if allCollapsed {
                        collapsedBranches.removeAll()
                    } else {
                        collapsedBranches = Set(allBranchKeys)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: allCollapsed ? "rectangle.expand.vertical" : "rectangle.compress.vertical")
                        .font(.system(size: 10.5))
                    Text(allCollapsed ? L("展开全部", "Expand All") : L("折叠全部", "Collapse All"))
                        .font(.system(size: 11.5, weight: .medium))
                }
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4.5)
                .background(Capsule().fill(AppTheme.softCardBg))
                .overlay(Capsule().strokeBorder(AppTheme.subtleBorder, lineWidth: 0.8))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                appState.copyMermaidMindMapToClipboard(for: meeting)
                onToast?(L("已复制 Mermaid 导图代码", "Copied Mermaid"))
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10.5))
                    Text(L("复制 Mermaid", "Copy Mermaid"))
                        .font(.system(size: 11.5, weight: .medium))
                }
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4.5)
                .background(Capsule().fill(AppTheme.softCardBg))
                .overlay(Capsule().strokeBorder(AppTheme.subtleBorder, lineWidth: 0.8))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)

            Button {
                exportMindMapPNG()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "photo.badge.arrow.down")
                        .font(.system(size: 10.5))
                    Text(L("导出 PNG 图片", "Export PNG"))
                        .font(.system(size: 11.5, weight: .medium))
                }
                .foregroundStyle(AppTheme.brandPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4.5)
                .background(Capsule().fill(AppTheme.brandSoftFill))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(L("将思维导图导出为高清 2× Retina PNG 图片", "Export mind-map as a crisp 2× Retina PNG image"))
        }
    }

    @ViewBuilder
    private func mindMapCanvas(interactive: Bool) -> some View {
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
                        mindMapBranch(
                            key: "overview",
                            title: L("会议概览", "Overview"),
                            items: [meeting.minutes.overview],
                            interactive: interactive,
                            allowCitations: false
                        )
                    }

                    ForEach(meeting.minutes.topics) { topic in
                        mindMapBranch(
                            key: "topic-\(topic.id.uuidString)",
                            title: topic.title,
                            items: topic.points,
                            interactive: interactive,
                            allowCitations: true
                        )
                    }

                    if !meeting.minutes.decisions.isEmpty {
                        mindMapBranch(
                            key: "decisions",
                            title: L("关键决议", "Key Decisions"),
                            items: meeting.minutes.decisions,
                            interactive: interactive,
                            allowCitations: true
                        )
                    }

                    if !meeting.minutes.actionItems.isEmpty {
                        mindMapActionBranch(
                            key: "actions",
                            items: meeting.minutes.actionItems,
                            interactive: interactive
                        )
                    }

                    if !meeting.minutes.openQuestions.isEmpty {
                        mindMapBranch(
                            key: "questions",
                            title: L("待确认问题", "Open Questions"),
                            items: meeting.minutes.openQuestions,
                            interactive: interactive,
                            allowCitations: true
                        )
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

    private func mindMapBranch(
        key: String,
        title: String,
        items: [String],
        interactive: Bool,
        allowCitations: Bool
    ) -> some View {
        let isCollapsed = interactive && collapsedBranches.contains(key)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(AppTheme.mindMapLine)
                    .frame(width: 12, height: 1.5)

                Button {
                    guard interactive else { return }
                    withAnimation(.easeInOut(duration: 0.16)) {
                        if collapsedBranches.contains(key) {
                            collapsedBranches.remove(key)
                        } else {
                            collapsedBranches.insert(key)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if interactive {
                            Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(AppTheme.brandPrimary.opacity(0.75))
                                .frame(width: 10)
                        }
                        Text(title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppTheme.textPrimary)
                        if isCollapsed && !items.isEmpty {
                            Text("\(items.count)")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(AppTheme.brandPrimary)
                                .padding(.horizontal, 5.5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(AppTheme.brandSoftFill))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(AppTheme.mindMapNodeFill)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            if !isCollapsed && !items.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, point in
                        let citation = (interactive && allowCitations && onJumpToTimestamp != nil) ? citationCache[point] : nil
                        HStack(alignment: .top, spacing: 7) {
                            Circle()
                                .fill(AppTheme.brandPrimary.opacity(0.5))
                                .frame(width: 4.5, height: 4.5)
                                .padding(.top, 6)
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                inlineMarkdownText(citation?.displayText ?? point)
                                    .font(.system(size: 13))
                                    .foregroundStyle(AppTheme.textPrimary.opacity(0.9))
                                    .lineSpacing(4)
                                    .textSelection(.enabled)

                                if let citation, let jump = onJumpToTimestamp {
                                    Button {
                                        jump(citation.timestamp)
                                    } label: {
                                        HStack(spacing: 2.5) {
                                            Image(systemName: "play.fill")
                                                .font(.system(size: 7))
                                            Text(citation.formattedTimestamp)
                                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        }
                                        .foregroundStyle(AppTheme.brandPrimary)
                                        .padding(.horizontal, 5.5)
                                        .padding(.vertical, 1.5)
                                        .background(Capsule().fill(AppTheme.brandSoftFill.opacity(0.85)))
                                    }
                                    .buttonStyle(.plain)
                                    .help(L("跳转到 \(citation.formattedTimestamp) 听原声", "Jump to \(citation.formattedTimestamp)"))
                                }
                            }
                        }
                    }
                }
                .padding(.leading, 26)
            }
        }
    }

    private func mindMapActionBranch(key: String, items: [ActionItem], interactive: Bool) -> some View {
        let isCollapsed = interactive && collapsedBranches.contains(key)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(AppTheme.mindMapLine)
                    .frame(width: 12, height: 1.5)

                Button {
                    guard interactive else { return }
                    withAnimation(.easeInOut(duration: 0.16)) {
                        if collapsedBranches.contains(key) {
                            collapsedBranches.remove(key)
                        } else {
                            collapsedBranches.insert(key)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if interactive {
                            Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(AppTheme.brandPrimary.opacity(0.75))
                                .frame(width: 10)
                        }
                        Text(L("待办事项", "Action Items"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppTheme.textPrimary)
                        if isCollapsed {
                            Text("\(items.count)")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(AppTheme.brandPrimary)
                                .padding(.horizontal, 5.5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(AppTheme.brandSoftFill))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(AppTheme.mindMapNodeFill)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            if !isCollapsed {
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
    }

    private func rebuildCitationCache() {
        guard onJumpToTimestamp != nil else {
            citationCache = [:]
            return
        }
        let segments = meeting.segments
        var candidates: [String] = []
        for topic in meeting.minutes.topics { candidates.append(contentsOf: topic.points) }
        candidates.append(contentsOf: meeting.minutes.decisions)
        candidates.append(contentsOf: meeting.minutes.openQuestions)

        var map: [String: MinutesTimestampMatcher.Match] = [:]
        for text in candidates where map[text] == nil {
            if let match = MinutesTimestampMatcher.resolve(for: text, segments: segments) {
                map[text] = match
            }
        }
        citationCache = map
    }

    private func exportMindMapPNG() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        let safeTitle = meeting.title.replacingOccurrences(of: "/", with: "-")
        panel.nameFieldStringValue = "\(safeTitle)-MindMap.png"
        panel.title = L("导出思维导图图片 (PNG)", "Export Mind-Map Image (PNG)")
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let exportView = VStack(alignment: .leading, spacing: 12) {
            mindMapCanvas(interactive: false)
            HStack {
                Spacer()
                Text("Sonote 声记")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(AppTheme.textMuted)
            }
            .padding(.top, 6)
        }
        .padding(28)
        .frame(width: 720, alignment: .leading)
        .background(AppTheme.canvasWhite)
        .environment(\.colorScheme, theme.preferredColorScheme ?? .light)

        let renderer = ImageRenderer(content: exportView)
        renderer.scale = 2.0
        guard let nsImage = renderer.nsImage,
              let tiff = nsImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let pngData = rep.representation(using: .png, properties: [:]) else {
            onToast?(L("导图图片渲染失败", "PNG Render Failed"))
            return
        }

        do {
            try pngData.write(to: url, options: .atomic)
            onToast?(L("已导出 PNG 图片", "Exported PNG"))
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L("导图图片保存失败", "Failed to Save PNG")
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private func actionItemDisplayText(_ item: ActionItem) -> String {
        var suffix: [String] = []
        if !item.owner.isEmpty && item.owner != "待定" && item.owner != "TBD" { suffix.append(item.owner) }
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
