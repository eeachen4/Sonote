import SwiftUI
import SonoteCore

// MARK: - Editorial Structured Minutes Editor (Auto-Wrapping, Full CRUD, Card-Grouped)

struct StructuredMinutesEditorView: View {
    @Binding var minutes: SmartMinutes
    @ObservedObject private var theme = ThemeManager.shared

    @State private var newDecisionDraft: String = ""
    @State private var newQuestionDraft: String = ""
    @State private var newActionTask: String = ""
    @State private var newActionOwner: String = ""
    @State private var newActionDue: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if minutes.rawMarkdownFallback != nil {
                rawMarkdownEditorSection
            } else {
                summarySection
                topicsSection
                decisionsSection
                actionItemsSection
                openQuestionsSection
            }
        }
    }

    // MARK: - Raw Markdown Fallback Editor

    private var rawMarkdownEditorSection: some View {
        editorSection(L("纪要正文（Markdown）", "Minutes Content (Markdown)")) {
            EditorialMultilineField(
                placeholder: L("输入会议纪要内容...", "Enter meeting minutes..."),
                text: Binding(
                    get: { minutes.rawMarkdownFallback ?? "" },
                    set: { minutes.rawMarkdownFallback = $0 }
                ),
                minLines: 8,
                maxLines: 24,
                fontSize: 13
            )
        }
    }

    // MARK: - 1. Summary

    private var summarySection: some View {
        editorSection(L("摘要", "Summary")) {
            EditorialMultilineField(
                placeholder: L("用 2–4 句话概括本次会议的核心结论与背景...", "Summarize the key takeaways and context in 2–4 sentences..."),
                text: $minutes.overview,
                minLines: 3,
                maxLines: 12,
                fontSize: 13.5
            )
        }
    }

    // MARK: - 2. Key Topics (Card-Grouped with Full Add/Delete)

    private var topicsSection: some View {
        editorSection(
            L("核心要点", "Key Topics"),
            trailingCount: minutes.topics.count
        ) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(minutes.topics.enumerated()), id: \.element.id) { tIdx, topic in
                    topicEditorCard(topicIndex: tIdx, topic: topic)
                }

                SubtleAddButton(
                    title: L("新增议题", "Add Topic"),
                    icon: "plus"
                ) {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        minutes.topics.append(TopicSection(title: "", points: [""]))
                    }
                }
            }
        }
    }

    private func topicEditorCard(topicIndex tIdx: Int, topic: TopicSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Card Header: Number Pill + Topic Title + Delete Topic
            HStack(alignment: .top, spacing: 8) {
                Text(String(format: "%02d", tIdx + 1))
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppTheme.brandPrimary)
                    .padding(.horizontal, 6.5)
                    .padding(.vertical, 3.5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(AppTheme.brandSoftFill)
                    )
                    .padding(.top, 5)

                EditorialMultilineField(
                    placeholder: L("议题标题...", "Topic title..."),
                    text: Binding(
                        get: { tIdx < minutes.topics.count ? minutes.topics[tIdx].title : "" },
                        set: { val in
                            if tIdx < minutes.topics.count {
                                minutes.topics[tIdx].title = val
                            }
                        }
                    ),
                    minLines: 1,
                    maxLines: 3,
                    fontSize: 13.5,
                    fontWeight: .semibold
                )

                HoverDestructiveIconButton(
                    icon: "trash",
                    help: L("删除此议题", "Delete topic")
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        minutes.topics.removeAll { $0.id == topic.id }
                    }
                }
                .padding(.top, 5)
            }

            // Bullet Points
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(topic.points.enumerated()), id: \.offset) { pIdx, _ in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(AppTheme.brandPrimary.opacity(0.65))
                            .frame(width: 5, height: 5)
                            .padding(.top, 12)
                            .padding(.leading, 8)

                        EditorialMultilineField(
                            placeholder: L("输入要点内容...", "Enter key point..."),
                            text: Binding(
                                get: {
                                    guard tIdx < minutes.topics.count, pIdx < minutes.topics[tIdx].points.count else { return "" }
                                    return minutes.topics[tIdx].points[pIdx]
                                },
                                set: { val in
                                    if tIdx < minutes.topics.count && pIdx < minutes.topics[tIdx].points.count {
                                        minutes.topics[tIdx].points[pIdx] = val
                                    }
                                }
                            ),
                            minLines: 1,
                            maxLines: 6,
                            fontSize: 13
                        )

                        HoverDestructiveIconButton(
                            icon: "xmark",
                            help: L("删除此要点", "Remove point")
                        ) {
                            withAnimation(.easeInOut(duration: 0.14)) {
                                if tIdx < minutes.topics.count && pIdx < minutes.topics[tIdx].points.count {
                                    minutes.topics[tIdx].points.remove(at: pIdx)
                                }
                            }
                        }
                        .padding(.top, 5)
                    }
                }

                // Add Point inside Topic
                Button {
                    withAnimation(.easeInOut(duration: 0.14)) {
                        if tIdx < minutes.topics.count {
                            minutes.topics[tIdx].points.append("")
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .semibold))
                        Text(L("添加要点", "Add Point"))
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .foregroundStyle(AppTheme.brandPrimary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(AppTheme.brandSoftFill.opacity(0.7)))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.leading, 21)
                .padding(.top, 2)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.softCardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(AppTheme.subtleBorder, lineWidth: 1)
        )
    }

    // MARK: - 3. Decisions (Full CRUD + Enter-to-Add)

    private var decisionsSection: some View {
        editorSection(
            L("会议决议", "Decisions"),
            trailingCount: minutes.decisions.count
        ) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(minutes.decisions.enumerated()), id: \.offset) { dIdx, _ in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.brandPrimary)
                            .padding(.top, 9)

                        EditorialMultilineField(
                            placeholder: L("决议内容...", "Decision..."),
                            text: Binding(
                                get: { dIdx < minutes.decisions.count ? minutes.decisions[dIdx] : "" },
                                set: { val in
                                    if dIdx < minutes.decisions.count {
                                        minutes.decisions[dIdx] = val
                                    }
                                }
                            ),
                            minLines: 1,
                            maxLines: 5,
                            fontSize: 13
                        )

                        HoverDestructiveIconButton(
                            icon: "xmark",
                            help: L("删除此决议", "Remove decision")
                        ) {
                            withAnimation(.easeInOut(duration: 0.14)) {
                                if dIdx < minutes.decisions.count {
                                    minutes.decisions.remove(at: dIdx)
                                }
                            }
                        }
                        .padding(.top, 5)
                    }
                }

                // Inline Quick-Add Decision
                HStack(spacing: 8) {
                    EditorialInlineField(
                        placeholder: L("输入新决议后按回车添加...", "Add a decision and press Enter..."),
                        icon: "plus.circle",
                        text: $newDecisionDraft,
                        onSubmit: appendDecision
                    )

                    CleanPrimaryButton(
                        title: L("添加", "Add"),
                        disabled: newDecisionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        action: appendDecision
                    )
                }
            }
        }
    }

    private func appendDecision() {
        let trimmed = newDecisionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.14)) {
            minutes.decisions.append(trimmed)
        }
        newDecisionDraft = ""
    }

    // MARK: - 4. Action Items (Spacious Cards + Enter-to-Add)

    private var actionItemsSection: some View {
        editorSection(
            L("待办事项", "Action Items"),
            trailingCount: minutes.actionItems.count
        ) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(minutes.actionItems.enumerated()), id: \.element.id) { aIdx, item in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 8) {
                            Button {
                                if aIdx < minutes.actionItems.count {
                                    minutes.actionItems[aIdx].isCompleted.toggle()
                                }
                            } label: {
                                Image(systemName: item.isCompleted ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 14.5))
                                    .foregroundStyle(item.isCompleted ? AppTheme.brandPrimary : AppTheme.textMuted)
                                    .padding(.top, 7)
                            }
                            .buttonStyle(.plain)

                            EditorialMultilineField(
                                placeholder: L("待办任务描述...", "Action item description..."),
                                text: Binding(
                                    get: { aIdx < minutes.actionItems.count ? minutes.actionItems[aIdx].task : "" },
                                    set: { val in
                                        if aIdx < minutes.actionItems.count {
                                            minutes.actionItems[aIdx].task = val
                                        }
                                    }
                                ),
                                minLines: 1,
                                maxLines: 4,
                                fontSize: 13
                            )

                            HoverDestructiveIconButton(
                                icon: "trash",
                                help: L("删除此待办", "Delete action item")
                            ) {
                                withAnimation(.easeInOut(duration: 0.14)) {
                                    minutes.actionItems.removeAll { $0.id == item.id }
                                }
                            }
                            .padding(.top, 5)
                        }

                        HStack(spacing: 8) {
                            Spacer().frame(width: 16)
                            EditorialInlineField(
                                placeholder: L("负责人", "Owner"),
                                icon: "person",
                                text: Binding(
                                    get: { aIdx < minutes.actionItems.count ? minutes.actionItems[aIdx].owner : "" },
                                    set: { val in
                                        if aIdx < minutes.actionItems.count {
                                            minutes.actionItems[aIdx].owner = val
                                        }
                                    }
                                )
                            )
                            .frame(maxWidth: 160)

                            EditorialInlineField(
                                placeholder: L("截止时间", "Due date"),
                                icon: "calendar",
                                text: Binding(
                                    get: { aIdx < minutes.actionItems.count ? minutes.actionItems[aIdx].dueDate : "" },
                                    set: { val in
                                        if aIdx < minutes.actionItems.count {
                                            minutes.actionItems[aIdx].dueDate = val
                                        }
                                    }
                                )
                            )
                            .frame(maxWidth: 160)

                            Spacer()
                        }
                    }
                    .padding(11)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(AppTheme.softCardBg)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(AppTheme.subtleBorder, lineWidth: 1)
                    )
                }

                // Quick-Add Action Item Card
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        EditorialInlineField(
                            placeholder: L("新增待办事项（按回车快速添加）...", "New action item (press Enter to add)..."),
                            icon: "plus.circle",
                            text: $newActionTask,
                            onSubmit: appendActionItem
                        )

                        CleanPrimaryButton(
                            title: L("添加", "Add"),
                            icon: "plus",
                            disabled: newActionTask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                            action: appendActionItem
                        )
                    }

                    HStack(spacing: 8) {
                        EditorialInlineField(
                            placeholder: L("负责人（可选）", "Owner (optional)"),
                            icon: "person",
                            text: $newActionOwner,
                            onSubmit: appendActionItem
                        )
                        .frame(maxWidth: 168)

                        EditorialInlineField(
                            placeholder: L("截止时间（可选）", "Due (optional)"),
                            icon: "calendar",
                            text: $newActionDue,
                            onSubmit: appendActionItem
                        )
                        .frame(maxWidth: 168)

                        Spacer()
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.softCardBg.opacity(0.65))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(AppTheme.subtleBorder, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
            }
        }
    }

    private func appendActionItem() {
        let task = newActionTask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty else { return }
        let owner = newActionOwner.trimmingCharacters(in: .whitespacesAndNewlines)
        let due = newActionDue.trimmingCharacters(in: .whitespacesAndNewlines)
        withAnimation(.easeInOut(duration: 0.14)) {
            minutes.actionItems.append(ActionItem(
                task: task,
                owner: owner.isEmpty ? L("待定", "TBD") : owner,
                dueDate: due
            ))
        }
        newActionTask = ""
        newActionOwner = ""
        newActionDue = ""
    }

    // MARK: - 5. Open Questions (Full CRUD + Enter-to-Add)

    private var openQuestionsSection: some View {
        editorSection(
            L("待确认问题", "Open Questions"),
            trailingCount: minutes.openQuestions.count
        ) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(minutes.openQuestions.enumerated()), id: \.offset) { qIdx, _ in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 11.5))
                            .foregroundStyle(AppTheme.warningAmber)
                            .padding(.top, 9)

                        EditorialMultilineField(
                            placeholder: L("待确认问题...", "Open question..."),
                            text: Binding(
                                get: { qIdx < minutes.openQuestions.count ? minutes.openQuestions[qIdx] : "" },
                                set: { val in
                                    if qIdx < minutes.openQuestions.count {
                                        minutes.openQuestions[qIdx] = val
                                    }
                                }
                            ),
                            minLines: 1,
                            maxLines: 5,
                            fontSize: 13
                        )

                        HoverDestructiveIconButton(
                            icon: "xmark",
                            help: L("删除此问题", "Remove question")
                        ) {
                            withAnimation(.easeInOut(duration: 0.14)) {
                                if qIdx < minutes.openQuestions.count {
                                    minutes.openQuestions.remove(at: qIdx)
                                }
                            }
                        }
                        .padding(.top, 5)
                    }
                }

                HStack(spacing: 8) {
                    EditorialInlineField(
                        placeholder: L("输入待确认问题后按回车添加...", "Add an open question and press Enter..."),
                        icon: "plus.circle",
                        text: $newQuestionDraft,
                        onSubmit: appendQuestion
                    )

                    CleanPrimaryButton(
                        title: L("添加", "Add"),
                        disabled: newQuestionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        action: appendQuestion
                    )
                }
            }
        }
    }

    private func appendQuestion() {
        let trimmed = newQuestionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.14)) {
            minutes.openQuestions.append(trimmed)
        }
        newQuestionDraft = ""
    }

    // MARK: - Section Chrome

    private func editorSection<Content: View>(
        _ title: String,
        trailingCount: Int? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                if let count = trailingCount, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppTheme.textMuted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(AppTheme.neutralPill))
                }
            }
            content()
        }
    }
}

