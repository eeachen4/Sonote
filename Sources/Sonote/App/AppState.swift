import Foundation
import SwiftUI
import AppKit
import AVFoundation
import Speech
import UniformTypeIdentifiers
import SonoteCore

public struct GlobalActionItemEntry: Identifiable, Sendable {
    public var id: UUID { item.id }
    public var meetingID: UUID
    public var meetingTitle: String
    public var meetingDate: Date
    public var item: ActionItem
}

@MainActor
public final class AppState: ObservableObject {
    public static let shared = AppState()

    // MARK: - Published State

    @Published public var settings: AppSettings {
        didSet {
            handleSettingsDidChange(from: oldValue, to: settings)
        }
    }

    private func handleSettingsDidChange(from oldValue: AppSettings, to newValue: AppSettings) {
        if oldValue.appearanceMode != newValue.appearanceMode
            || oldValue.accentTheme != newValue.accentTheme
            || oldValue.interfaceLanguage != newValue.interfaceLanguage
            || oldValue.fontScale != newValue.fontScale {
            ThemeManager.shared.sync(with: newValue)
        }

        // Write ONLY changed secrets to Keychain immediately; debounce settings.json writes off MainActor
        store.saveChangedSecrets(newValue, previous: oldValue)
        scheduleDebouncedSettingsSave(newValue)

        let authChanged = oldValue.authMode != newValue.authMode
            || oldValue.authFilePath != newValue.authFilePath
            || oldValue.apiKey != newValue.apiKey
            || oldValue.apiBaseURL != newValue.apiBaseURL
            || oldValue.model != newValue.model
            || oldValue.codexModel != newValue.codexModel
            || oldValue.deepSeekAPIKey != newValue.deepSeekAPIKey
            || oldValue.deepSeekBaseURL != newValue.deepSeekBaseURL
            || oldValue.deepSeekModel != newValue.deepSeekModel
            || oldValue.qwenAPIKey != newValue.qwenAPIKey
            || oldValue.qwenBaseURL != newValue.qwenBaseURL
            || oldValue.qwenModel != newValue.qwenModel
            || oldValue.domesticProvider != newValue.domesticProvider
            || oldValue.domesticAPIKey != newValue.domesticAPIKey
            || oldValue.domesticBaseURL != newValue.domesticBaseURL
            || oldValue.domesticModel != newValue.domesticModel
            || oldValue.claudeAPIKey != newValue.claudeAPIKey
            || oldValue.claudeBaseURL != newValue.claudeBaseURL
            || oldValue.claudeModel != newValue.claudeModel
            || oldValue.geminiAPIKey != newValue.geminiAPIKey
            || oldValue.geminiBaseURL != newValue.geminiBaseURL
            || oldValue.geminiModel != newValue.geminiModel
            || oldValue.localMLXLLMModelID != newValue.localMLXLLMModelID
        if authChanged {
            refreshAuthInspection()
        }

        let detectionChanged = oldValue.autoDetectMeetings != newValue.autoDetectMeetings
            || oldValue.detectBrowserCalls != newValue.detectBrowserCalls
            || oldValue.promptOnMeetingEnd != newValue.promptOnMeetingEnd
            || oldValue.monitoredBundleIDs != newValue.monitoredBundleIDs
            || oldValue.ignoredBundleIDs != newValue.ignoredBundleIDs
        if detectionChanged {
            detector.configure(settings: newValue) { [weak self] in
                self?.isRecordingOrPaused ?? false
            }
        }

        if oldValue.enableGlobalHotKeys != newValue.enableGlobalHotKeys
            || oldValue.globalHotKeyPreset != newValue.globalHotKeyPreset {
            GlobalHotKeyService.shared.configure(
                enabled: newValue.enableGlobalHotKeys,
                preset: newValue.globalHotKeyPreset
            )
        }
    }

    private func scheduleDebouncedSettingsSave(_ snapshot: AppSettings) {
        pendingSettingsSaveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.store.saveSettingsJSONAsync(snapshot)
        }
        pendingSettingsSaveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    /// Flushes any debounced settings write and queued background meeting saves synchronously.
    public func flushPendingPersistence() {
        if let pending = pendingSettingsSaveWorkItem {
            pending.cancel()
            pendingSettingsSaveWorkItem = nil
            store.saveSettingsJSONAsync(settings)
        }
        store.flushPendingWrites()
    }

