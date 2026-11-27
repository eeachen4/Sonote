import SwiftUI
import SonoteCore

/// Left-hand live transcript stream + bottom dotted waveform + minimal timer/pause/stop dock,
/// matching Doubao Work Screenshot 1.
struct TranscriptPaneView: View {
    let meeting: MeetingSession
    @ObservedObject var appState: AppState
    @ObservedObject private var theme = ThemeManager.shared

    @State private var showQuickNoteInput = false
    @State private var quickNoteDraft = ""
    @FocusState private var isQuickNoteFocused: Bool

    private var isLiveSession: Bool {
        appState.activeRecordingMeetingID == meeting.id
    }

    private var manualNoteLines: [String] {
        meeting.manualNotes
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var hasAnyTranscript: Bool {
        !meeting.segments.isEmpty
            || (isLiveSession && (!appState.volatileRemoteText.isEmpty || !appState.volatileMeText.isEmpty))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Subtle permission notice only if audio capture had an issue
            if isLiveSession && !appState.runtimeWarnings.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppTheme.warningAmber)
                    Text(appState.runtimeWarnings.first ?? "")
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    Button(L("授权", "Grant")) {
                        appState.openPrivacySettings("Privacy_AudioCapture")
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(AppTheme.brandPrimary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8).fill(AppTheme.elevatedSurface))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(AppTheme.subtleBorder))
                .padding(.horizontal, 22)
                .padding(.top, 38)
            }

            // Clean Transcript Scroll Area
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if !hasAnyTranscript {
                            // Exact match to Screenshot 1: two serene skeleton bars
                            VStack(alignment: .leading, spacing: 16) {
                                SkeletonPill(width: 155, height: 14, fill: AppTheme.skeletonBg, cornerRadius: 7)
                                SkeletonPill(width: nil, height: 12, fill: AppTheme.skeletonBg, cornerRadius: 6)
                            }
                            .padding(.top, appState.runtimeWarnings.isEmpty ? 56 : 18)
                        } else {
                            Spacer().frame(height: appState.runtimeWarnings.isEmpty ? 38 : 6)

                            ForEach(meeting.segments) { seg in
                                minimalSegmentRow(seg)
                                    .id(seg.id)
                            }

                            if isLiveSession && !appState.volatileRemoteText.isEmpty {
                                volatileLine(speaker: .remote, text: appState.volatileRemoteText)
                                    .id("v-remote")
                            }
                            if isLiveSession && !appState.volatileMeText.isEmpty {
                                volatileLine(speaker: .me, text: appState.volatileMeText)
                                    .id("v-me")
                            }
                        }
                    }
                    .padding(.horizontal, 26)
                    .padding(.bottom, 20)
                }
                .onChange(of: meeting.segments.count) { _, _ in
                    if isLiveSession, let last = meeting.segments.last {
                        withAnimation(.easeOut(duration: 0.18)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: appState.volatileRemoteText) { _, val in
                    if isLiveSession && !val.isEmpty { proxy.scrollTo("v-remote", anchor: .bottom) }
                }
                .onChange(of: appState.volatileMeText) { _, val in
                    if isLiveSession && !val.isEmpty { proxy.scrollTo("v-me", anchor: .bottom) }
                }
            }

            // Collapsible Lightweight "会中随手记" Strip (unobtrusive when collapsed)
            if isLiveSession {
                VStack(alignment: .leading, spacing: 8) {
                    if showQuickNoteInput {
                        if !manualNoteLines.isEmpty {
                            ScrollView(.vertical, showsIndicators: false) {
                                VStack(alignment: .leading, spacing: 5) {
                                    ForEach(Array(manualNoteLines.suffix(4).enumerated()), id: \.offset) { _, line in
                                        HStack(alignment: .top, spacing: 6) {
                                            Circle()
                                                .fill(AppTheme.brandPrimary.opacity(0.65))
                                                .frame(width: 4, height: 4)
                                                .padding(.top, 6)
                                            Text(line)
                                                .font(.system(size: 11.5))
                                                .foregroundStyle(AppTheme.textSecondary)
                                                .lineLimit(2)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 74)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppTheme.elevatedSurface.opacity(0.88)))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(AppTheme.subtleBorder, lineWidth: 1))
                        }

                        HStack(spacing: 6) {
                            TextField(L("随手记要点/人名/待办，回车融入纪要...", "Jot key points, names, or tasks (Enter to save)..."), text: $quickNoteDraft)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.textPrimary)
                                .focused($isQuickNoteFocused)
                                .onSubmit { submitQuickNote() }

                            Button {
                                submitQuickNote()
                            } label: {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 15))
                                    .foregroundStyle(quickNoteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AppTheme.textMuted.opacity(0.5) : AppTheme.brandPrimary)
                            }
                            .buttonStyle(.plain)
                            .disabled(quickNoteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    showQuickNoteInput = false
                                }
                            } label: {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(AppTheme.textMuted)
                                    .frame(width: 20, height: 20)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(L("收起随手记", "Collapse Quick Notes"))
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(AppTheme.inputBackground))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(AppTheme.brandPrimary.opacity(0.38), lineWidth: 1))
                    } else {
                        HStack {
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    showQuickNoteInput = true
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                    isQuickNoteFocused = true
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "square.and.pencil")
                                        .font(.system(size: 11))
                                    Text(manualNoteLines.isEmpty ? L("随手记", "Quick Notes") : L("随手记 (\(manualNoteLines.count))", "Notes (\(manualNoteLines.count))"))
                                        .font(.system(size: 11.5))
                                }
                                .foregroundStyle(manualNoteLines.isEmpty ? AppTheme.textMuted : AppTheme.brandPrimary)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(manualNoteLines.isEmpty ? AppTheme.elevatedSurface.opacity(0.8) : AppTheme.brandSoftFill))
                                .overlay(Capsule().strokeBorder(manualNoteLines.isEmpty ? AppTheme.subtleBorder : Color.clear, lineWidth: 1))
                                .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .help(L("记录会议重点，AI 提炼纪要时将高优先级参考", "Jot notes — AI prioritizes them in your minutes"))
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, 26)
                .padding(.bottom, 6)
            }

            // Bottom Minimal Audio Waveform + Controls Dock (EXACTLY Screenshot 1)
            VStack(spacing: 20) {
                DoubaoDottedWaveformView(
                    level: max(appState.systemAudioLevel, appState.micAudioLevel),
                    isActive: appState.systemAudioActive || appState.micAudioActive,
                    isPaused: appState.isPaused
                )

                HStack {
                    // Elapsed Timer
                    Text(meeting.formattedDuration)
                        .font(.system(size: 14, weight: .regular, design: .monospaced))
                        .foregroundStyle(AppTheme.textPrimary)
                        .frame(width: 68, alignment: .leading)

                    Spacer()

                    // Soft-Blue Pause / Play Pill
                    Button {
                        appState.togglePauseRecording()
                    } label: {
                        Image(systemName: appState.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(AppTheme.brandPrimary)
                            .frame(width: 72, height: 38)
                            .background(Capsule().fill(AppTheme.brandSoftFill))
                    }
                    .buttonStyle(.plain)
                    .help(appState.isPaused ? L("继续记录", "Resume Recording") : L("暂停记录", "Pause Recording"))

                    Spacer()

                    // Soft-Gray Stop Square Pill
                    Button {
                        Task { await appState.stopRecordingAndFinalize(generateFinalSummary: true) }
                    } label: {
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .fill(AppTheme.textPrimary)
                            .frame(width: 11, height: 11)
                            .frame(width: 64, height: 38)
                            .background(Capsule().fill(AppTheme.neutralPill))
                    }
                    .buttonStyle(.plain)
                    .help(L("结束录音并生成总结", "Stop & Summarize"))
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 10)
            .padding(.bottom, 22)
        }
        .background(AppTheme.leftPaneBg)
    }

    private func minimalSegmentRow(_ seg: TranscriptSegment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(seg.resolvedSpeakerName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(seg.speaker == .me ? AppTheme.brandPrimary : AppTheme.textSecondary)
                Text(seg.formattedTimestamp)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(AppTheme.textMuted)
            }
            Text(seg.text)
                .font(.system(size: AppTheme.scaled(13.5)))
                .foregroundStyle(AppTheme.textPrimary)
                .lineSpacing(4)
                .textSelection(.enabled)
        }
    }

    private func submitQuickNote() {
        let trimmed = quickNoteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appState.addQuickManualNote(trimmed, to: meeting.id)
        quickNoteDraft = ""
    }

    private func volatileLine(speaker: SpeakerSource, text: String) -> some View {
        let localName = appState.settings.localUserName.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = speaker == .me ? (localName.isEmpty ? L("我", "Me") : localName) : L("发言人", "Speaker")
        return VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.textMuted)
            Text(text)
                .font(.system(size: 13.5))
                .foregroundStyle(AppTheme.textSecondary)
                .lineSpacing(4)
        }
    }
}
