import SwiftUI
import SonoteCore

// MARK: - Audio-Synced Click-to-Seek, Search Highlight, Inline Edit & Speaker Rename Transcript View

extension CompletedMeetingDocumentView {

    var hasGenericSpeakers: Bool {
        meeting.distinctSpeakerNames.contains { $0 == "发言人" || $0.hasPrefix("发言人 ") }
    }

    var filteredTranscriptSegments: [TranscriptSegment] {
        let q = transcriptSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return meeting.segments.filter { seg in
            if starredOnlyFilter && !seg.isStarred { return false }
            if let spk = selectedSpeakerFilter, seg.resolvedSpeakerName != spk { return false }
            if !q.isEmpty {
                let matchesText = seg.text.localizedCaseInsensitiveContains(q)
                let matchesSpeaker = seg.resolvedSpeakerName.localizedCaseInsensitiveContains(q)
                if !matchesText && !matchesSpeaker { return false }
            }
            return true
        }
    }

    var syncedTranscriptView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top Controls: Hint + In-Transcript Search + Diarization & AI Name Inference
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    // Compact in-transcript search input
                    HStack(spacing: 5) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 10.5))
                            .foregroundStyle(AppTheme.textMuted)
                        TextField(L("搜索逐字稿关键词...", "Search transcript..."), text: $transcriptSearchQuery)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .frame(width: 168)
                        if !transcriptSearchQuery.isEmpty {
                            Text("\(filteredTranscriptSegments.count)")
                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(AppTheme.brandPrimary)
                            Button {
                                transcriptSearchQuery = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppTheme.textMuted)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(AppTheme.inputBackground))
                    .overlay(Capsule().strokeBorder(AppTheme.inputBorder, lineWidth: 1))

                    Spacer()

                    if hasGenericSpeakers {
                        Button {
                            Task { await appState.inferSpeakerNamesWithAI(for: meeting.id) }
                        } label: {
                            HStack(spacing: 4) {
                                if appState.isInferringSpeakers {
                                    ProgressView().controlSize(.mini)
                                } else {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 10.5))
                                }
                                Text(appState.isInferringSpeakers ? L("推断中...", "Inferring...") : L("AI 猜姓名", "AI Name Guess"))
                                    .font(.system(size: 11.5, weight: .medium))
                            }
                            .foregroundStyle(AppTheme.textSecondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(AppTheme.softCardBg))
                            .overlay(Capsule().strokeBorder(AppTheme.subtleBorder, lineWidth: 1))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(appState.isInferringSpeakers || appState.isDiarizing)
                        .help(L("根据对话上下文和日程参会人自动推断「发言人 1 / 2」的真实姓名", "Infer real speaker names from context & calendar attendees"))
                    }

                    if hasAudioFile {
                        Button {
                            Task { await appState.runSpeakerDiarization(for: meeting.id) }
                        } label: {
                            HStack(spacing: 5) {
                                if appState.isDiarizing {
                                    ProgressView().controlSize(.mini)
                                } else {
                                    Image(systemName: "person.2.wave.2")
                                        .font(.system(size: 11))
                                }
                                Text(appState.isDiarizing ? L("正在识别声纹...", "Identifying...") : L("声纹认人", "Voiceprint ID"))
                                    .font(.system(size: 11.5, weight: .medium))
                            }
                            .foregroundStyle(AppTheme.brandPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(AppTheme.brandSoftFill))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(appState.isDiarizing)
                        .help(L("通过 Sortformer 分离多说话人，并自动匹配本地 ECAPA 声纹库", "Separate speakers via Sortformer and match local ECAPA voiceprints"))
                    }
                }

                Text(hasAudioFile
                     ? L("点击段落跳转回听 · 双击文字修正错字 · 点击说话人改名或记住声纹", "Click paragraph to seek · Double-click text to edit · Click speaker to rename")
                     : L("点击说话人标签可改名 · 双击文字可修正错字", "Click speaker to rename · Double-click text to fix typos"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppTheme.textMuted)

                // Speaker & Star Filter Bar
                let speakers = meeting.distinctSpeakerNames
                let hasStarred = meeting.segments.contains(where: \.isStarred)
                if speakers.count > 1 || hasStarred {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            transcriptFilterPill(
                                title: L("全部 (\(meeting.segments.count))", "All (\(meeting.segments.count))"),
                                isSelected: selectedSpeakerFilter == nil && !starredOnlyFilter
                            ) {
                                selectedSpeakerFilter = nil
                                starredOnlyFilter = false
                            }

                            ForEach(speakers, id: \.self) { name in
                                let count = meeting.segments.filter { $0.resolvedSpeakerName == name }.count
                                transcriptFilterPill(
                                    title: "\(name) (\(count))",
                                    isSelected: selectedSpeakerFilter == name
                                ) {
                                    selectedSpeakerFilter = (selectedSpeakerFilter == name) ? nil : name
                                }
                            }

                            if hasStarred {
                                transcriptFilterPill(
                                    title: L("⭐ 重点", "⭐ Starred"),
                                    isSelected: starredOnlyFilter
                                ) {
                                    starredOnlyFilter.toggle()
                                }
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 4)

            if filteredTranscriptSegments.isEmpty {
                Text(L("没有匹配的逐字稿段落", "No matching transcript segments"))
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.textMuted)
                    .padding(.vertical, 16)
            } else {
                ForEach(filteredTranscriptSegments) { seg in
                    transcriptSegmentRow(seg)
                        .id(seg.id)
                }
            }
        }
    }

    private func transcriptSegmentRow(_ seg: TranscriptSegment) -> some View {
        let isActive = activePlayingSegmentID == seg.id
        let isEditingRow = editingSegmentID == seg.id
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                // Clickable Speaker Name Pill -> Opens Rename & Voiceprint Enrollment Popover
                Button {
                    renamingSegmentID = seg.id
                } label: {
                    HStack(spacing: 4) {
                        Text(seg.resolvedSpeakerName)
                            .font(.system(size: 12, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .medium))
                            .opacity(0.65)
                    }
                    .foregroundStyle(seg.speaker == .me ? AppTheme.brandPrimary : AppTheme.textPrimary.opacity(0.8))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(Capsule().fill(seg.speaker == .me ? AppTheme.brandSoftFill : AppTheme.softCardBg))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(L("点击修改说话人姓名或记住声纹", "Rename speaker or enroll voiceprint"))
                .popover(
                    isPresented: Binding(
                        get: { renamingSegmentID == seg.id },
                        set: { if !$0 && renamingSegmentID == seg.id { renamingSegmentID = nil } }
                    ),
                    arrowEdge: .bottom
                ) {
                    SpeakerRenamePopoverView(
                        currentName: seg.resolvedSpeakerName,
                        hasAudioFile: hasAudioFile,
                        candidateNames: speakerCandidateNames,
                        onConfirm: { newName, applyAll, updateMinutes, enrollVP in
                            renamingSegmentID = nil
                            Task {
                                await appState.renameSpeaker(
                                    meetingID: meeting.id,
                                    oldName: seg.resolvedSpeakerName,
                                    newName: newName,
                                    onlySegmentID: applyAll ? nil : seg.id,
                                    updateMinutes: updateMinutes,
                                    enrollVoiceprint: enrollVP
                                )
                            }
                        },
                        onCancel: { renamingSegmentID = nil }
                    )
                }

                // Timestamp seek pill
                Button {
                    if hasAudioFile {
                        audioPlayer.seek(to: seg.timestamp, autoPlay: true)
                    }
                } label: {
                    HStack(spacing: 3) {
                        if hasAudioFile {
                            Image(systemName: isActive && audioPlayer.isPlaying ? "speaker.wave.2.fill" : "play.fill")
                                .font(.system(size: 8.5))
                        }
                        Text(seg.formattedTimestamp)
                            .font(.system(size: 11, design: .monospaced))
                    }
                    .foregroundStyle(isActive ? AppTheme.brandPrimary : AppTheme.textMuted)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                // Star key quote button
                Button {
                    appState.toggleStarSegment(meetingID: meeting.id, segmentID: seg.id)
                } label: {
                    Image(systemName: seg.isStarred ? "star.fill" : "star")
                        .font(.system(size: 11))
                        .foregroundStyle(seg.isStarred ? AppTheme.warningAmber : AppTheme.textMuted.opacity(0.65))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(seg.isStarred ? L("取消标星重点", "Remove Star") : L("标星为重点发言", "Star Key Quote"))

                // Edit transcript typo button
                Button {
                    if isEditingRow {
                        appState.updateSegmentText(meetingID: meeting.id, segmentID: seg.id, newText: editingSegmentDraft)
                        editingSegmentID = nil
                    } else {
                        editingSegmentDraft = seg.text
                        editingSegmentID = seg.id
                    }
                } label: {
                    Image(systemName: isEditingRow ? "checkmark" : "pencil")
                        .font(.system(size: 10.5))
                        .foregroundStyle(isEditingRow ? AppTheme.brandPrimary : AppTheme.textMuted.opacity(0.65))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isEditingRow ? L("保存修改", "Save Edit") : L("修正转写错字", "Edit Transcript Text"))
            }

            if isEditingRow {
                HStack(spacing: 6) {
                    TextField(L("修正逐字稿文本", "Edit transcript text"), text: $editingSegmentDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13))
                        .onSubmit {
                            appState.updateSegmentText(meetingID: meeting.id, segmentID: seg.id, newText: editingSegmentDraft)
                            editingSegmentID = nil
                        }
                    Button(L("取消", "Cancel")) {
                        editingSegmentID = nil
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppTheme.textSecondary)
                }
            } else {
                highlightedTranscriptText(seg.text, query: transcriptSearchQuery)
                    .font(.system(size: AppTheme.scaled(13.5)))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineSpacing(4)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .onTapGesture(count: 2) {
                        editingSegmentDraft = seg.text
                        editingSegmentID = seg.id
                    }
                    .onTapGesture {
                        if hasAudioFile {
                            audioPlayer.seek(to: seg.timestamp, autoPlay: true)
                        }
                    }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isActive ? AppTheme.mindMapNodeFill : (seg.isStarred ? AppTheme.warningAmber.opacity(0.06) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(isActive ? AppTheme.brandPrimary.opacity(0.28) : Color.clear, lineWidth: 1)
        )
    }

    private func highlightedTranscriptText(_ text: String, query: String) -> Text {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Text(text) }

        var attr = AttributedString(text)
        var searchStart = attr.startIndex
        while searchStart < attr.endIndex,
              let range = attr[searchStart..<attr.endIndex].range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) {
            attr[range].backgroundColor = AppTheme.warningAmber.opacity(0.28)
            attr[range].foregroundColor = AppTheme.textPrimary
            searchStart = range.upperBound
        }
        return Text(attr)
    }

    var speakerCandidateNames: [String] {
        var list: [String] = []
        let local = appState.settings.localUserName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !local.isEmpty { list.append(local) }
        for vp in appState.voiceprints where !list.contains(vp.name) {
            list.append(vp.name)
        }
        for att in meeting.calendarAttendees where !list.contains(att) {
            list.append(att)
        }
        return list
    }

    func transcriptFilterPill(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? AppTheme.brandPrimary : AppTheme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(isSelected ? AppTheme.brandSoftFill : AppTheme.softCardBg))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Speaker Rename & Voiceprint Enrollment Popover