    @Published public var authInspection: AuthInspectionResult
    @Published public var meetings: [MeetingSession] = []
    @Published public var selectedMeetingID: UUID? {
        didSet {
            if let id = selectedMeetingID {
                ensureMeetingLoaded(id: id)
            }
        }
    }
    @Published public var activeRecordingMeetingID: UUID?
    @Published public var dailyTokenLedger: [String: TokenUsage] = [:]
    @Published public var audioStorageStats: AudioStorageStats = AudioStorageStats()
    @Published public var voiceprints: [VoiceprintProfile] = []
    private var hydratedMeetingIDs: Set<UUID> = []

    // Live audio capture status (high-frequency meters isolated in `audioMeters` to avoid AppState invalidation)
    @Published public var isPaused: Bool = false
    @Published public var systemAudioActive: Bool = false
    @Published public var micAudioActive: Bool = false
    public let audioMeters = AudioMeterState()

    // Live volatile streaming transcription
    @Published public var volatileRemoteText: String = ""
    @Published public var volatileMeText: String = ""
    @Published public var mlxModelState: MLXModelState = .idle

    // AI generation & background job state
    @Published public var isGeneratingMinutes: Bool = false
    @Published public var isAskingAI: Bool = false
    @Published public var isDiarizing: Bool = false
    @Published public var isRetranscribing: Bool = false
    @Published public var isInferringSpeakers: Bool = false
    @Published public var isEnrollingVoiceprint: Bool = false
    @Published public var voiceprintEnrollProgress: Double = 0
    @Published public var voiceprintEnrollLevel: Float = 0
    @Published public var voiceprintStatusMessage: String?
    @Published public var isPreloadingDenoiser: Bool = false
    @Published public var isPreloadingLocalLLM: Bool = false
    @Published public var isPushingWebhook: Bool = false
    @Published public var importProgress: AudioFileImportProgress?
    @Published public var aiStreamingPreview: String = ""
    @Published public var statusBannerMessage: String?
    @Published public var runtimeWarnings: [String] = []

    // Detection prompts
    @Published public var pendingDetectedMeeting: DetectedMeetingApp?
    @Published public var pendingEndedMeeting: DetectedMeetingApp?

    // Floating capsule, live subtitle bar & smart live highlight
    @Published public var isCapsuleVisible: Bool = false
    @Published public var isSubtitleBarVisible: Bool = false
    @Published public var liveSubtitleTranslation: String = ""
    @Published public var pendingLiveStarHighlight: Bool = false
    @Published public var lastLiveHighlightFlash: String? = nil

    // Crash recovery banner for an abnormally interrupted prior recording
    @Published public var recoveredInterruptedMeetingID: UUID? = nil

    // MARK: - Services (internal for domain extensions)

    let store = MeetingStore.shared
    let voiceprintStore = VoiceprintStore.shared
    let authManager = AuthManager.shared
    let gptClient = GPTClient.shared
    let audioManager = DualAudioCaptureManager()
    let transcriptionCoordinator = TranscriptionCoordinator()
    let detector = MeetingDetector()

    var durationTimer: Timer?
    var liveSummaryTimer: Timer?
    var lastSummarizedCharCount: Int = 0
    var lastSummarizedSegmentCount: Int = 0
    var lastSummarizedManualNotes: String = ""
    var activeAskAITask: Task<Void, Never>?
    var activeImportTask: Task<Void, Never>?
    var activeSubtitleTranslationTask: Task<Void, Never>?
    var subtitleTranslationGeneration: UInt64 = 0
    let recordingClock = RecordingClock()
    private var pendingSettingsSaveWorkItem: DispatchWorkItem?

