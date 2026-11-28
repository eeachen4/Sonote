import SwiftUI
import AppKit
import SonoteCore

// MARK: - Synced Audio Playback Bar (With ±10s Skip, Scrubbing, Speed Control & Spacebar Shortcut)

struct AudioPlaybackStrip: View {
    @ObservedObject var player: MeetingAudioPlayer
    @ObservedObject private var theme = ThemeManager.shared
    @Binding var autoFollowTranscript: Bool
    var fallbackDuration: TimeInterval = 0

    private var effectiveDuration: TimeInterval {
        player.duration > 0 ? player.duration : fallbackDuration
    }

    var body: some View {
        HStack(spacing: 9) {
            // Skip back 10s
            Button {
                player.seek(to: max(0, player.currentTime - 10), autoPlay: player.isPlaying)
            } label: {
                Image(systemName: "gobackward.10")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("后退 10 秒", "Rewind 10s"))

            // Play / Pause
            Button {
                player.togglePlayPause()
            } label: {
                ZStack {
                    Circle()
                        .fill(AppTheme.brandSoftFill)
                        .frame(width: 28, height: 28)
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppTheme.brandPrimary)
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(L("播放 / 暂停（空格键）", "Play / Pause (Space)"))

            // Skip forward 10s
            Button {
                let target = player.duration > 0 ? min(player.duration, player.currentTime + 10) : player.currentTime + 10
                player.seek(to: target, autoPlay: player.isPlaying)
            } label: {
                Image(systemName: "goforward.10")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("前进 10 秒", "Forward 10s"))

            Text(MeetingAudioPlayer.formatTime(player.currentTime))
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 42, alignment: .trailing)

            AudioWaveformScrubber(
                samples: player.waveformSamples,
                progress: effectiveDuration > 0 ? min(1, max(0, player.currentTime / effectiveDuration)) : 0,
                duration: effectiveDuration
            ) { newFraction in
                let target = newFraction * max(0.1, effectiveDuration)
                player.seek(to: target, autoPlay: player.isPlaying)
            }

            Text(MeetingAudioPlayer.formatTime(effectiveDuration))
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(AppTheme.textMuted)
                .frame(width: 42, alignment: .leading)

            Button {
                player.cycleRate()
            } label: {
                Text(String(format: "%.2gx", player.playbackRate))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(AppTheme.neutralPill))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(L("切换播放倍速", "Cycle Playback Speed"))

            Button {
                autoFollowTranscript.toggle()
            } label: {
                Image(systemName: "text.line.first.and.arrowtriangle.forward")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(autoFollowTranscript ? AppTheme.brandPrimary : AppTheme.textMuted)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(autoFollowTranscript ? AppTheme.brandSoftFill : Color.clear))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(autoFollowTranscript ? L("逐字稿自动跟随播放：已开启", "Auto-Scroll Transcript: On") : L("逐字稿自动跟随播放：已关闭", "Auto-Scroll Transcript: Off"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.elevatedSurface.opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(AppTheme.subtleBorder, lineWidth: 1)
        )
    }
}

// MARK: - Interactive Audio Waveform Scrubber

struct AudioWaveformScrubber: View {
    let samples: [Float]
    let progress: Double
    let duration: TimeInterval
    let onSeekFraction: (Double) -> Void

    @State private var hoverFraction: Double? = nil
    @State private var isDragging: Bool = false

    private var displayBars: [Float] {
        if !samples.isEmpty { return samples }
        // Subtle flat placeholder bars while envelope finishes decoding
        return Array(repeating: 0.22, count: 64)
    }

    var body: some View {
        GeometryReader { geo in
            let w = max(1, geo.size.width)
            let h = geo.size.height
            let bars = displayBars
            let activeFrac = isDragging ? (hoverFraction ?? progress) : progress

            ZStack(alignment: .leading) {
                HStack(alignment: .center, spacing: 2) {
                    ForEach(0..<bars.count, id: \.self) { idx in
                        let frac = Double(idx) / Double(max(1, bars.count - 1))
                        let isPlayed = frac <= activeFrac
                        let isHovered = hoverFraction.map { frac <= $0 && !isPlayed } ?? false
                        let barH = max(3, CGFloat(bars[idx]) * (h - 6))
                        Capsule()
                            .fill(
                                isPlayed
                                    ? AppTheme.brandPrimary
                                    : (isHovered ? AppTheme.brandPrimary.opacity(0.42) : AppTheme.waveformInactive.opacity(0.45))
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: barH)
                    }
                }
                .frame(height: h)

                // Hover time tooltip badge
                if let hoverFrac = hoverFraction, duration > 0 {
                    let hoverX = min(max(24, CGFloat(hoverFrac) * w), w - 24)
                    Text(MeetingAudioPlayer.formatTime(hoverFrac * duration))
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppTheme.textPrimary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(AppTheme.elevatedSurface))
                        .overlay(Capsule().strokeBorder(AppTheme.inputBorder, lineWidth: 0.8))
                        .position(x: hoverX, y: -4)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let loc):
                    hoverFraction = min(1, max(0, Double(loc.x / w)))
                case .ended:
                    if !isDragging { hoverFraction = nil }
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        let frac = min(1, max(0, Double(value.location.x / w)))
                        hoverFraction = frac
                        onSeekFraction(frac)
                    }
                    .onEnded { value in
                        let frac = min(1, max(0, Double(value.location.x / w)))
                        onSeekFraction(frac)
                        isDragging = false
                        hoverFraction = nil
                    }
            )
        }
        .frame(height: 26)
    }
}

// MARK: - Token Usage Popover

struct TokenUsagePopoverView: View {
    let title: String
    let usage: TokenUsage
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                if usage.isEstimated {
                    Text(L("估算", "Est."))
                        .font(.system(size: 10.5))
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(AppTheme.neutralPill))
                }
            }

            Divider().overlay(AppTheme.divider)

            VStack(spacing: 6) {
                statRow(L("总计 Tokens", "Total Tokens"), TokenUsage.formatNumber(usage.totalTokens), bold: true)
                statRow(L("输入 (Input)", "Input"), TokenUsage.formatNumber(usage.inputTokens))
                statRow(L("输出 (Output)", "Output"), TokenUsage.formatNumber(usage.outputTokens))
                if usage.cachedTokens > 0 {
                    statRow(L("缓存命中 (Cached)", "Cache Hit"), TokenUsage.formatNumber(usage.cachedTokens))
                }
                if usage.reasoningTokens > 0 {
                    statRow(L("推理思考 (Reasoning)", "Reasoning"), TokenUsage.formatNumber(usage.reasoningTokens))
                }
                statRow(L("AI 调用次数", "AI Requests"), L("\(usage.requestCount) 次", "\(usage.requestCount)"))
            }
        }
        .padding(14)
        .frame(width: 235)
        .background(AppTheme.elevatedSurface)
        .preferredColorScheme(theme.preferredColorScheme)
    }

    private func statRow(_ label: String, _ value: String, bold: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: bold ? .semibold : .medium, design: .monospaced))
                .foregroundStyle(AppTheme.textPrimary)
        }
    }
}