struct SpeakerRenamePopoverView: View {
    let currentName: String
    let hasAudioFile: Bool
    let candidateNames: [String]
    let onConfirm: (_ newName: String, _ applyAll: Bool, _ updateMinutes: Bool, _ enrollVoiceprint: Bool) -> Void
    let onCancel: () -> Void
    @ObservedObject private var theme = ThemeManager.shared

    @State private var nameDraft: String = ""
    @State private var applyToAll: Bool = true
    @State private var updateMinutes: Bool = true
    @State private var enrollVoiceprint: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(L("修改说话人姓名", "Rename Speaker"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)

            TextField(L("输入姓名（如：林致远）", "Enter speaker name (e.g. Alex)"), text: $nameDraft)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12.5))
                .onSubmit { submitIfValid() }

            if !candidateNames.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L("快捷选择（声纹库 / 日程参会人）", "Suggestions (Voiceprints & Calendar)"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(AppTheme.textMuted)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(candidateNames.prefix(10), id: \.self) { candidate in
                                Button {
                                    nameDraft = candidate
                                } label: {
                                    Text(candidate)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(nameDraft == candidate ? AppTheme.brandPrimary : AppTheme.textSecondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3.5)
                                        .background(Capsule().fill(nameDraft == candidate ? AppTheme.brandSoftFill : AppTheme.softCardBg))
                                        .contentShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            Divider().overlay(AppTheme.divider)

            VStack(alignment: .leading, spacing: 7) {
                Toggle(L("同步替换本场所有「\(currentName)」", "Replace all \"\(currentName)\" in this meeting"), isOn: $applyToAll)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))

                if applyToAll {
                    Toggle(L("同步替换纪要与待办中的对应称呼", "Also update mentions in summary & tasks"), isOn: $updateMinutes)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))
                }

                if hasAudioFile {
                    Toggle(L("记住该说话人声纹（跨会议自动认人）", "Save voiceprint for future meetings"), isOn: $enrollVoiceprint)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))
                }
            }

            HStack {
                Spacer()
                Button(L("取消", "Cancel"), action: onCancel)
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())

                Button(L("确定", "Save")) {
                    submitIfValid()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AppTheme.brandPrimary.opacity(0.35) : AppTheme.brandPrimary)
                )
                .contentShape(Rectangle())
                .disabled(nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .frame(width: 286)
        .background(AppTheme.elevatedSurface)
        .preferredColorScheme(theme.preferredColorScheme)
        .onAppear {
            nameDraft = (currentName == "发言人" || currentName.hasPrefix("发言人 ")) ? "" : currentName
            enrollVoiceprint = hasAudioFile
        }
    }

    private func submitIfValid() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onConfirm(trimmed, applyToAll, applyToAll && updateMinutes, hasAudioFile && enrollVoiceprint)
    }
}