    // Callbacks wired by AppDelegate / SwiftUI for NSPanel & main NSWindow management
    public weak var trackedMainWindow: NSWindow?
    public var swiftUIOpenMainWindow: (() -> Void)?
    public var onShowMeetingPrompt: ((DetectedMeetingApp) -> Void)?
    public var onShowMeetingEndPrompt: ((DetectedMeetingApp) -> Void)?
    public var onHidePromptPanel: (() -> Void)?
    public var onUpdateCapsuleVisibility: ((Bool) -> Void)?
    public var onUpdateSubtitleVisibility: ((Bool) -> Void)?
    public var onOpenMainWindow: (() -> Void)?
    public var onHideMainWindow: (() -> Void)?
    public var onToggleMainWindow: (() -> Void)?

    public func registerMainWindow(_ window: NSWindow) {
        window.identifier = NSUserInterfaceItemIdentifier("sonote-main-window")
        window.isReleasedWhenClosed = false
        trackedMainWindow = window
    }

    public init() {
        let loadedSettings = MeetingStore.shared.loadSettings()
        ThemeManager.shared.sync(with: loadedSettings)
        self.settings = loadedSettings
        self.authInspection = AuthManager.shared.inspect(settings: loadedSettings)

        // Check for abnormally interrupted recordings BEFORE loadMeetings normalizes their status
        let interruptedIDs = MeetingStore.shared.detectInterruptedMeetingIDs()

        // Fast-startup path: use meetings_index.json for O(1) instant Home rendering when library is large (>25 meetings)
        let indexEntries = MeetingStore.shared.loadMeetingIndex()
        if indexEntries.count > 25 && interruptedIDs.isEmpty {
            self.meetings = indexEntries.map { $0.toLightweightSession() }
            self.dailyTokenLedger = MeetingStore.shared.loadTokenLedger(seedFrom: nil)
            self.hydrateMeetingsInBackground()
        } else {
            let loadedMeetings = MeetingStore.shared.loadMeetings()
            self.meetings = loadedMeetings
            self.hydratedMeetingIDs = Set(loadedMeetings.map(\.id))
            self.dailyTokenLedger = MeetingStore.shared.loadTokenLedger(seedFrom: loadedMeetings)
        }
        self.recoveredInterruptedMeetingID = interruptedIDs.first

        self.audioStorageStats = MeetingStore.shared.audioStorageStats()
        self.voiceprints = VoiceprintStore.shared.loadProfiles()
        // Land on the clean Home page on launch instead of jumping directly into an old recording
        self.selectedMeetingID = nil

        setupDetector()
    }

    /// Hydrates a single meeting's full transcript/chat JSON from disk on demand (O(1) file read).
    public func ensureMeetingLoaded(id: UUID) {
        guard !hydratedMeetingIDs.contains(id) else { return }
        if let full = store.loadMeeting(id: id),
           let idx = meetings.firstIndex(where: { $0.id == id }) {
            meetings[idx] = full
            hydratedMeetingIDs.insert(id)
        }
    }

    private func hydrateMeetingsInBackground() {
        let storeRef = self.store
        Task.detached(priority: .utility) { [weak self] in
            let fullMeetings = storeRef.loadMeetings()
            await MainActor.run { [weak self] in
                guard let self else { return }
                var byID: [UUID: MeetingSession] = [:]
                for m in fullMeetings { byID[m.id] = m }
                for idx in self.meetings.indices {
                    let id = self.meetings[idx].id
                    if !self.hydratedMeetingIDs.contains(id), let full = byID[id] {
                        self.meetings[idx] = full
                        self.hydratedMeetingIDs.insert(id)
                    }
                }
                if self.dailyTokenLedger.isEmpty {
                    self.dailyTokenLedger = self.store.loadTokenLedger(seedFrom: fullMeetings)
                }
            }
        }
    }

    // MARK: - Computed Helpers

    public var isRecording: Bool {
        activeRecordingMeetingID != nil && !isPaused
    }

    public var isRecordingOrPaused: Bool {
        activeRecordingMeetingID != nil
    }

    public var selectedMeeting: MeetingSession? {
        guard let id = selectedMeetingID else { return nil }
        return meetings.first(where: { $0.id == id })
    }

    public var activeRecordingMeeting: MeetingSession? {
        guard let id = activeRecordingMeetingID else { return nil }
        return meetings.first(where: { $0.id == id })
    }

