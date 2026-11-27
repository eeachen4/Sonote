import SwiftUI
import AppKit
import SonoteCore

/// Native SwiftUI GitHub-Flavored Markdown renderer styled for Doubao Work's clean light canvas.
/// Renders headings, inline bold/italic/code/links, bullet/task/ordered lists, GFM tables, blockquotes, and code fences.
struct MarkdownContentView: View {
    let markdown: String
    var fontSize: CGFloat = 13.5
    @ObservedObject private var theme = ThemeManager.shared

    private var effectiveFontSize: CGFloat {
        (fontSize * CGFloat(theme.fontScale.multiplier)).rounded(.toNearestOrAwayFromZero)
    }

    var body: some View {
        let blocks = MarkdownParser.parse(markdown)
        VStack(alignment: .leading, spacing: 11) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                renderBlock(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func renderBlock(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            inlineMarkdownText(text)
                .font(.system(size: headingSize(level), weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .padding(.top, level <= 2 ? 6 : 4)
                .textSelection(.enabled)

        case .paragraph(let text):
            inlineMarkdownText(text)
                .font(.system(size: effectiveFontSize))
                .foregroundStyle(AppTheme.textPrimary.opacity(0.92))
                .lineSpacing(4.5)
                .textSelection(.enabled)

        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        if let checked = item.isChecked {
                            Image(systemName: checked ? "checkmark.square.fill" : "square")
                                .font(.system(size: 13))
                                .foregroundStyle(checked ? AppTheme.brandPrimary : AppTheme.textMuted)
                                .padding(.top, 2)
                        } else {
                            Circle()
                                .fill(item.indentLevel == 0 ? AppTheme.brandPrimary.opacity(0.65) : AppTheme.textMuted)
                                .frame(width: 4.5, height: 4.5)
                                .padding(.top, 7)
                        }

                        inlineMarkdownText(item.text)
                            .font(.system(size: effectiveFontSize))
                            .foregroundStyle(AppTheme.textPrimary.opacity(0.92))
                            .lineSpacing(4)
                            .textSelection(.enabled)
                    }
                    .padding(.leading, CGFloat(item.indentLevel * 16))
                }
            }

        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 7) {
                        Text("\(item.number).")
                            .font(.system(size: effectiveFontSize - 0.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(minWidth: 18, alignment: .trailing)
                        inlineMarkdownText(item.text)
                            .font(.system(size: effectiveFontSize))
                            .foregroundStyle(AppTheme.textPrimary.opacity(0.92))
                            .lineSpacing(4)
                            .textSelection(.enabled)
                    }
                    .padding(.leading, CGFloat(item.indentLevel * 16))
                }
            }

        case .table(let headers, let rows):
            MarkdownTableView(headers: headers, rows: rows, fontSize: effectiveFontSize - 0.5)

        case .blockquote(let text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(AppTheme.brandPrimary.opacity(0.45))
                    .frame(width: 3)
                inlineMarkdownText(text)
                    .font(.system(size: effectiveFontSize - 0.5))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineSpacing(4)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 4)

        case .codeBlock(let language, let code):
            MarkdownCodeBlockView(language: language, code: code)

        case .divider:
            Divider()
                .overlay(AppTheme.divider)
                .padding(.vertical, 4)
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return effectiveFontSize + 4.5
        case 2: return effectiveFontSize + 2.5
        case 3: return effectiveFontSize + 1.0
        default: return effectiveFontSize
        }
    }
}

/// Renders inline Markdown (`**bold**`, `*italic*`, `` `code` ``, `~~strike~~`, `[link](url)`, `<br>`)
/// using our CJK-friendly native parser so patterns like `**云端编译：**正文` always render cleanly.
@MainActor
func inlineMarkdownText(_ raw: String) -> Text {
    let spans = MarkdownParser.parseInline(raw)
    guard !spans.isEmpty else { return Text("") }

    var combined = AttributedString()
    for span in spans {
        var part = AttributedString(span.text)
        var intent: InlinePresentationIntent = []
        if span.style.contains(.bold) {
            intent.insert(.stronglyEmphasized)
        }
        if span.style.contains(.italic) {
            intent.insert(.emphasized)
        }
        if span.style.contains(.code) {
            intent.insert(.code)
            part.backgroundColor = AppTheme.inlineCodeBg
        }
        if !intent.isEmpty {
            part.inlinePresentationIntent = intent
        }
        if span.style.contains(.strikethrough) {
            part.strikethroughStyle = .single
        }
        if let urlStr = span.linkURL, let url = URL(string: urlStr) {
            part.link = url
            part.foregroundColor = AppTheme.brandPrimary
        }
        combined.append(part)
    }
    return Text(combined)
}

// MARK: - Clean GFM Table View

private struct MarkdownTableView: View {
    let headers: [String]
    let rows: [[String]]
    let fontSize: CGFloat

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                // Header Row
                GridRow {
                    ForEach(Array(headers.enumerated()), id: \.offset) { colIdx, header in
                        inlineMarkdownText(header)
                            .font(.system(size: fontSize, weight: .semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .frame(minWidth: 88, maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.mindMapNodeFill.opacity(0.75))
                            .overlay(alignment: .trailing) {
                                if colIdx < headers.count - 1 {
                                    Rectangle().fill(AppTheme.divider).frame(width: 1)
                                }
                            }
                            .textSelection(.enabled)
                    }
                }

                // Body Rows
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                    Divider().overlay(AppTheme.divider)
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { colIdx, cell in
                            inlineMarkdownText(cell)
                                .font(.system(size: fontSize))
                                .foregroundStyle(AppTheme.textPrimary.opacity(0.9))
                                .lineSpacing(3)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .frame(minWidth: 88, maxWidth: .infinity, alignment: .leading)
                                .background(rowIdx % 2 == 1 ? AppTheme.softCardBg.opacity(0.6) : AppTheme.elevatedSurface)
                                .overlay(alignment: .trailing) {
                                    if colIdx < row.count - 1 {
                                        Rectangle().fill(AppTheme.divider).frame(width: 1)
                                    }
                                }
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(AppTheme.subtleBorder, lineWidth: 1)
            )
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Clean Code Fence View

private struct MarkdownCodeBlockView: View {
    let language: String?
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language?.isEmpty == false ? language! : "code")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
                } label: {
                    Text(copied ? "已复制" : "复制")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(AppTheme.neutralPill.opacity(0.7))

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(AppTheme.textPrimary)
                    .padding(12)
                    .textSelection(.enabled)
            }
        }
        .background(AppTheme.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(AppTheme.subtleBorder, lineWidth: 1)
        )
    }
}
