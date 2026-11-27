import Foundation
import SonoteCore

// MARK: - AI Smart Minutes & Interactive Q&A

extension AppState {

    public func refreshMinutesNow(for meetingID: UUID, isFinal: Bool) async {
        guard let meeting = meetings.first(where: { $0.id == meetingID }) else { return }
        let hasTranscript = !meeting.segments.isEmpty
        let hasNotes = !meeting.manualNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasTranscript || hasNotes else {
            statusBannerMessage = L("暂无转写内容或手动笔记，开始说话后即可自动提炼智能纪要。", "No transcript or notes yet. Start speaking to generate live minutes.")
            return
        }

        isGeneratingMinutes = true
        aiStreamingPreview = ""
        statusBannerMessage = isFinal
            ? L("正在生成完整智能会议纪要...", "Generating final meeting minutes...")
            : L("正在实时更新会中纪要要点...", "Updating live summary...")

        do {
            // Use true incremental delta segments during active meetings to cut token usage by 60-80%
            let deltaSegments: [TranscriptSegment]?
            if !isFinal && !meeting.minutes.isEmpty && lastSummarizedSegmentCount > 0 && lastSummarizedSegmentCount < meeting.segments.count {
                deltaSegments = Array(meeting.segments[lastSummarizedSegmentCount...])
            } else {
                deltaSegments = nil
            }

            let (generated, usage) = try await gptClient.generateMinutesWithUsage(
                for: meeting,
                settings: settings,
                isFinal: isFinal,
                deltaSegmentsOnly: deltaSegments
            ) { [weak self] delta in
                Task { @MainActor [weak self] in
                    self?.aiStreamingPreview += delta
                }
            }

            let charCount = meeting.segments.reduce(0) { $0 + $1.text.count }
            lastSummarizedCharCount = charCount
            lastSummarizedSegmentCount = meeting.segments.count
            lastSummarizedManualNotes = meeting.manualNotes

            updateMeeting(id: meetingID) { m in
                // Preserve user checkmarks on matching action items
                let prevCompleted = Set(m.minutes.actionItems.filter(\.isCompleted).map(\.task))
                var merged = generated
                for idx in merged.actionItems.indices {
                    if prevCompleted.contains(merged.actionItems[idx].task) {
                        merged.actionItems[idx].isCompleted = true
                    }
                }
                m.minutes = merged
                m.tokenUsage.add(usage)
                // Auto-upgrade default generic title once AI identifies the real topic
                if !merged.suggestedTitle.isEmpty,
                   (m.title == "新录音" || m.title == "New Recording" || m.title == m.sourceAppName || m.title.contains(" · ") || m.title.hasPrefix("会议记录")) {
                    m.title = merged.suggestedTitle
                }
            }
            recordDailyTokenUsage(usage)

            // Auto-sync to Obsidian / local Markdown folder on final summary if enabled
            if isFinal && settings.autoSyncMarkdownFolder,
               !settings.obsidianVaultPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let updatedMeeting = meetings.first(where: { $0.id == meetingID }) {
                _ = syncMeetingToMarkdownFolder(updatedMeeting)
            }

            statusBannerMessage = isFinal
                ? L("智能会议纪要已生成", "Meeting minutes ready")
                : L("实时纪要已更新", "Live summary updated")
        } catch {
            statusBannerMessage = L("AI 生成纪要失败：\(error.localizedDescription)", "Failed to generate minutes: \(error.localizedDescription)")
        }

        isGeneratingMinutes = false
        aiStreamingPreview = ""
    }

    public func askAI(meetingID: UUID, question: String) async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let meeting = meetings.first(where: { $0.id == meetingID }),
              !isAskingAI else { return }

        let userMsg = MeetingChatMessage(role: .user, content: trimmed)
        let assistantMsgID = UUID()
        let placeholderAssistant = MeetingChatMessage(id: assistantMsgID, role: .assistant, content: "")

        updateMeeting(id: meetingID) { m in
            m.chatHistory.append(userMsg)
            m.chatHistory.append(placeholderAssistant)
        }

        isAskingAI = true
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let (reply, usage) = try await self.gptClient.askAboutMeetingWithUsage(
                    meeting: meeting,
                    question: trimmed,
                    settings: self.settings
                ) { [weak self] delta in
                    Task { @MainActor [weak self] in
                        guard !Task.isCancelled else { return }
                        self?.updateMeeting(id: meetingID, persist: false) { m in
                            if let idx = m.chatHistory.firstIndex(where: { $0.id == assistantMsgID }) {
                                m.chatHistory[idx].content += delta
                            }
                        }
                    }
                }
                if Task.isCancelled {
                    self.persistCancelledAskAI(meetingID: meetingID, assistantMsgID: assistantMsgID)
                } else {
                    self.updateMeeting(id: meetingID) { m in
                        if let idx = m.chatHistory.firstIndex(where: { $0.id == assistantMsgID }) {
                            m.chatHistory[idx].content = reply
                            m.chatHistory[idx].tokenUsage = usage
                        }
                        m.tokenUsage.add(usage)
                    }
                    self.recordDailyTokenUsage(usage)
                }
            } catch {
                let isCancelled = (error is CancellationError)
                    || ((error as? URLError)?.code == .cancelled)
                    || Task.isCancelled
                if isCancelled {
                    self.persistCancelledAskAI(meetingID: meetingID, assistantMsgID: assistantMsgID)
                } else {
                    self.updateMeeting(id: meetingID) { m in
                        if let idx = m.chatHistory.firstIndex(where: { $0.id == assistantMsgID }) {
                            m.chatHistory[idx].content = L("⚠️ 请求失败：\(error.localizedDescription)", "⚠️ Request failed: \(error.localizedDescription)")
                        }
                    }
                }
            }
            self.isAskingAI = false
            self.activeAskAITask = nil
        }
        activeAskAITask = task
        await task.value
    }

    func persistCancelledAskAI(meetingID: UUID, assistantMsgID: UUID) {
        updateMeeting(id: meetingID) { m in
            guard let idx = m.chatHistory.firstIndex(where: { $0.id == assistantMsgID }) else { return }
            let trimmed = m.chatHistory[idx].content.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                m.chatHistory[idx].content = L("（已停止生成）", "(Generation stopped)")
            }
        }
    }

    public func cancelAskAI() {
        activeAskAITask?.cancel()
        activeAskAITask = nil
        isAskingAI = false
    }
}
