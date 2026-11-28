import SwiftUI
import SonoteCore

// MARK: - CompletedMeetingDocumentView Chrome, Metadata, Streaming Card & Manual Notes

extension CompletedMeetingDocumentView {

    // MARK: - Top Safe-Area Chrome & Sticky Editing Bar

    @ViewBuilder
    var topChromeBar: some View {
        if isEditingSummary {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    // Leave full clearance for macOS window traffic lights
                    Spacer().frame(width: 72)

                    HStack(spacing: 6) {
                        Image(systemName: "pencil.line")
                            .font(.system(size: 11, weight: .semibold))
                        Text(L("正在编辑纪要", "Editing Minutes"))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(AppTheme.brandPrimary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(AppTheme.brandSoftFill))

                    Text(L("⌘⏎ 保存 · Esc 取消", "⌘⏎ Save · Esc Cancel"))
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.textMuted)
                        .lineLimit(1)

                    Spacer()

                    Button {
                        cancelEditing()
                    } label: {
                        Text(L("取消", "Cancel"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5.5)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(AppTheme.elevatedSurface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(AppTheme.subtleBorder, lineWidth: 1)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)

                    CleanPrimaryButton(
                        title: L("保存完成", "Save"),
                        icon: "checkmark"
                    ) {
                        commitEditing()
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                }
                .padding(.trailing, 20)
                .frame(height: 44)
                .background(AppTheme.elevatedSurface.opacity(0.92))

                Divider().overlay(AppTheme.divider)
            }
        } else {
            HStack {
                Spacer().frame(width: 72)
                Spacer()
                if let toast = copiedToast {
                    Text(toast)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(AppTheme.brandPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3.5)
                        .background(Capsule().fill(AppTheme.brandSoftFill))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.trailing, 20)
            .frame(height: 36)
        }
    }

    // MARK: - Header Metadata & Tags Row

    var metadataHeaderRow: some View {
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
                        CleanInputBox(
                            placeholder: L("例如：产品周会、技术评审", "e.g. Weekly Sync, Design"),
                            text: $newTagDraft
                        ) {
                            let trimmed = newTagDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            appState.addTag(trimmed, to: meeting.id)
                            showAddTagPopover = false
                        }
                        CleanPrimaryButton(
                            title: L("添加", "Add"),
                            disabled: newTagDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ) {
                            appState.addTag(newTagDraft, to: meeting.id)
                            showAddTagPopover = false
                        }
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

    // MARK: - Bottom Bar & Export Menu

    var bottomActionBar: some View {
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
                    Button(L("导出为 .pdf 文件（仅纪要）...", "Export as .pdf (Minutes)...")) {
                        appState.exportPDFWithSavePanel(for: meeting, includeTranscript: false)
                    }
                    if !meeting.segments.isEmpty {
                        Button(L("导出为 .pdf 文件（含逐字稿）...", "Export as .pdf (With Transcript)...")) {
                            appState.exportPDFWithSavePanel(for: meeting, includeTranscript: true)
                        }
                    }
                    Button(L("导出为 .md 文件...", "Export as .md...")) {
                        appState.exportMarkdownWithSavePanel(for: meeting)
                    }
                    if !meeting.segments.isEmpty {
                        Divider()
                        Button(L("导出字幕文件 (.srt)...", "Export Subtitles (.srt)...")) {
                            appState.exportSRTWithSavePanel(for: meeting)
                        }
                        Button(L("导出字幕文件 (.vtt)...", "Export Subtitles (.vtt)...")) {
                            appState.exportVTTWithSavePanel(for: meeting)
                        }
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

    var summarizingProgressCard: some View {
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

    var manualNotesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isEditingSummary {
                // Collapsible secondary section during minutes editing to avoid clutter & conflicting hints
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        showQuickNotesInEditor.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showQuickNotesInEditor ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AppTheme.textMuted)
                            .frame(width: 12)
                        Image(systemName: "note.text")
                            .font(.system(size: 11.5))
                            .foregroundStyle(AppTheme.brandPrimary)
                        Text(L("会中随手记", "Quick Notes"))
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                        Spacer()
                        Text(L("随本次编辑一起保存", "Saved alongside minutes"))
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.textMuted)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showQuickNotesInEditor {
                    EditorialMultilineField(
                        placeholder: L("补充会议备注、上下文链接或会中灵感...", "Add personal notes, links, or extra context..."),
                        text: Binding(
                            get: { editDraft?.manualNotes ?? meeting.manualNotes },
                            set: { editDraft?.manualNotes = $0 }
                        ),
                        minLines: 3,
                        maxLines: 10,
                        fontSize: 13
                    )
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "note.text")
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppTheme.brandPrimary)
                    Text(L("会中随手记", "Quick Notes"))
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Spacer()
                }

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
        .padding(.top, isEditingSummary ? 4 : 0)
    }
}