// MARK: - Reusable Editorial Input Controls

struct EditorialMultilineField: View {
    let placeholder: String
    @Binding var text: String
    var minLines: Int = 1
    var maxLines: Int = 8
    var fontSize: CGFloat = 13
    var fontWeight: Font.Weight = .regular

    @FocusState private var isFocused: Bool
    @State private var isHovering: Bool = false

    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: fontSize, weight: fontWeight))
            .foregroundStyle(AppTheme.textPrimary)
            .lineSpacing(4)
            .lineLimit(minLines...maxLines)
            .focused($isFocused)
            .padding(.horizontal, 11)
            .padding(.vertical, 7.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppTheme.inputBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isFocused
                            ? AppTheme.brandPrimary
                            : (isHovering ? AppTheme.inputHoverBorder : AppTheme.inputBorder),
                        lineWidth: isFocused ? 1.5 : 1
                    )
            )
            .shadow(
                color: isFocused ? AppTheme.brandPrimary.opacity(0.16) : Color.black.opacity(0.015),
                radius: isFocused ? 4 : 1,
                y: isFocused ? 0 : 0.5
            )
            .animation(.easeOut(duration: 0.14), value: isFocused)
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .onHover { isHovering = $0 }
    }
}

struct EditorialInlineField: View {
    let placeholder: String
    var icon: String? = nil
    @Binding var text: String
    var onSubmit: (() -> Void)? = nil