    public var menuBarTimerLabel: String? {
        guard settings.showMenuBarTimer, let meeting = activeRecordingMeeting else { return nil }
        return meeting.formattedDuration
    }

    // MARK: - Setup & Detection

    private func setupDetector() {
        detector.configure(settings: settings) { [weak self] in
            self?.isRecordingOrPaused ?? false
        }
        detector.onMeetingDetected = { [weak self] detected in
            Task { @MainActor in
                guard let self, !self.isRecordingOrPaused else { return }
                self.pendingDetectedMeeting = detected
                self.pendingEndedMeeting = nil
                self.onShowMeetingPrompt?(detected)
            }
        }
        detector.onActiveMeetingEnded = { [weak self] ended in
            Task { @MainActor in
                guard let self, self.isRecordingOrPaused else { return }
                self.pendingEndedMeeting = ended
                self.pendingDetectedMeeting = nil
                self.onShowMeetingEndPrompt?(ended)
            }
        }
        detector.start()
    }

    public func refreshAuthInspection() {
        authInspection = authManager.inspect(settings: settings)
    }

    public func triggerSimulatedMeetingPrompt(appName: String = "腾讯会议") {
        let simulated = DetectedMeetingApp(
            bundleIdentifier: "com.tencent.meeting",
            appName: appName,
            pid: 99999,
            isUsingMicrophone: true,
            isPlayingAudio: true
        )
        pendingDetectedMeeting = simulated
        pendingEndedMeeting = nil
        onShowMeetingPrompt?(simulated)
    }

    public func acceptDetectedMeetingPrompt() {
        let detected = pendingDetectedMeeting
        pendingDetectedMeeting = nil
        onHidePromptPanel?()
        Task {
            await startNewMeeting(from: detected)
            if !settings.showFloatingCapsuleWhileRecording {
                onOpenMainWindow?()
            }
        }
    }

    public func snoozeDetectedMeetingPrompt(minutes: Int = 5) {
        if let detected = pendingDetectedMeeting {
            detector.snoozeMeeting(detected, duration: TimeInterval(minutes * 60))
        }
        pendingDetectedMeeting = nil
        onHidePromptPanel?()
    }

    public func dismissDetectedMeetingPrompt() {
        if let detected = pendingDetectedMeeting {
            detector.dismissCurrentMeeting(detected)
        }
        pendingDetectedMeeting = nil
        onHidePromptPanel?()
    }

    public func ignoreDetectedAppPermanently() {
        if let detected = pendingDetectedMeeting {
            let bid = detected.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            if !bid.isEmpty && !settings.ignoredBundleIDs.contains(where: { $0.caseInsensitiveCompare(bid) == .orderedSame }) {
                settings.ignoredBundleIDs.append(bid)
            }
            detector.dismissCurrentMeeting(detected)
        }
        pendingDetectedMeeting = nil
        onHidePromptPanel?()
    }

    public func dismissEndedMeetingPrompt() {
        pendingEndedMeeting = nil
        onHidePromptPanel?()
    }

    // MARK: - Token Usage Aggregations & Audio Storage Management

    public var todayTokenUsage: TokenUsage {
        let key = MeetingStore.dayKey(for: Date())
        return dailyTokenLedger[key] ?? TokenUsage()
    }

    public var totalTokenUsage: TokenUsage {
        var ledgerTotal = TokenUsage()
        for usage in dailyTokenLedger.values {
            ledgerTotal.add(usage)
        }
        var meetingTotal = TokenUsage()
        for m in meetings {
            meetingTotal.add(m.tokenUsage)
        }
        return ledgerTotal.totalTokens >= meetingTotal.totalTokens ? ledgerTotal : meetingTotal
    }

    func recordDailyTokenUsage(_ usage: TokenUsage) {
        guard !usage.isEmpty else { return }
        dailyTokenLedger = store.recordTokenUsage(usage, on: Date())
    }

