import SwiftUI
import AppKit
import SonoteCore

// MARK: - Clean Action Card Component

struct HomeActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let isPrimary: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isPrimary ? AppTheme.brandPrimary : AppTheme.neutralPill)
                            .frame(width: 36, height: 36)
                        Image(systemName: icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(isPrimary ? Color.white : AppTheme.textPrimary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isPrimary ? AppTheme.brandPrimary.opacity(isHovering ? 1 : 0.6) : AppTheme.textMuted)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isPrimary ? AppTheme.mindMapNodeFill : AppTheme.elevatedSurface.opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isHovering
                            ? (isPrimary ? AppTheme.brandPrimary.opacity(0.35) : AppTheme.textMuted.opacity(0.45))
                            : (isPrimary ? AppTheme.mindMapLine : AppTheme.subtleBorder),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(isHovering ? 0.05 : 0.015), radius: isHovering ? 10 : 4, y: 2)
            .animation(.easeOut(duration: 0.15), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Clean Editorial Meeting Row

struct HomeMeetingRow: View {
    let meeting: MeetingSession
    let isRecording: Bool
    let searchQuery: String
    let onSelect: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void

    @ObservedObject private var theme = ThemeManager.shared
    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isRecording ? AppTheme.brandSoftFill : AppTheme.softCardBg)
                        .frame(width: 34, height: 34)
                    Image(systemName: isRecording ? "waveform" : "doc.text")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isRecording ? AppTheme.brandPrimary : AppTheme.textSecondary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(meeting.title)
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(1)

                        if isRecording {
                            Text(L("录音中", "Live"))
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(AppTheme.brandPrimary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(Capsule().fill(AppTheme.brandSoftFill))
                        }

                        ForEach(meeting.tags.prefix(3), id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.system(size: 10))
                                .foregroundStyle(AppTheme.textSecondary)
                                .padding(.horizontal, 5.5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(AppTheme.neutralPill))
                        }
                    }

                    Text(previewText)
                        .font(.system(size: 12))
                        .foregroundStyle(isShowingSearchSnippet ? AppTheme.brandPrimary.opacity(0.9) : AppTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                if isHovering {
                    HStack(spacing: 6) {
                        Button(action: onCopy) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.textSecondary)
                                .frame(width: 26, height: 26)
                                .background(Circle().fill(AppTheme.neutralPill))
                        }
                        .buttonStyle(.plain)
                        .help(L("复制 Markdown 纪要", "Copy Markdown Minutes"))

                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.textSecondary)
                                .frame(width: 26, height: 26)
                                .background(Circle().fill(AppTheme.neutralPill))
                        }
                        .buttonStyle(.plain)
                        .help(L("删除记录", "Delete Meeting"))
                    }
                } else {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(shortTime(meeting.startedAt))
                            .font(.system(size: 11.5))
                            .foregroundStyle(AppTheme.textSecondary)
                        HStack(spacing: 5) {
                            Text(meeting.duration > 0 ? (theme.isEnglish ? meeting.formattedDuration : meeting.chineseDurationText) : meeting.sourceAppName)
                            if !meeting.tokenUsage.isEmpty {
                                Text("· \(meeting.tokenUsage.formattedCompact)t")
                            }
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.textMuted)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isHovering ? AppTheme.elevatedSurface : AppTheme.elevatedSurface.opacity(0.62))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isHovering ? AppTheme.subtleBorder : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button(L("复制 Markdown 纪要", "Copy Markdown Minutes"), action: onCopy)
            Divider()
            Button(L("删除记录", "Delete Meeting"), role: .destructive, action: onDelete)
        }
    }

    private var matchedSnippet: String? {
        meeting.searchSnippet(for: searchQuery)
    }

    private var isShowingSearchSnippet: Bool {
        matchedSnippet != nil
    }

    private var previewText: String {
        if let snippet = matchedSnippet {
            return snippet
        }
        if !meeting.minutes.overview.isEmpty {
            return meeting.minutes.overview
        }
        if let firstSeg = meeting.segments.first {
            return firstSeg.text
        }
        return L("未识别到文字内容", "No transcript content")
    }

    private func shortTime(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "MM-dd HH:mm"
        return df.string(from: date)
    }
}

// MARK: - Paste Transcript -> Smart Minutes Sheet

struct PasteTranscriptSheet: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var theme = ThemeManager.shared
    @Binding var isPresented: Bool

    @State private var title: String = ""
    @State private var rawText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L("粘贴文本生成智能纪要", "Generate Minutes from Text"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }

            TextField(L("会议主题（留空由 AI 自动命名）", "Meeting title (optional — AI can name it)"), text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .foregroundStyle(AppTheme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(AppTheme.inputBackground))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(AppTheme.inputBorder, lineWidth: 1))

            TextEditor(text: $rawText)
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 210)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(AppTheme.inputBackground))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(AppTheme.inputBorder, lineWidth: 1))

            HStack {
                Text(L("支持直接粘贴逐字稿、聊天讨论或零散笔记", "Paste transcripts, chat threads, or rough notes"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
                Button(L("取消", "Cancel")) { isPresented = false }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5))
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal, 10)

                Button {
                    let t = title
                    let body = rawText
                    isPresented = false
                    Task { await appState.createMeetingFromPastedText(title: t, rawText: body) }
                } label: {
                    Text(L("生成智能纪要", "Generate Minutes"))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(AppTheme.brandPrimary))
                }
                .buttonStyle(.plain)
                .disabled(rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 500)
        .background(AppTheme.canvasWhite)
        .tint(AppTheme.brandPrimary)
        .preferredColorScheme(theme.preferredColorScheme)
    }
}

// MARK: - Main NSWindow Accessor

/// Captures the hosting `NSWindow` for SwiftUI's primary `Window("Sonote", id: "main")`
/// so floating panels, global hotkeys, and menu bar actions always focus the exact main window
/// rather than mistakenly matching Settings or MenuBarExtra windows.
struct MainWindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = WindowCaptureNSView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let captureView = nsView as? WindowCaptureNSView {
            captureView.onWindow = onWindow
            if let window = captureView.window {
                onWindow(window)
            }
        }
    }

    private final class WindowCaptureNSView: NSView {
        var onWindow: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                onWindow?(window)
            }
        }
    }
}