    @FocusState private var isFocused: Bool
    @State private var isHovering: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(isFocused ? AppTheme.brandPrimary : AppTheme.textMuted)
            }
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(AppTheme.textPrimary)
                .focused($isFocused)
                .onSubmit { onSubmit?() }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6.5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.inputBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isFocused
                        ? AppTheme.brandPrimary
                        : (isHovering ? AppTheme.inputHoverBorder : AppTheme.inputBorder),
                    lineWidth: isFocused ? 1.5 : 1
                )
        )
        .shadow(
            color: isFocused ? AppTheme.brandPrimary.opacity(0.15) : Color.black.opacity(0.015),
            radius: isFocused ? 3.5 : 1,
            y: isFocused ? 0 : 0.5
        )
        .animation(.easeOut(duration: 0.14), value: isFocused)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .onHover { isHovering = $0 }
    }
}

private struct SubtleAddButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    @State private var isHovering: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(isHovering ? AppTheme.brandPrimary : AppTheme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isHovering ? AppTheme.brandSoftFill.opacity(0.6) : AppTheme.softCardBg.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        isHovering ? AppTheme.brandPrimary.opacity(0.45) : AppTheme.subtleBorder,
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct HoverDestructiveIconButton: View {
    let icon: String
    let help: String
    let action: () -> Void
    @State private var isHovering: Bool = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isHovering ? AppTheme.recordingRed : AppTheme.textMuted)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovering ? AppTheme.recordingRed.opacity(0.10) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { isHovering = $0 }
    }
}
