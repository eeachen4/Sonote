import Foundation
import AppKit
import UniformTypeIdentifiers
import SonoteCore

// MARK: - Tags, Action Items, Reminders, Cross-Meeting AI, Webhooks, Obsidian Sync, Backup & MLX Controls

extension AppState {

    public var allMeetingTags: [String] {
        var tags: [String] = []
        for m in meetings {
            for t in m.tags where !t.isEmpty && !tags.contains(t) {
                tags.append(t)
            }
        }
        return tags
    }

    public func addTag(_ rawTag: String, to meetingID: UUID) {
        let cleaned = rawTag.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard !cleaned.isEmpty else { return }
        updateMeeting(id: meetingID) { m in
            if !m.tags.contains(cleaned) {
                m.tags.append(cleaned)
            }
        }
    }

    public func removeTag(_ tag: String, from meetingID: UUID) {
        updateMeeting(id: meetingID) { m in
            m.tags.removeAll { $0 == tag }
        }
    }

    public var allActionItems: [GlobalActionItemEntry] {
        var entries: [GlobalActionItemEntry] = []
        for m in meetings {
            for item in m.minutes.actionItems {
                entries.append(GlobalActionItemEntry(
                    meetingID: m.id,
                    meetingTitle: m.title,
                    meetingDate: m.startedAt,
                    item: item
                ))
            }
        }
        return entries
    }

    public var openActionItemsCount: Int {
        allActionItems.filter { !$0.item.isCompleted }.count
    }

    public func exportActionItemsToReminders(_ entries: [GlobalActionItemEntry]) async -> String {
        do {
            let count = try await CalendarContextService.shared.exportActionItemsToReminders(
                entries.map { (meetingTitle: $0.meetingTitle, item: $0.item) }
            )
            let msg = count > 0
                ? L("已同步 \(count) 条待办到 macOS「提醒事项」", "Synced \(count) action items to Apple Reminders")
                : L("没有需要同步的未完成待办", "No open action items to sync")
            statusBannerMessage = msg
            return msg
        } catch {
            let msg = L("同步提醒事项失败：\(error.localizedDescription)", "Reminders sync failed: \(error.localizedDescription)")
            statusBannerMessage = msg
            return msg
        }
    }

    public func askAcrossMeetings(
        meetingIDs: [UUID],
        question: String,
        onDelta: @escaping @Sendable (String) -> Void
    ) async -> (text: String, usage: TokenUsage)? {
        let selected = meetings.filter { meetingIDs.contains($0.id) }
        guard !selected.isEmpty else { return nil }
        do {
            let (reply, usage) = try await gptClient.askAcrossMeetingsWithUsage(
                meetings: selected,
                question: question,
                settings: settings,
                onStreamDelta: onDelta
            )
            recordDailyTokenUsage(usage)
            return (reply, usage)
        } catch {
            return (L("⚠️ 跨会议分析请求失败：\(error.localizedDescription)", "⚠️ Cross-meeting Q&A failed: \(error.localizedDescription)"), TokenUsage())
        }
    }

    // MARK: - Obsidian / Local Markdown Folder Sync

    @discardableResult
    public func syncMeetingToMarkdownFolder(_ meeting: MeetingSession) -> MarkdownFolderSyncResult {
        let result = MarkdownFolderSyncService.shared.sync(meeting: meeting, toFolder: settings.obsidianVaultPath)
        if let err = result.errorMessage {
            statusBannerMessage = L("同步 Markdown 目录失败：\(err)", "Markdown folder sync failed: \(err)")
        } else if let url = result.lastFileURL {
            statusBannerMessage = L("已同步笔记至 \(url.lastPathComponent)", "Synced note to \(url.lastPathComponent)")
        }
        return result
    }

    @discardableResult
    public func syncAllMeetingsToMarkdownFolder() -> MarkdownFolderSyncResult {
        let result = MarkdownFolderSyncService.shared.syncAll(meetings: meetings, toFolder: settings.obsidianVaultPath)
        if let err = result.errorMessage {
            statusBannerMessage = L("批量同步失败：\(err)", "Batch sync failed: \(err)")
        } else {
            statusBannerMessage = L("已同步 \(result.syncedCount) 场会议至 Markdown 目录", "Synced \(result.syncedCount) meetings to Markdown folder")
        }
        return result
    }

