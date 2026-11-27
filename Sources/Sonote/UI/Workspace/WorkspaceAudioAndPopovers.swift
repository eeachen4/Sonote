import SwiftUI
import AppKit
import SonoteCore

// MARK: - Synced Audio Playback Bar (With ±10s Skip, Scrubbing, Speed Control & Spacebar Shortcut)

struct AudioPlaybackStrip: View {
    @ObservedObject var player: MeetingAudioPlayer
    @ObservedObject private var theme = ThemeManager.shared
    @Binding var autoFollowTranscript: Bool

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

            Slider(
                value: Binding(
                    get: { player.currentTime },
                    set: { player.seek(to: $0, autoPlay: false) }
                ),
                in: 0...max(0.1, player.duration)
            )
            .tint(AppTheme.brandPrimary)
            .controlSize(.small)

            Text(MeetingAudioPlayer.formatTime(player.duration))
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