    public func resetAllTokenUsage() {
        for idx in meetings.indices {
            meetings[idx].tokenUsage = TokenUsage()
            for msgIdx in meetings[idx].chatHistory.indices {
                meetings[idx].chatHistory[msgIdx].tokenUsage = nil
            }
            store.saveMeeting(meetings[idx])
        }
        store.clearTokenLedger()
        dailyTokenLedger = [:]
    }

    public func refreshAudioStorageStats() {
        audioStorageStats = store.audioStorageStats()
    }

    @discardableResult
    public func pruneAudioBackups(olderThanDays days: Int) -> (removedFiles: Int, freedBytes: Int64) {
        let result = store.pruneAudioBackups(
            olderThanDays: days,
            activeMeetingID: activeRecordingMeetingID,
            meetings: &meetings
        )
        refreshAudioStorageStats()
        if result.removedFiles > 0 {
            let fmt = ByteCountFormatter.string(fromByteCount: result.freedBytes, countStyle: .file)
            statusBannerMessage = L("已清理 \(result.removedFiles) 个录音文件，释放 \(fmt)（文字纪要已保留）", "Removed \(result.removedFiles) audio files, freed \(fmt) (minutes preserved)")
        }
        return result
    }

    public func revealAudioDirectoryInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([store.audioDirectory])
    }

    // MARK: - Editing, Bookmarks & Storage

    public func appendTranscriptSegment(_ segment: TranscriptSegment, to meetingID: UUID) {
        let cleaned = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        updateMeeting(id: meetingID) { m in
            // Avoid accidental duplicate adjacent commit
            if let last = m.segments.last,
               last.speaker == segment.speaker,
               last.text == cleaned,
               abs(last.timestamp - segment.timestamp) < 3.0 {
                return
            }
            var newSeg = segment
            newSeg.text = cleaned
            m.segments.append(newSeg)
        }
    }

    public func addQuickManualNote(_ text: String, to meetingID: UUID) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateMeeting(id: meetingID) { m in
            let prefix = m.status == .recording ? "[\(m.formattedDuration)] " : ""
            if m.manualNotes.isEmpty {
                m.manualNotes = "\(prefix)\(trimmed)"
            } else {
                m.manualNotes += "\n\(prefix)\(trimmed)"
            }
        }
    }

    public func toggleStarSegment(meetingID: UUID, segmentID: UUID) {
        updateMeeting(id: meetingID) { m in
            if let idx = m.segments.firstIndex(where: { $0.id == segmentID }) {
                m.segments[idx].isStarred.toggle()
            }
        }
    }

    public func toggleActionItem(meetingID: UUID, actionID: UUID) {
        updateMeeting(id: meetingID) { m in
            if let idx = m.minutes.actionItems.firstIndex(where: { $0.id == actionID }) {
                m.minutes.actionItems[idx].isCompleted.toggle()
            }
        }
    }

    public func updateMeeting(id: UUID, persist: Bool = true, _ mutate: (inout MeetingSession) -> Void) {
        ensureMeetingLoaded(id: id)
        guard let idx = meetings.firstIndex(where: { $0.id == id }) else { return }
        hydratedMeetingIDs.insert(id)
        mutate(&meetings[idx])
        if persist {
            store.saveMeetingAsync(meetings[idx])
        }
    }

    public func deleteMeeting(_ meeting: MeetingSession) {
        if activeRecordingMeetingID == meeting.id {
            Task { await stopRecordingAndFinalize(generateFinalSummary: false) }
        }
        store.deleteMeeting(meeting)
        meetings.removeAll { $0.id == meeting.id }
        if selectedMeetingID == meeting.id {
            selectedMeetingID = nil
        }
        refreshAudioStorageStats()
    }

    public func createMeetingFromPastedText(title: String, rawText: String) async {
        let cleaned = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        let lines = cleaned
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let segments = lines.enumerated().map { idx, line in
            TranscriptSegment(
                timestamp: TimeInterval(idx * 10),
                speaker: .mixed,
                text: line
            )
        }

        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let session = MeetingSession(
            title: cleanTitle.isEmpty ? L("新纪要", "New Minutes") : cleanTitle,
            sourceAppName: L("文本导入", "Pasted Text"),
            startedAt: Date(),
            endedAt: Date(),
            duration: 0,
            status: .summarizing,
            segments: segments
        )

        meetings.insert(session, at: 0)
        selectedMeetingID = session.id
        store.saveMeeting(session)

        await refreshMinutesNow(for: session.id, isFinal: true)
        updateMeeting(id: session.id) { $0.status = .completed }
    }

    public func createSampleMeetingForDemo() {
        let now = Date()
        let demo = MeetingSession(
            title: L("Sonote 端侧 MLX 语音与声纹评审会（示例）", "Sonote On-Device MLX Architecture Review (Sample)"),
            sourceAppName: L("腾讯会议", "Zoom"),
            sourceBundleId: "com.tencent.meeting",
            startedAt: now.addingTimeInterval(-1260),
            endedAt: now,
            duration: 1260,
            status: .completed,
            segments: [
                TranscriptSegment(timestamp: 12, speaker: .remote, text: "大家好，今天我们主要过一下 Apple Silicon 端侧智能会议纪要的核心架构与体验。"),
                TranscriptSegment(timestamp: 38, speaker: .me, text: "核心痛点有两个：一是加入腾讯会议或飞书后自动弹窗提醒，免得忘记录音；二是系统声音和麦克风双轨分离采集。"),
                TranscriptSegment(timestamp: 85, speaker: .remote, text: "对，而且会中需要边听边提炼思维导图和待办事项，同时支持 DeepSeek、通义千问和内置离线 MLX 模型一键切换。"),
                TranscriptSegment(timestamp: 142, speaker: .me, text: "没问题，我们用 CoreAudio Process Tap + MLX Qwen3-ASR 实现 100% 本地语音转写，周五前完成发版测试。")
            ],
            manualNotes: "重点：确保所有 API 密钥仅存入 macOS Keychain，绝不落盘明文。",
            minutes: SmartMinutes(
                suggestedTitle: L("Sonote 端侧 MLX 语音与声纹评审会", "Sonote On-Device MLX Architecture Review"),
                overview: "本次会议明确了 Apple Silicon 端侧智能会议纪要工具的核心范围，聚焦自动会议检测、双通道音频采集、会中实时思维导图提炼及国产/离线多模型接入。",
                topics: [
                    TopicSection(title: "自动会议检测与无感启动", points: [
                        "加入腾讯会议、飞书、Zoom 等线上会议后自动在桌面右上角弹出轻量提醒卡片。",
                        "支持一键开启、稍后提醒或将该应用加入永久忽略列表。"
                    ]),
                    TopicSection(title: "双通道采集与会中实时记录", points: [
                        "采用 CoreAudio Process Tap 采集系统声音（远端参会人）并同步采集本机麦克风（我）。",
                        "会中增量提炼议题要点、决议与待办，并支持会中随手记与 AI 追问。"
                    ]),
                    TopicSection(title: "国产大模型与离线 MLX 策略", points: [
                        "原生接入 DeepSeek、通义千问 Qwen、OpenAI、Claude、Gemini 及内置离线 Qwen2.5 MLX 模型，密钥统一由 macOS Keychain 加密保管。"
                    ])
                ],
                decisions: [
                    "采用原生 SwiftUI + CoreAudio Process Tap + Apple Silicon MLX 架构，零虚拟声卡驱动与外部进程。",
                    "会后支持一键同步 Obsidian / 本地 Markdown 目录以及飞书/钉钉 Webhook 推送。"
                ],
                actionItems: [
                    ActionItem(task: "完成端侧 MLX 语音管线与音频热切换联调", owner: "我", dueDate: "本周五"),
                    ActionItem(task: "验证腾讯会议 / 飞书自动检测与悬浮胶囊展开体验", owner: "产品与测试", dueDate: "下周一")
                ],
                openQuestions: [
                    "后续版本是否引入 Apple Developer ID 公证以进一步简化安装流程？"
                ],
                participants: ["我", "产品负责人"],
                lastUpdatedAt: now,
                isFinalized: true
            )
        )
        meetings.insert(demo, at: 0)
        selectedMeetingID = demo.id
        store.saveMeeting(demo)
    }
}