    // MARK: - Clipboard, PDF & Markdown Exports

    public func copyRichTextToClipboard(for meeting: MeetingSession, includeTranscript: Bool = false) {
        let html = MeetingStore.exportHTML(for: meeting, includeTranscript: includeTranscript)
        let markdownFallback = MeetingStore.exportMarkdown(for: meeting, includeTranscript: includeTranscript)
        let pb = NSPasteboard.general
        pb.clearContents()

        let htmlData = Data(html.utf8)
        if let attr = try? NSAttributedString(
            data: htmlData,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        ), let rtfData = try? attr.data(
            from: NSRange(location: 0, length: attr.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        ) {
            pb.declareTypes([.html, .rtf, .string], owner: nil)
            pb.setData(htmlData, forType: .html)
            pb.setData(rtfData, forType: .rtf)
            pb.setString(markdownFallback, forType: .string)
        } else {
            pb.declareTypes([.html, .string], owner: nil)
            pb.setData(htmlData, forType: .html)
            pb.setString(markdownFallback, forType: .string)
        }
        statusBannerMessage = L("已复制富文本纪要（可直接粘贴到飞书文档 / 邮件）", "Copied rich text (paste into Feishu / Mail)")
    }

    public func copyMarkdownToClipboard(for meeting: MeetingSession, includeTranscript: Bool = true) {
        let md = MeetingStore.exportMarkdown(for: meeting, includeTranscript: includeTranscript)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(md, forType: .string)
        statusBannerMessage = L("已复制 Markdown 会议纪要到剪贴板", "Copied Markdown minutes to clipboard")
    }

    public func copyMermaidMindMapToClipboard(for meeting: MeetingSession) {
        let mermaid = MeetingStore.exportMermaidMindMap(for: meeting)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(mermaid, forType: .string)
        statusBannerMessage = L("已复制 Mermaid 思维导图代码到剪贴板", "Copied Mermaid mind-map to clipboard")
    }

    public func exportMarkdownWithSavePanel(for meeting: MeetingSession) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        let safeName = meeting.title.replacingOccurrences(of: "/", with: "-")
        panel.nameFieldStringValue = "\(safeName).md"
        panel.title = L("导出智能会议纪要 (Markdown)", "Export Meeting Minutes (Markdown)")
        if panel.runModal() == .OK, let url = panel.url {
            let md = MeetingStore.exportMarkdown(for: meeting, includeTranscript: true)
            do {
                try md.write(to: url, atomically: true, encoding: .utf8)
                statusBannerMessage = L("已导出至 \(url.lastPathComponent)", "Exported to \(url.lastPathComponent)")
            } catch {
                reportExportError(format: "Markdown", error: error)
            }
        }
    }

