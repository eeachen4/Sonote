import SwiftUI
import AppKit
import SonoteCore

// MARK: - Non-Activating Floating NSPanel Base

final class FloatingHUDPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Ensures clicks on buttons inside a non-activating floating HUD panel fire on the very first click
/// even while another app (Zoom / Feishu / Chrome) is focused.
final class AcceptsFirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Meeting Detection Prompt HUD Controller (Compact, Fixed-Size Doubao Card)

@MainActor
final class FloatingPromptPanelController {
    private var panel: FloatingHUDPanel?

    func showMeetingDetected(_ meeting: DetectedMeetingApp, appState: AppState) {
        let width: CGFloat = 344
        let height: CGFloat = 122
        let view = MeetingPromptHUDView(
            mode: .meetingStarted(meeting),
            appState: appState,
            cardWidth: width,
            cardHeight: height
        )
        presentPanel(rootView: view, width: width, height: height)
    }

    func showMeetingEnded(_ meeting: DetectedMeetingApp, appState: AppState) {
        let width: CGFloat = 344
        let height: CGFloat = 116
        let view = MeetingPromptHUDView(
            mode: .meetingEnded(meeting),
            appState: appState,
            cardWidth: width,
            cardHeight: height
        )
        presentPanel(rootView: view, width: width, height: height)
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func presentPanel<V: View>(rootView: V, width: CGFloat, height: CGFloat) {
        hide()

        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let originX = screenFrame.maxX - width - 18
        let originY = screenFrame.maxY - height - 16
        let frame = NSRect(x: originX, y: originY, width: width, height: height)

        let panel = FloatingHUDPanel(contentRect: frame)
        let hosting = AcceptsFirstMouseHostingView(rootView: rootView)
        // Lock sizing so SwiftUI never unexpectedly stretches the panel height
        hosting.sizingOptions = []
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        panel.contentView = hosting
        panel.setFrame(frame, display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.20
            panel.animator().alphaValue = 1
        }
        self.panel = panel
    }
}

struct MeetingPromptHUDView: View {
    enum Mode {
        case meetingStarted(DetectedMeetingApp)
        case meetingEnded(DetectedMeetingApp)
    }

    let mode: Mode
    @ObservedObject var appState: AppState
    @ObservedObject private var theme = ThemeManager.shared
    let cardWidth: CGFloat
    let cardHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch mode {
            case .meetingStarted(let detected):
                HStack(alignment: .center, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(AppTheme.brandSoftFill)
                            .frame(width: 34, height: 34)
                        Image(systemName: "waveform")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppTheme.brandPrimary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("检测到「\(detected.appName)」", "Detected \"\(detected.appName)\""))
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(1)
                        Text(L("是否开启智能纪要，实时记录会议内容？", "Start live AI meeting minutes now?"))
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    Button {
                        appState.dismissDetectedMeetingPrompt()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppTheme.textMuted)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 8) {
                    Button {
                        appState.acceptDetectedMeetingPrompt()
                    } label: {
                        Text(L("开启智能纪要", "Start Minutes"))
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(AppTheme.brandPrimary))
                    }
                    .buttonStyle(.plain)

