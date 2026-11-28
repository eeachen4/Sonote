import SwiftUI
import AppKit
import SonoteCore

// MARK: - Ask AI Conversation Section & Composer

extension CompletedMeetingDocumentView {

    var minimalAskAIView: some View {
        VStack(alignment: .leading, spacing: 14) {
            if meeting.chatHistory.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("基于本次会议内容随时提问", "Ask anything about this meeting"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(L("可在下方直接输入问题，或点击快捷指令一键生成周报、邮件、待办与风险清单。", "Type a question below or use quick prompts to draft emails, weekly reports, action items, or risks."))
                        .font(.system(size: 12.5))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding(.vertical, 12)
            }

            ForEach(meeting.chatHistory) { msg in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(msg.role == .user ? L("我", "You") : L("AI 总结", "Sonote AI"))
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
                                showToast(L("已复制回答", "Copied"))
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 10.5))
                                    Text(L("复制", "Copy"))
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
                            Text(L("思考中...", "Thinking..."))
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
}

// MARK: - Doubao-Style Elevated AI Composer Input Card (With Stop Generation)

struct DoubaoAIComposerView: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let isSending: Bool
    var customPrompts: [String] = []
    var onAddCustomPrompt: ((String) -> Void)? = nil
    var onRemoveCustomPrompt: ((String) -> Void)? = nil
    let onQuickPrompt: (String) -> Void
    let onSend: () -> Void
    let onStop: () -> Void
    @ObservedObject private var theme = ThemeManager.shared

    @State private var showAddPromptPopover: Bool = false
    @State private var newPromptDraft: String = ""

    private var quickTags: [(label: String, prompt: String)] {
        [
            (L("整理为邮件", "Draft Email"), L("请基于本次会议记录，整理为一封结构清晰的会后跟进邮件。", "Draft a clear, structured follow-up email based on this meeting.")),
            (L("提炼周报", "Weekly Report"), L("请基于本次会议记录，提炼为简明周报要点。", "Summarize this meeting into concise weekly report bullets.")),
            (L("列出待办", "Action Items"), L("请基于本次会议记录，列出所有待办事项、负责人和截止时间。", "List all action items with owners and due dates from this meeting.")),
            (L("风险与分歧", "Risks & Gaps"), L("请基于本次会议记录，梳理潜在风险、未决分歧和需要跟进的问题。", "Identify open risks, disagreements, and follow-up questions from this meeting."))
        ]
    }

    private var canSend: Bool {
        !isSending && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(
                L("向 AI 追问会议细节，或直接输入整理指令...", "Ask AI about meeting details or enter an instruction..."),
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
                        ForEach(quickTags, id: \.label) { item in
                            ComposerQuickChip(label: item.label, disabled: isSending) {
                                onQuickPrompt(item.prompt)
                            }
                        }

                        ForEach(customPrompts, id: \.self) { custom in
                            ComposerQuickChip(
                                label: String(custom.prefix(16)) + (custom.count > 16 ? "…" : ""),
                                disabled: isSending,
                                isCustom: true,
                                onDelete: onRemoveCustomPrompt != nil ? { onRemoveCustomPrompt?(custom) } : nil
                            ) {
                                onQuickPrompt(custom)
                            }
                            .help(custom)
                        }

                        if onAddCustomPrompt != nil {
                            Button {
                                newPromptDraft = ""
                                showAddPromptPopover = true
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 9.5, weight: .semibold))
                                    Text(L("自定义指令", "Custom"))
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundStyle(AppTheme.brandPrimary)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(AppTheme.brandSoftFill.opacity(0.65)))
                                .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .help(L("保存常用追问指令以便一键复用", "Save reusable custom AI quick prompts"))
                            .popover(isPresented: $showAddPromptPopover, arrowEdge: .top) {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(L("新增自定义快捷指令", "New Custom Quick Prompt"))
                                        .font(.system(size: 12.5, weight: .semibold))
                                        .foregroundStyle(AppTheme.textPrimary)
                                    Text(L("例如：「写成 3 句话飞书群同步消息」或「转成英文客户邮件」", "e.g. \"Write a 3-line Slack update\" or \"Draft client follow-up\""))
                                        .font(.system(size: 11))
                                        .foregroundStyle(AppTheme.textMuted)
                                    CleanInputBox(
                                        placeholder: L("输入指令内容...", "Enter prompt instruction..."),
                                        text: $newPromptDraft
                                    ) {
                                        submitCustomPrompt()
                                    }
                                    HStack {
                                        Spacer()
                                        CleanPrimaryButton(
                                            title: L("保存指令", "Save Prompt"),
                                            icon: "plus",
                                            disabled: newPromptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                        ) {
                                            submitCustomPrompt()
                                        }
                                    }
                                }
                                .padding(13)
                                .frame(width: 280)
                                .background(AppTheme.elevatedSurface)
                                .preferredColorScheme(theme.preferredColorScheme)
                            }
                        }
                    }
                }

                Spacer(minLength: 8)

                if canSend {
                    Text(L("⏎ 发送", "⏎ Send"))
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
                    .help(L("停止生成", "Stop Generation"))
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
                    .help(L("发送 (Return)", "Send (Return)"))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.elevatedSurface)
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

    private func submitCustomPrompt() {
        let trimmed = newPromptDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onAddCustomPrompt?(trimmed)
        newPromptDraft = ""
        showAddPromptPopover = false
    }
}

struct ComposerQuickChip: View {
    let label: String
    let disabled: Bool
    var isCustom: Bool = false
    var onDelete: (() -> Void)? = nil
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            Button(action: action) {
                HStack(spacing: 4) {
                    Image(systemName: isCustom ? "bookmark.fill" : "sparkles")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(isHovering || isCustom ? AppTheme.brandPrimary : AppTheme.textMuted)
                    Text(label)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(isHovering ? AppTheme.brandPrimary : AppTheme.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(disabled)

            if let onDelete, isHovering {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(AppTheme.textMuted)
                }
                .buttonStyle(.plain)
                .help(L("移除此自定义指令", "Remove custom prompt"))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(isHovering ? AppTheme.brandSoftFill : (isCustom ? AppTheme.brandSoftFill.opacity(0.45) : AppTheme.softCardBg))
        )
        .overlay(
            Capsule()
                .strokeBorder(isHovering ? AppTheme.mindMapLine : AppTheme.subtleBorder.opacity(0.7), lineWidth: 1)
        )
        .onHover { isHovering = $0 }
    }
}