    public func exportPDFWithSavePanel(for meeting: MeetingSession, includeTranscript: Bool = false) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        let safeName = meeting.title.replacingOccurrences(of: "/", with: "-")
        let suffix = includeTranscript ? L("-含逐字稿", "-with-transcript") : ""
        panel.nameFieldStringValue = "\(safeName)\(suffix).pdf"
        panel.title = includeTranscript
            ? L("导出会议纪要与逐字稿 (PDF)", "Export Minutes & Transcript (PDF)")
            : L("导出智能会议纪要 (PDF)", "Export Meeting Minutes (PDF)")
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try MeetingPDFExporter.exportPDF(for: meeting, includeTranscript: includeTranscript, to: url)
                statusBannerMessage = L("已导出 PDF 至 \(url.lastPathComponent)", "Exported PDF to \(url.lastPathComponent)")
            } catch {
                reportExportError(format: "PDF", error: error)
            }
        }
    }

    public func exportSRTWithSavePanel(for meeting: MeetingSession) {
        let content = MeetingStore.exportSRT(for: meeting)
        guard !content.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        let safeName = meeting.title.replacingOccurrences(of: "/", with: "-")
        panel.nameFieldStringValue = "\(safeName).srt"
        panel.title = L("导出会议字幕 (SRT)", "Export Subtitles (SRT)")
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
                statusBannerMessage = L("已导出 SRT 字幕至 \(url.lastPathComponent)", "Exported SRT to \(url.lastPathComponent)")
            } catch {
                reportExportError(format: "SRT", error: error)
            }
        }
    }

    public func exportVTTWithSavePanel(for meeting: MeetingSession) {
        let content = MeetingStore.exportVTT(for: meeting)
        guard !meeting.segments.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        let safeName = meeting.title.replacingOccurrences(of: "/", with: "-")
        panel.nameFieldStringValue = "\(safeName).vtt"
        panel.title = L("导出会议字幕 (WebVTT)", "Export Subtitles (WebVTT)")
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
                statusBannerMessage = L("已导出 VTT 字幕至 \(url.lastPathComponent)", "Exported VTT to \(url.lastPathComponent)")
            } catch {
                reportExportError(format: "WebVTT", error: error)
            }
        }
    }

    private func reportExportError(format: String, error: Error) {
        let msg = L("导出 \(format) 失败：\(error.localizedDescription)", "\(format) export failed: \(error.localizedDescription)")
        statusBannerMessage = msg
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("文件导出失败", "Export Failed")
        alert.informativeText = msg
        alert.addButton(withTitle: L("好的", "OK"))
        alert.runModal()
    }

    // MARK: - Pinning, Batch Management, Glossary Auto-Learning & Custom Ask AI Prompts

    public func togglePinMeeting(id: UUID) {
        updateMeeting(id: id) { $0.isPinned.toggle() }
    }

    public func batchDeleteMeetings(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let targets = meetings.filter { ids.contains($0.id) }
        for m in targets {
            deleteMeeting(m)
        }
        statusBannerMessage = L("已删除 \(targets.count) 场会议记录", "Deleted \(targets.count) meetings")
    }

    public func batchAddTag(_ rawTag: String, to ids: Set<UUID>) {
        let cleaned = rawTag.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard !cleaned.isEmpty, !ids.isEmpty else { return }
        for id in ids {
            addTag(cleaned, to: id)
        }
        statusBannerMessage = L("已为 \(ids.count) 场会议添加标签 #\(cleaned)", "Added #\(cleaned) to \(ids.count) meetings")
    }

    public func batchExportMarkdownToFolder(ids: Set<UUID>) {
        let selected = meetings.filter { ids.contains($0.id) }
        guard !selected.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.title = L("选择批量导出 Markdown 的目标文件夹", "Choose Folder to Export Selected Meetings (.md)")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let dirURL = panel.url else { return }

        let result = MarkdownFolderSyncService.shared.syncAll(meetings: selected, toFolder: dirURL.path)
        if let err = result.errorMessage {
            statusBannerMessage = L("批量导出失败：\(err)", "Batch export failed: \(err)")
        } else {
            statusBannerMessage = L("已批量导出 \(result.syncedCount) 份 Markdown 至 \(dirURL.lastPathComponent)", "Exported \(result.syncedCount) Markdown files to \(dirURL.lastPathComponent)")
        }
    }

    @discardableResult
    public func addGlossaryTerm(_ rawTerm: String) -> Bool {
        let trimmed = rawTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if settings.glossaryTerms.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return false
        }
        settings.glossaryTerms.append(trimmed)
        statusBannerMessage = L("已将「\(trimmed)」加入专业词典，后续转写自动生效", "Added \"\(trimmed)\" to ASR glossary")
        return true
    }

    public func addCustomAskAIPrompt(_ rawPrompt: String) {
        let trimmed = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !settings.customAskAIPrompts.contains(trimmed) else { return }
        settings.customAskAIPrompts.append(trimmed)
    }

    public func removeCustomAskAIPrompt(_ prompt: String) {
        settings.customAskAIPrompts.removeAll { $0 == prompt }
    }

    @discardableResult
    public func replaceInTranscript(meetingID: UUID, find: String, replaceWith: String) -> Int {
        var count = 0
        updateMeeting(id: meetingID) { m in
            count = m.replaceInTranscript(find: find, replaceWith: replaceWith)
        }
        if count > 0 {
            statusBannerMessage = L("已替换 \(count) 处「\(find)」→「\(replaceWith)」", "Replaced \(count) occurrence(s)")
        }
        return count
    }

    @discardableResult
    public func mergeAdjacentTranscriptSegments(meetingID: UUID) -> Int {
        var merged = 0
        updateMeeting(id: meetingID) { m in
            merged = m.mergeAdjacentSameSpeakerSegments()
        }
        if merged > 0 {
            statusBannerMessage = L("已合并 \(merged) 条相邻同人短句", "Merged \(merged) adjacent segment(s)")
        }
        return merged
    }

    /// Archives a Cross-Meeting AI synthesis report as a standalone completed meeting document
    /// (with full Markdown rendering, export, PDF, Webhook & Obsidian auto-sync support).
    @discardableResult
    public func saveCrossMeetingReportAsMeeting(
        title: String,
        markdownContent: String,
        sourceMeetingTitles: [String],
        usage: TokenUsage? = nil
    ) -> MeetingSession {
        let df = DateFormatter()
        df.dateFormat = "MM-dd"
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = cleanTitle.isEmpty
            ? L("跨会议汇总 · \(df.string(from: Date()))", "Cross-Meeting Digest · \(df.string(from: Date()))")
            : cleanTitle

        let sourceNote = sourceMeetingTitles.isEmpty
            ? ""
            : L("来源会议（\(sourceMeetingTitles.count) 场）：", "Source meetings (\(sourceMeetingTitles.count)): ")
              + sourceMeetingTitles.joined(separator: "、")

        let session = MeetingSession(
            title: resolvedTitle,
            sourceAppName: L("跨会议汇总", "AI Digest"),
            startedAt: Date(),
            endedAt: Date(),
            duration: 0,
            status: .completed,
            manualNotes: sourceNote,
            minutes: SmartMinutes(
                suggestedTitle: resolvedTitle,
                overview: "",
                lastUpdatedAt: Date(),
                isFinalized: true,
                rawMarkdownFallback: markdownContent
            ),
            tokenUsage: usage ?? TokenUsage(),
            tags: [L("汇总", "Digest")]
        )

        meetings.insert(session, at: 0)
        store.saveMeetingAsync(session)
        if settings.autoSyncMarkdownFolder && !settings.obsidianVaultPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            _ = syncMeetingToMarkdownFolder(session)
        }
        statusBannerMessage = L("已保存为新纪要「\(resolvedTitle)」", "Saved digest as \"\(resolvedTitle)\"")
        return session
    }

    // MARK: - Webhook Push, Backup Archive & On-Device MLX Controls

    public func pushMeetingToWebhook(_ meeting: MeetingSession) async -> (success: Bool, message: String) {
        guard !isPushingWebhook else { return (false, L("正在推送中...", "Sending...")) }
        isPushingWebhook = true
        defer { isPushingWebhook = false }
        do {
            try await WebhookPushService.shared.push(
                meeting: meeting,
                provider: settings.webhookProvider,
                webhookURL: settings.webhookURL,
                secret: settings.webhookSecret
            )
            let msg = L("已推送「\(meeting.title)」到 \(settings.webhookProvider.displayName)", "Pushed \"\(meeting.title)\" via Webhook")
            statusBannerMessage = msg
            return (true, msg)
        } catch {
            let msg = error.localizedDescription
            statusBannerMessage = msg
            return (false, msg)
        }
    }

    public func sendTestWebhook() async -> (success: Bool, message: String) {
        let testSession = MeetingSession(
            title: L("Sonote（声记）Webhook 连通性测试", "Sonote Webhook Connectivity Test"),
            sourceAppName: "Sonote",
            duration: 60,
            status: .completed,
            minutes: SmartMinutes(
                overview: L("这是一条来自「Sonote 声记」的 Webhook 测试卡片，配置已生效。", "This is a test webhook card from Sonote. Your configuration is working."),
                decisions: [L("确认 Webhook 推送链路正常", "Verified webhook delivery pipeline")],
                actionItems: [ActionItem(task: L("会后点击「导出 / 复制 → 推送到 Webhook」即可一键同步纪要", "Use Export -> Push to Webhook after meetings"), owner: settings.localUserName.isEmpty ? L("我", "Me") : settings.localUserName)]
            ),
            tags: ["test"]
        )
        return await pushMeetingToWebhook(testSession)
    }

    public func exportBackupArchiveWithSavePanel(includeAudio: Bool) -> String? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmm"
        panel.nameFieldStringValue = "Sonote-Backup-\(df.string(from: Date())).zip"
        panel.title = L("导出 Sonote（声记）全库备份（不含 API 密钥）", "Export Sonote Full Library Backup (No API Keys)")
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        flushPendingPersistence()
        do {
            try ArchiveBackupService.exportArchive(to: url, includeAudioFiles: includeAudio)
            let msg = L("已导出全库备份至 \(url.lastPathComponent)", "Exported backup to \(url.lastPathComponent)")
            statusBannerMessage = msg
            return msg
        } catch {
            let msg = L("备份导出失败：\(error.localizedDescription)", "Backup export failed: \(error.localizedDescription)")
            statusBannerMessage = msg
            return msg
        }
    }

    public func importBackupArchiveWithOpenPanel(restoreSettings: Bool = true) -> String? {
        let panel = NSOpenPanel()
        panel.title = L("选择 Sonote（声记）备份包 (.zip) 进行合并恢复", "Choose Sonote Backup Archive (.zip) to Merge")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            let summary = try ArchiveBackupService.importArchive(from: url, restoreSettings: restoreSettings)
            self.meetings = store.loadMeetings()
            self.voiceprints = voiceprintStore.loadProfiles()
            self.dailyTokenLedger = store.loadTokenLedger(seedFrom: self.meetings)
            self.audioStorageStats = store.audioStorageStats()
            if restoreSettings {
                self.settings = store.loadSettings()
            }
            let msg = L(
                "恢复完成：合并 \(summary.meetingsImported) 场会议、\(summary.voiceprintsImported) 份声纹、\(summary.audioFilesRestored) 个音频",
                "Restored \(summary.meetingsImported) meetings, \(summary.voiceprintsImported) voiceprints, \(summary.audioFilesRestored) audio files"
            )
            statusBannerMessage = msg
            return msg
        } catch {
            let msg = L("备份恢复失败：\(error.localizedDescription)", "Backup restore failed: \(error.localizedDescription)")
            statusBannerMessage = msg
            return msg
        }
    }

    public func preloadLocalMLXLLM() async {
        guard !isPreloadingLocalLLM else { return }
        isPreloadingLocalLLM = true
        statusBannerMessage = L("正在下载/初始化内置离线 MLX 模型...", "Loading built-in offline MLX LLM...")
        do {
            _ = try await LocalMLXLLMEngine.shared.ensureLoaded(
                modelID: settings.localMLXLLMModelID,
                hfHost: settings.mlxHuggingFaceHost
            )
            refreshAuthInspection()
            statusBannerMessage = L("内置离线 MLX 模型已就绪", "Built-in offline MLX LLM ready")
        } catch {
            statusBannerMessage = L("内置离线 MLX 模型加载失败：\(error.localizedDescription)", "Failed to load offline MLX LLM: \(error.localizedDescription)")
        }
        isPreloadingLocalLLM = false
    }

    public func unloadLocalMLXLLM() async {
        await LocalMLXLLMEngine.shared.unload()
        statusBannerMessage = L("已释放内置离线 MLX 模型显存", "Unloaded offline MLX LLM weights")
    }

    public func preloadMLXQwen3Model() async {
        let modelID = settings.mlxQwen3ModelID
        let hfHost = settings.mlxHuggingFaceHost
        do {
            _ = try await MLXQwen3ASREngine.shared.ensureLoaded(
                modelID: modelID,
                hfHost: hfHost
            ) { [weak self] state in
                Task { @MainActor [weak self] in
                    self?.mlxModelState = state
                }
            }
        } catch {
            mlxModelState = .failed(error.localizedDescription)
        }
    }

    public func unloadMLXQwen3Model() async {
        await MLXQwen3ASREngine.shared.unloadModel { [weak self] state in
            Task { @MainActor [weak self] in
                self?.mlxModelState = state
            }
        }
    }

    public func openPrivacySettings(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