                    Button {
                        appState.snoozeDetectedMeetingPrompt(minutes: 5)
                    } label: {
                        Text(L("稍后提醒", "Snooze"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.textPrimary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(AppTheme.neutralPill))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        appState.ignoreDetectedAppPermanently()
                    } label: {
                        Text(L("不再提醒", "Mute App"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(AppTheme.textMuted)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(L("将此应用加入自动检测忽略列表", "Add this app to auto-detection ignore list"))

                    Button {
                        appState.dismissDetectedMeetingPrompt()
                    } label: {
                        Text(L("忽略", "Dismiss"))
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

            case .meetingEnded(let ended):
                HStack(alignment: .center, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(AppTheme.neutralPill)
                            .frame(width: 34, height: 34)
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(AppTheme.successGreen)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("「\(ended.appName)」可能已结束", "\"\(ended.appName)\" May Have Ended"))
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(1)
                        Text(L("是否停止采集并生成完整会议总结？", "Stop recording and generate final summary?"))
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }

                HStack(spacing: 8) {
                    Button {
                        Task { await appState.stopRecordingAndFinalize(generateFinalSummary: true) }
                    } label: {
                        Text(L("结束并总结", "Stop & Summarize"))
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(AppTheme.brandPrimary))
                    }
                    .buttonStyle(.plain)

                    Button {
                        appState.dismissEndedMeetingPrompt()
                    } label: {
                        Text(L("继续记录", "Keep Recording"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.textPrimary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(AppTheme.neutralPill))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: cardWidth, height: cardHeight, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AppTheme.subtleBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 16, x: 0, y: 6)
        .tint(AppTheme.brandPrimary)
        .preferredColorScheme(ThemeManager.shared.preferredColorScheme)
    }
}

// MARK: - Top-Left Mini Recording Window (录制中左上角悬浮小窗)

@MainActor
final class LiveCapsulePanelController {
    private var panel: FloatingHUDPanel?

    func setVisible(_ visible: Bool, appState: AppState) {
        if visible {
            show(appState: appState)
        } else {
            hide()
        }
    }

    private func show(appState: AppState) {
        if let existing = panel {
            existing.orderFrontRegardless()
            return
        }

        let width: CGFloat = 316
        let height: CGFloat = 108
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        // Anchor cleanly at the top-left corner of the screen
        let frame = NSRect(
            x: screenFrame.minX + 18,
            y: screenFrame.maxY - height - 16,
            width: width,
            height: height
        )

        let panel = FloatingHUDPanel(contentRect: frame)
        let hosting = AcceptsFirstMouseHostingView(rootView: LiveCapsuleView(appState: appState, width: width, height: height))
        hosting.sizingOptions = []
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        panel.contentView = hosting
        panel.setFrame(frame, display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 1
        }
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

struct LiveCapsuleView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var theme = ThemeManager.shared
    let width: CGFloat
    let height: CGFloat

    @State private var isHoveringExpand = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            // Row 1: Recording dot + timer + mini dotted waveform + expand button
            HStack(spacing: 8) {
                RecordingPulseDot(isActive: appState.isRecording, isPaused: appState.isPaused)

                Text(appState.activeRecordingMeeting?.formattedDuration ?? "00:00")
                    .font(.system(size: 13.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppTheme.textPrimary)

                MiniDottedWaveformView(
                    level: max(appState.systemAudioLevel, appState.micAudioLevel),
                    isActive: appState.systemAudioActive || appState.micAudioActive,
                    isPaused: appState.isPaused
                )

                Spacer(minLength: 4)

                Button {
                    appState.expandFromMiniWindowToMain()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(isHoveringExpand ? AppTheme.brandPrimary : AppTheme.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(isHoveringExpand ? AppTheme.brandSoftFill : AppTheme.softCardBg))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .onHover { isHoveringExpand = $0 }
                .help(L("展开为双栏实时记录大窗", "Expand to Full Workspace"))
            }

            // Row 2: Live 1-line transcript or AI summary snippet (double-click also expands)
            Text(liveSnippet)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    appState.expandFromMiniWindowToMain()
                }

            // Row 3: Doubao-style Pause (soft blue) + Stop (soft gray) pills
            HStack(spacing: 8) {
                Button {
                    appState.togglePauseRecording()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: appState.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text(appState.isPaused ? L("继续", "Resume") : L("暂停", "Pause"))
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .foregroundStyle(AppTheme.brandPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(Capsule().fill(AppTheme.brandSoftFill))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    Task { await appState.stopRecordingAndFinalize(generateFinalSummary: true) }
                } label: {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(AppTheme.textPrimary)
                            .frame(width: 8.5, height: 8.5)
                        Text(L("结束并总结", "Stop & Summarize"))
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(Capsule().fill(AppTheme.neutralPill))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: width, height: height, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(AppTheme.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(AppTheme.subtleBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 16, x: 0, y: 6)
        .tint(AppTheme.brandPrimary)
        .preferredColorScheme(theme.preferredColorScheme)
    }

    private var liveSnippet: String {
        if appState.mlxModelState.isBusy {
            return appState.mlxModelState.statusText
        }
        if appState.isPaused {
            return L("录音已暂停 · 点击继续采集声音", "Recording paused · Click Resume to continue")
        }
        if appState.isGeneratingMinutes {
            return L("正在提炼实时会议总结...", "Synthesizing live summary...")
        }
        if !appState.volatileRemoteText.isEmpty {
            return "\(L("发言人", "Speaker")): \(appState.volatileRemoteText)"
        }
        if !appState.volatileMeText.isEmpty {
            return "\(L("我", "Me")): \(appState.volatileMeText)"
        }
        if let highlight = appState.activeRecordingMeeting?.minutes.latestHighlight {
            return highlight
        }
        if let lastSeg = appState.activeRecordingMeeting?.segments.last {
            let prefix = lastSeg.speaker == .me ? L("我", "Me") : L("发言人", "Speaker")
            return "\(prefix): \(lastSeg.text)"
        }
        return L("正在识别说话人和讨论内容...", "Listening for speakers and discussion...")
    }
}

private struct MiniDottedWaveformView: View {
    let level: Float
    let isActive: Bool
    let isPaused: Bool

    @State private var samples: [Float] = Array(repeating: 0, count: 16)

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<samples.count, id: \.self) { i in
                let v = samples[i]
                let h: CGFloat = isActive && !isPaused ? max(3, min(14, 3 + CGFloat(v) * 13)) : 3
                Capsule()
                    .fill(v > 0.06 && isActive && !isPaused
                          ? AppTheme.brandPrimary.opacity(0.75)
                          : AppTheme.waveformInactive)
                    .frame(width: 2, height: h)
                    .animation(.easeOut(duration: 0.1), value: v)
            }
        }
        .frame(height: 15)
        .onChange(of: level) { _, newVal in
            var next = samples
            next.removeFirst()
            let jitter = newVal > 0.02 ? Float.random(in: 0.82...1.18) : 1.0
            next.append(min(1.0, newVal * jitter))
            samples = next
        }
    }
}
