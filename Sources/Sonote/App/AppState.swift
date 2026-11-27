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
            ThemeManager.shared.sync(with: settings)
            store.saveSettings(settings)
            refreshAuthInspection()
            detector.configure(settings: settings) { [weak self] in
                self?.isRecordingOrPaused ?? false
            }
            GlobalHotKeyService.shared.configure(
                enabled: settings.enableGlobalHotKeys,
                preset: settings.globalHotKeyPreset
            )
        }
    }

    @Published public var authInspection: AuthInspectionResult
    @Published public var meetings: [MeetingSession] = []
    @Published public var selectedMeetingID: UUID?
    @Published public var activeRecordingMeetingID: UUID?
    @Published public var dailyTokenLedger: [String: TokenUsage] = [:]
    @Published public var audioStorageStats: AudioStorageStats = AudioStorageStats()
    @Published public var voiceprints: [VoiceprintProfile] = []

    // Live audio capture status & meters
    @Published public var isPaused: Bool = false
    @Published public var systemAudioActive: Bool = false
    @Published public var micAudioActive: Bool = false
    @Published public var systemAudioLevel: Float = 0
    @Published public var micAudioLevel: Float = 0

    // Live volatile streaming transcription
    @Published public var volatileRemoteText: String = ""
    @Published public var volatileMeText: String = ""
    @Published public var mlxModelState: MLXModelState = .idle

    // AI generation & background job state
    @Published public var isGeneratingMinutes: Bool = false
    @Published public var isAskingAI: Bool = false
    @Published public var isDiarizing: Bool = false
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

    // Floating capsule visibility
    @Published public var isCapsuleVisible: Bool = false

    // MARK: - Services

    private let store = MeetingStore.shared
    private let voiceprintStore = VoiceprintStore.shared
    private let authManager = AuthManager.shared
    private let gptClient = GPTClient.shared
    private let audioManager = DualAudioCaptureManager()
    private let transcriptionCoordinator = TranscriptionCoordinator()
    private let detector = MeetingDetector()

    private var durationTimer: Timer?
    private var liveSummaryTimer: Timer?
    private var lastSummarizedCharCount: Int = 0
    private var lastSummarizedSegmentCount: Int = 0
    private var lastSummarizedManualNotes: String = ""
    private var activeAskAITask: Task<Void, Never>?
    private var activeRecordingStartDate: Date?
    private var accumulatedPausedSeconds: TimeInterval = 0
    private var pauseStartedAt: Date?

    // Callbacks wired by AppDelegate / SwiftUI for NSPanel & main NSWindow management
    public weak var trackedMainWindow: NSWindow?
    public var swiftUIOpenMainWindow: (() -> Void)?
    public var onShowMeetingPrompt: ((DetectedMeetingApp) -> Void)?
    public var onShowMeetingEndPrompt: ((DetectedMeetingApp) -> Void)?
    public var onHidePromptPanel: (() -> Void)?
    public var onUpdateCapsuleVisibility: ((Bool) -> Void)?
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
        let loadedMeetings = MeetingStore.shared.loadMeetings()
        self.meetings = loadedMeetings
        self.dailyTokenLedger = MeetingStore.shared.loadTokenLedger(seedFrom: loadedMeetings)
        self.audioStorageStats = MeetingStore.shared.audioStorageStats()
        self.voiceprints = VoiceprintStore.shared.loadProfiles()
        // Land on the clean Home page on launch instead of jumping directly into an old recording
        self.selectedMeetingID = nil

        setupDetector()
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

    // MARK: - Meeting Lifecycle

    public func startNewMeeting(from detectedApp: DetectedMeetingApp? = nil) async {
        if isRecordingOrPaused {
            await stopRecordingAndFinalize(generateFinalSummary: false)
        }

        runtimeWarnings = []
        statusBannerMessage = nil
        volatileRemoteText = ""
        volatileMeText = ""
        lastSummarizedCharCount = 0
        lastSummarizedSegmentCount = 0
        lastSummarizedManualNotes = ""
        accumulatedPausedSeconds = 0
        pauseStartedAt = nil

        let now = Date()
        var calendarContext: CalendarMeetingContext? = nil
        if settings.enableCalendarIntegration {
            calendarContext = CalendarContextService.shared.currentMeetingContext(at: now)
        }

        let title = calendarContext?.title ?? detectedApp?.appName ?? "新录音"
        let calendarAttendees = calendarContext?.attendees ?? []
        let calendarHotwords = calendarContext?.asrHotwordHint ?? ""
        let combinedHotwords = [calendarHotwords, combinedVoiceprintHotwords]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")

        let session = MeetingSession(
            title: title,
            sourceAppName: detectedApp?.appName ?? "新录音",
            sourceBundleId: detectedApp?.bundleIdentifier,
            startedAt: now,
            status: .recording,
            template: settings.defaultMinutesTemplate,
            calendarAttendees: calendarAttendees
        )

        meetings.insert(session, at: 0)
        selectedMeetingID = session.id
        activeRecordingMeetingID = session.id
        activeRecordingStartDate = now
        isPaused = false
        store.saveMeeting(session)
        detector.markRecordingStarted(for: detectedApp)

        // Wire audio buffers -> meters + transcriber
        audioManager.onSystemBuffer = { [weak self] buffer, level in
            self?.transcriptionCoordinator.feedSystemAudio(buffer)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.systemAudioLevel = self.systemAudioLevel * 0.45 + level * 0.55
            }
        }
        audioManager.onMicBuffer = { [weak self] buffer, level in
            self?.transcriptionCoordinator.feedMicrophoneAudio(buffer)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.micAudioLevel = self.micAudioLevel * 0.45 + level * 0.55
            }
        }
        audioManager.onDeviceRouteChanged = { [weak self] notice in
            Task { @MainActor [weak self] in
                self?.statusBannerMessage = notice
            }
        }

        let backupURL = settings.saveAudioBackup ? store.audioBackupURL(for: session.id) : nil
        let report = await audioManager.start(mode: settings.audioCaptureMode, saveBackupTo: backupURL)
        systemAudioActive = report.systemAudioActive
        micAudioActive = report.microphoneActive
        runtimeWarnings.append(contentsOf: report.warnings)

        if let audioPath = report.backupFilePath {
            updateMeeting(id: session.id) { $0.audioFilePath = audioPath }
        }

        // Wire transcription callbacks
        transcriptionCoordinator.onVolatileUpdate = { [weak self] speaker, text in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch speaker {
                case .remote, .mixed: self.volatileRemoteText = text
                case .me: self.volatileMeText = text
                }
            }
        }
        transcriptionCoordinator.onCommittedSegment = { [weak self] segment in
            Task { @MainActor [weak self] in
                guard let self, let activeID = self.activeRecordingMeetingID else { return }
                self.appendTranscriptSegment(segment, to: activeID)
            }
        }
        transcriptionCoordinator.onStatusNotice = { [weak self] msg in
            Task { @MainActor [weak self] in
                self?.statusBannerMessage = msg
            }
        }
        transcriptionCoordinator.onMLXModelStateChange = { [weak self] state in
            Task { @MainActor [weak self] in
                self?.mlxModelState = state
            }
        }

        if report.hasAnySource {
            let notices = await transcriptionCoordinator.start(
                settings: settings,
                captureRemote: report.systemAudioActive,
                captureMic: report.microphoneActive,
                sessionStartDate: now,
                extraContextHint: combinedHotwords,
                voiceprintProfiles: voiceprints
            )
            runtimeWarnings.append(contentsOf: notices)
        } else {
            runtimeWarnings.append("未能开启任何音频源（系统声音或麦克风）。请授予对应系统权限后重试，或先使用手动笔记。")
        }

        startTimers()

        if settings.showFloatingCapsuleWhileRecording {
            collapseToTopLeftMiniWindow()
        }
    }

    public func togglePauseRecording() {
        guard let activeID = activeRecordingMeetingID else { return }
        isPaused.toggle()
        audioManager.setPaused(isPaused)
        if isPaused {
            pauseStartedAt = Date()
            systemAudioLevel = 0
            micAudioLevel = 0
            updateMeeting(id: activeID) { $0.status = .paused }
        } else {
            if let pauseStartedAt {
                accumulatedPausedSeconds += Date().timeIntervalSince(pauseStartedAt)
            }
            pauseStartedAt = nil
            updateMeeting(id: activeID) { $0.status = .recording }
        }
    }

    public func stopRecordingAndFinalize(generateFinalSummary: Bool = true) async {
        guard let activeID = activeRecordingMeetingID else { return }

        stopTimers()
        pendingEndedMeeting = nil
        onHidePromptPanel?()
        setCapsuleVisible(false)

        audioManager.stop()
        refreshAudioStorageStats()
        await transcriptionCoordinator.stop()

        // Compute exact elapsed duration before resetting timers
        let exactElapsed: TimeInterval
        if let startDate = activeRecordingStartDate {
            let extraPause = pauseStartedAt.map { Date().timeIntervalSince($0) } ?? 0
            exactElapsed = max(0, Date().timeIntervalSince(startDate) - accumulatedPausedSeconds - extraPause)
        } else {
            exactElapsed = activeRecordingMeeting?.duration ?? 0
        }

        // Commit any leftover volatile text if substantial
        let leftRemote = volatileRemoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !leftRemote.isEmpty {
            appendTranscriptSegment(TranscriptSegment(timestamp: exactElapsed, speaker: .remote, text: leftRemote), to: activeID)
        }
        let leftMe = volatileMeText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !leftMe.isEmpty {
            appendTranscriptSegment(TranscriptSegment(timestamp: exactElapsed, speaker: .me, text: leftMe), to: activeID)
        }

        volatileRemoteText = ""
        volatileMeText = ""
        systemAudioActive = false
        micAudioActive = false
        systemAudioLevel = 0
        micAudioLevel = 0
        isPaused = false
        activeRecordingMeetingID = nil
        activeRecordingStartDate = nil
        detector.resetAfterRecordingStopped()

        let hasContent: Bool = {
            guard let m = meetings.first(where: { $0.id == activeID }) else { return false }
            return !m.segments.isEmpty || !m.manualNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }()

        let shouldSummarize = generateFinalSummary && hasContent

        updateMeeting(id: activeID) { m in
            m.duration = exactElapsed
            m.endedAt = Date()
            m.status = shouldSummarize ? .summarizing : .completed
        }

        // Bring main window forward to show the finished summary document
        selectedMeetingID = activeID
        onOpenMainWindow?()

        if shouldSummarize {
            await refreshMinutesNow(for: activeID, isFinal: true)
            updateMeeting(id: activeID) { $0.status = .completed }
        }
    }

    public func setCapsuleVisible(_ visible: Bool) {
        isCapsuleVisible = visible
        onUpdateCapsuleVisibility?(visible)
    }

    public func collapseToTopLeftMiniWindow() {
        setCapsuleVisible(true)
        onHideMainWindow?()
    }

    public func expandFromMiniWindowToMain() {
        if let activeID = activeRecordingMeetingID {
            selectedMeetingID = activeID
        }
        // Open and focus main workspace window first, then tear down the floating HUD on the next tick
        // so the button's mouseUp inside FloatingHUDPanel finishes cleanly.
        onOpenMainWindow?()
        DispatchQueue.main.async { [weak self] in
            self?.setCapsuleVisible(false)
        }
    }

    // MARK: - Timers & Periodic In-Meeting Smart Notes

    private func startTimers() {
        stopTimers()

        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self,
                      let activeID = self.activeRecordingMeetingID,
                      let startDate = self.activeRecordingStartDate,
                      !self.isPaused else { return }
                let elapsed = max(0, Date().timeIntervalSince(startDate) - self.accumulatedPausedSeconds)
                self.updateMeeting(id: activeID, persist: false) { $0.duration = elapsed }
            }
        }

        let interval = max(15, TimeInterval(settings.liveSummaryIntervalSeconds))
        liveSummaryTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.triggerLiveMinutesIfNeeded()
            }
        }
    }

    private func stopTimers() {
        durationTimer?.invalidate()
        durationTimer = nil
        liveSummaryTimer?.invalidate()
        liveSummaryTimer = nil
    }

    private func triggerLiveMinutesIfNeeded() async {
        guard settings.liveSummaryEnabled,
              !isGeneratingMinutes,
              !isPaused,
              let activeID = activeRecordingMeetingID,
              let meeting = meetings.first(where: { $0.id == activeID }) else {
            return
        }

        let currentCharCount = meeting.segments.reduce(0) { $0 + $1.text.count }
        let notesChanged = meeting.manualNotes != lastSummarizedManualNotes
            && !meeting.manualNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasEnoughNewSpeech = (currentCharCount - lastSummarizedCharCount) >= 25

        guard hasEnoughNewSpeech || notesChanged else { return }
        await refreshMinutesNow(for: activeID, isFinal: false)
    }

    // MARK: - AI Smart Minutes & Interactive Q&A

    public func refreshMinutesNow(for meetingID: UUID, isFinal: Bool) async {
        guard let meeting = meetings.first(where: { $0.id == meetingID }) else { return }
        let hasTranscript = !meeting.segments.isEmpty
        let hasNotes = !meeting.manualNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasTranscript || hasNotes else {
            statusBannerMessage = "暂无转写内容或手动笔记，开始说话后即可自动提炼智能纪要。"
            return
        }

        isGeneratingMinutes = true
        aiStreamingPreview = ""
        statusBannerMessage = isFinal ? "正在调用 GPT 生成完整智能会议纪要..." : "正在实时更新会中纪要要点..."

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
                // Auto-upgrade default generic title once GPT identifies the real topic
                if !merged.suggestedTitle.isEmpty,
                   (m.title == "新录音" || m.title == m.sourceAppName || m.title.contains(" · ") || m.title.hasPrefix("会议记录")) {
                    m.title = merged.suggestedTitle
                }
            }
            recordDailyTokenUsage(usage)
            statusBannerMessage = isFinal ? "智能会议纪要已生成" : "实时纪要已更新"
        } catch {
            statusBannerMessage = "GPT 生成纪要失败：\(error.localizedDescription)"
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
                            m.chatHistory[idx].content = "⚠️ 请求失败：\(error.localizedDescription)"
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

    private func persistCancelledAskAI(meetingID: UUID, assistantMsgID: UUID) {
        updateMeeting(id: meetingID) { m in
            guard let idx = m.chatHistory.firstIndex(where: { $0.id == assistantMsgID }) else { return }
            let trimmed = m.chatHistory[idx].content.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                m.chatHistory[idx].content = "（已停止生成）"
            }
        }
    }

    public func cancelAskAI() {
        activeAskAITask?.cancel()
        activeAskAITask = nil
        isAskingAI = false
    }

    // MARK: - Local Audio/Video Import & Multi-Speaker Diarization

    public func importMediaFile(url: URL) async {
        guard importProgress == nil else { return }
        let fileName = url.deletingPathExtension().lastPathComponent
        importProgress = AudioFileImportProgress(fraction: 0.02, message: "准备导入「\(fileName)」...")

        let sessionID = UUID()
        let baseBackupURL = store.audioBackupURL(for: sessionID)
        var savedMediaURL: URL?

        do {
            importProgress = AudioFileImportProgress(fraction: 0.04, message: "正在提取音频轨道...")
            let preparedURL = try await AudioFileImporter.preparePlayableAudioBackup(
                from: url,
                destinationBaseURL: baseBackupURL
            )
            savedMediaURL = preparedURL

            let (segments, duration) = try await AudioFileImporter.transcribeMediaFile(
                url: preparedURL,
                settings: settings,
                extraHotwords: combinedVoiceprintHotwords,
                voiceprintProfiles: voiceprints,
                onProgress: { [weak self] prog in
                    Task { @MainActor [weak self] in
                        self?.importProgress = prog
                    }
                },
                onMLXState: { [weak self] state in
                    Task { @MainActor [weak self] in
                        self?.mlxModelState = state
                    }
                }
            )

            let session = MeetingSession(
                id: sessionID,
                title: fileName.isEmpty ? "导入录音" : fileName,
                sourceAppName: "文件导入",
                startedAt: Date(),
                endedAt: Date(),
                duration: duration,
                status: segments.isEmpty ? .completed : .summarizing,
                segments: segments,
                audioFilePath: preparedURL.path,
                template: settings.defaultMinutesTemplate
            )

            meetings.insert(session, at: 0)
            selectedMeetingID = session.id
            store.saveMeeting(session)
            refreshAudioStorageStats()
            importProgress = nil

            if !segments.isEmpty {
                await refreshMinutesNow(for: session.id, isFinal: true)
                updateMeeting(id: session.id) { $0.status = .completed }
            }
        } catch {
            if let savedMediaURL {
                try? FileManager.default.removeItem(at: savedMediaURL)
            }
            importProgress = nil
            statusBannerMessage = "导入音视频失败：\(error.localizedDescription)"
        }
    }

    public var combinedVoiceprintHotwords: String {
        var terms: [String] = []
        let local = settings.localUserName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !local.isEmpty { terms.append(local) }
        for term in settings.glossaryTerms {
            let clean = term.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty && !terms.contains(clean) {
                terms.append(clean)
            }
        }
        for vp in voiceprints {
            let clean = vp.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty && !terms.contains(clean) {
                terms.append(clean)
            }
        }
        return terms.prefix(40).joined(separator: ", ")
    }

    public func runSpeakerDiarization(for meetingID: UUID) async {
        guard !isDiarizing,
              let meeting = meetings.first(where: { $0.id == meetingID }),
              let audioPath = meeting.audioFilePath,
              FileManager.default.fileExists(atPath: audioPath) else {
            return
        }

        isDiarizing = true
        let useVoiceprints = settings.autoIdentifyVoiceprints && !voiceprints.isEmpty
        if settings.diarizationStrategy == .voiceprintClusteringUnlimited {
            statusBannerMessage = "正在通过 ECAPA 声纹聚类识别多说话人（突破 4 人上限）..."
        } else {
            statusBannerMessage = useVoiceprints
                ? "正在通过 Sortformer + 本地声纹库识别说话人..."
                : "正在通过 Sortformer 识别多说话人..."
        }
        do {
            let (samples, decodedDur) = try await AudioFileImporter.decodeToMono16kSamples(url: URL(fileURLWithPath: audioPath))
            if settings.diarizationStrategy == .voiceprintClusteringUnlimited {
                let result = await SpeakerDiarizerService.diarizeByVoiceprintClustering(
                    segments: meeting.segments,
                    fullSamples16k: samples,
                    meetingDuration: max(meeting.duration, decodedDur),
                    profiles: useVoiceprints ? voiceprints : [],
                    matchThreshold: settings.voiceprintMatchThreshold,
                    voiceprintModelID: settings.voiceprintModelID,
                    hfHost: settings.mlxHuggingFaceHost,
                    localUserName: settings.localUserName,
                    autoUnloadVoiceprintModel: settings.mlxAutoUnloadAfterMeeting
                )
                updateMeeting(id: meetingID) { $0.segments = result.segments }
                if !result.matchedVoiceprintNames.isEmpty {
                    statusBannerMessage = "ECAPA 聚类已识别 \(result.totalRemoteSpeakersDetected) 位说话人，声纹匹配：\(result.matchedVoiceprintNames.joined(separator: "、"))"
                } else {
                    statusBannerMessage = "ECAPA 聚类已分离 \(result.totalRemoteSpeakersDetected) 位说话人（点击说话人名可改名并建档）"
                }
            } else {
                let diarization = try await SpeakerDiarizerService.shared.diarize(
                    samples16k: samples,
                    modelID: settings.diarizationModelID,
                    hfHost: settings.mlxHuggingFaceHost
                )
                if useVoiceprints {
                    let result = await SpeakerDiarizerService.assignSpeakerLabelsWithVoiceprints(
                        segments: meeting.segments,
                        diarization: diarization,
                        fullSamples16k: samples,
                        profiles: voiceprints,
                        matchThreshold: settings.voiceprintMatchThreshold,
                        voiceprintModelID: settings.voiceprintModelID,
                        hfHost: settings.mlxHuggingFaceHost,
                        localUserName: settings.localUserName,
                        autoUnloadVoiceprintModel: settings.mlxAutoUnloadAfterMeeting
                    )
                    updateMeeting(id: meetingID) { $0.segments = result.segments }
                    if !result.matchedVoiceprintNames.isEmpty {
                        statusBannerMessage = "已分离 \(result.totalRemoteSpeakersDetected) 位说话人，声纹匹配：\(result.matchedVoiceprintNames.joined(separator: "、"))"
                    } else {
                        statusBannerMessage = "已完成多说话人分离（未命中已建档声纹，可点击说话人名改名并记住声纹）"
                    }
                } else {
                    let updatedSegments = SpeakerDiarizerService.assignSpeakerLabels(
                        segments: meeting.segments,
                        diarization: diarization,
                        localUserName: settings.localUserName
                    )
                    updateMeeting(id: meetingID) { $0.segments = updatedSegments }
                    statusBannerMessage = "已完成多说话人声纹分离"
                }
                if settings.mlxAutoUnloadAfterMeeting {
                    await SpeakerDiarizerService.shared.unload()
                }
            }
        } catch {
            statusBannerMessage = "多说话人识别失败：\(error.localizedDescription)"
        }
        isDiarizing = false
    }

    public func inferSpeakerNamesWithAI(for meetingID: UUID) async {
        guard !isInferringSpeakers,
              let meeting = meetings.first(where: { $0.id == meetingID }) else { return }
        isInferringSpeakers = true
        statusBannerMessage = "正在结合会议上下文推断说话人姓名..."
        do {
            var candidates = meeting.calendarAttendees + voiceprints.map(\.name)
            let local = settings.localUserName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !local.isEmpty { candidates.append(local) }

            let (mapping, usage) = try await gptClient.inferSpeakerNames(
                for: meeting,
                candidateNames: candidates,
                settings: settings
            )
            if !usage.isEmpty {
                updateMeeting(id: meetingID) { $0.tokenUsage.add(usage) }
                recordDailyTokenUsage(usage)
            }
            if mapping.isEmpty {
                statusBannerMessage = "对话中暂无足够姓名线索，可点击说话人标签手动命名"
            } else {
                updateMeeting(id: meetingID) { m in
                    for (oldName, newName) in mapping {
                        m.renameSpeaker(from: oldName, to: newName, onlySegmentID: nil, updateMinutes: true)
                    }
                }
                let summary = mapping.map { "\($0.key)→\($0.value)" }.joined(separator: "，")
                statusBannerMessage = "AI 已推断说话人姓名：\(summary)"
            }
        } catch {
            statusBannerMessage = "AI 推断姓名失败：\(error.localizedDescription)"
        }
        isInferringSpeakers = false
    }

    /// Renames a speaker in a meeting transcript (single segment or all matching segments),
    /// optionally syncing minutes text and enrolling the speaker's audio into the local ECAPA voiceprint library.
    public func renameSpeaker(
        meetingID: UUID,
        oldName: String,
        newName: String,
        onlySegmentID: UUID?,
        updateMinutes: Bool,
        enrollVoiceprint: Bool
    ) async {
        let cleanNew = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanNew.isEmpty else { return }

        // Collect intervals BEFORE mutating if we are enrolling voiceprint
        var intervalsToEnroll: [(start: TimeInterval, end: TimeInterval)] = []
        var audioPathForEnroll: String? = nil
        if enrollVoiceprint, let meeting = meetings.first(where: { $0.id == meetingID }),
           let path = meeting.audioFilePath, FileManager.default.fileExists(atPath: path) {
            audioPathForEnroll = path
            let segs = meeting.segments
            for idx in segs.indices {
                let seg = segs[idx]
                let matchesTarget: Bool
                if let onlyID = onlySegmentID {
                    matchesTarget = seg.id == onlyID
                } else {
                    matchesTarget = seg.resolvedSpeakerName == oldName
                }
                guard matchesTarget else { continue }
                let nextStart: TimeInterval = (idx + 1 < segs.count)
                    ? segs[idx + 1].timestamp
                    : max(seg.timestamp + 6.0, meeting.duration)
                let estEnd = min(nextStart, seg.timestamp + 12.0)
                if estEnd - seg.timestamp >= 0.8 {
                    intervalsToEnroll.append((start: seg.timestamp, end: estEnd))
                }
            }
        }

        updateMeeting(id: meetingID) { m in
            m.renameSpeaker(
                from: oldName,
                to: cleanNew,
                onlySegmentID: onlySegmentID,
                updateMinutes: updateMinutes
            )
        }

        if enrollVoiceprint, let audioPath = audioPathForEnroll, !intervalsToEnroll.isEmpty {
            isEnrollingVoiceprint = true
            statusBannerMessage = "正在提取「\(cleanNew)」声纹并写入本地声纹库..."
            do {
                let (fullSamples, _) = try await AudioFileImporter.decodeToMono16kSamples(url: URL(fileURLWithPath: audioPath))
                let speakerSamples = VoiceprintService.extractSpeakerSamples(
                    from: fullSamples,
                    intervals: intervalsToEnroll,
                    maxDurationSeconds: 14.0
                )
                let embedding = try await VoiceprintService.shared.extractEmbedding(
                    samples16k: speakerSamples,
                    modelID: settings.voiceprintModelID,
                    hfHost: settings.mlxHuggingFaceHost
                )
                voiceprints = voiceprintStore.upsertProfile(name: cleanNew, embedding: embedding)
                if settings.mlxAutoUnloadAfterMeeting {
                    await VoiceprintService.shared.unload()
                }
                statusBannerMessage = "已保存「\(cleanNew)」声纹，下次会议将自动识别"
            } catch {
                statusBannerMessage = "已改名为「\(cleanNew)」，但声纹提取失败：\(error.localizedDescription)"
            }
            isEnrollingVoiceprint = false
        }
    }

    public func updateSegmentText(meetingID: UUID, segmentID: UUID, newText: String) {
        let cleaned = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        updateMeeting(id: meetingID) { m in
            if let idx = m.segments.firstIndex(where: { $0.id == segmentID }) {
                m.segments[idx].text = cleaned
            }
        }
    }

    // MARK: - Local Voiceprint Library Enrollment & Management

    public func enrollVoiceprintFromLiveMic(name: String, role: String = "", isSelf: Bool = false) async {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !isEnrollingVoiceprint else { return }

        isEnrollingVoiceprint = true
        voiceprintEnrollProgress = 0
        voiceprintEnrollLevel = 0
        voiceprintStatusMessage = "请对着麦克风自然朗读 5 秒..."

        let recorder = VoiceprintEnrollmentRecorder()
        do {
            let samples = try await recorder.recordSample(durationSeconds: 5.0) { [weak self] prog, level in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.voiceprintEnrollProgress = prog
                    if level > 0 {
                        self.voiceprintEnrollLevel = self.voiceprintEnrollLevel * 0.4 + level * 0.6
                    }
                }
            }
            voiceprintStatusMessage = "正在通过 ECAPA-TDNN 提取 192 维声纹特征..."
            let embedding = try await VoiceprintService.shared.extractEmbedding(
                samples16k: samples,
                modelID: settings.voiceprintModelID,
                hfHost: settings.mlxHuggingFaceHost
            )
            voiceprints = voiceprintStore.upsertProfile(
                name: cleanName,
                role: role,
                embedding: embedding,
                isSelf: isSelf
            )
            if isSelf && settings.localUserName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                settings.localUserName = cleanName
            }
            if settings.mlxAutoUnloadAfterMeeting {
                await VoiceprintService.shared.unload()
            }
            voiceprintStatusMessage = "已成功录入「\(cleanName)」声纹"
        } catch {
            voiceprintStatusMessage = "声纹录入失败：\(error.localizedDescription)"
        }
        voiceprintEnrollProgress = 0
        voiceprintEnrollLevel = 0
        isEnrollingVoiceprint = false
    }

    public func enrollVoiceprintFromAudioFile(url: URL, name: String, role: String = "", isSelf: Bool = false) async {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !isEnrollingVoiceprint else { return }

        isEnrollingVoiceprint = true
        voiceprintStatusMessage = "正在从音频文件提取「\(cleanName)」声纹..."
        do {
            let (samples, _) = try await AudioFileImporter.decodeToMono16kSamples(url: url)
            let embedding = try await VoiceprintService.shared.extractEmbedding(
                samples16k: samples,
                modelID: settings.voiceprintModelID,
                hfHost: settings.mlxHuggingFaceHost
            )
            voiceprints = voiceprintStore.upsertProfile(
                name: cleanName,
                role: role,
                embedding: embedding,
                isSelf: isSelf
            )
            if isSelf && settings.localUserName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                settings.localUserName = cleanName
            }
            if settings.mlxAutoUnloadAfterMeeting {
                await VoiceprintService.shared.unload()
            }
            voiceprintStatusMessage = "已从文件成功建档「\(cleanName)」声纹"
        } catch {
            voiceprintStatusMessage = "音频声纹建档失败：\(error.localizedDescription)"
        }
        isEnrollingVoiceprint = false
    }

    public func renameVoiceprint(id: UUID, newName: String, newRole: String? = nil) {
        voiceprints = voiceprintStore.renameProfile(id: id, newName: newName, newRole: newRole)
    }

    public func deleteVoiceprint(id: UUID) {
        voiceprints = voiceprintStore.deleteProfile(id: id)
    }

    public func preloadSpeechEnhancementModel() async {
        guard !isPreloadingDenoiser else { return }
        isPreloadingDenoiser = true
        statusBannerMessage = "正在下载并加载 DeepFilterNet3 降噪模型..."
        let loaded = await SpeechEnhancementService.shared.ensureLoaded(
            modelID: settings.speechEnhancementModelID,
            hfHost: settings.mlxHuggingFaceHost
        )
        statusBannerMessage = loaded != nil
            ? "DeepFilterNet3 降噪模型已就绪"
            : "DeepFilterNet3 模型加载失败，将自动使用轻量 DSP 降噪"
        isPreloadingDenoiser = false
    }

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
        statusBannerMessage = "已复制富文本纪要（可直接粘贴到飞书文档 / 邮件）"
    }

    public func setTemplate(_ template: MinutesTemplate, for meetingID: UUID, regenerate: Bool = false) {
        updateMeeting(id: meetingID) {
            $0.template = template
            $0.customTemplateID = nil
        }
        if regenerate {
            Task { await refreshMinutesNow(for: meetingID, isFinal: true) }
        }
    }

    public func setCustomTemplate(_ custom: CustomMinutesTemplate, for meetingID: UUID, regenerate: Bool = false) {
        updateMeeting(id: meetingID) { $0.customTemplateID = custom.id }
        if regenerate {
            Task { await refreshMinutesNow(for: meetingID, isFinal: true) }
        }
    }

    public func addCustomTemplate(name: String, guidance: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanGuidance = guidance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !cleanGuidance.isEmpty else { return }
        settings.customTemplates.append(CustomMinutesTemplate(name: cleanName, promptGuidance: cleanGuidance))
    }

    public func deleteCustomTemplate(id: UUID) {
        settings.customTemplates.removeAll { $0.id == id }
    }

    // MARK: - Meeting Tags, Global Action Items, Reminders Sync, Cross-Meeting AI & PDF Export

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
            let msg = count > 0 ? "已同步 \(count) 条待办到 macOS「提醒事项」" : "没有需要同步的未完成待办"
            statusBannerMessage = msg
            return msg
        } catch {
            let msg = "同步提醒事项失败：\(error.localizedDescription)"
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
            return ("⚠️ 跨会议分析请求失败：\(error.localizedDescription)", TokenUsage())
        }
    }

    public func exportPDFWithSavePanel(for meeting: MeetingSession, includeTranscript: Bool = false) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        let safeName = meeting.title.replacingOccurrences(of: "/", with: "-")
        panel.nameFieldStringValue = "\(safeName).pdf"
        panel.title = "导出智能会议纪要 (PDF)"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try MeetingPDFExporter.exportPDF(for: meeting, includeTranscript: includeTranscript, to: url)
                statusBannerMessage = "已导出 PDF 至 \(url.lastPathComponent)"
            } catch {
                statusBannerMessage = "导出 PDF 失败：\(error.localizedDescription)"
            }
        }
    }

    // MARK: - Webhook Push, Built-In Local MLX LLM & Full Data Backup

    public func pushMeetingToWebhook(_ meeting: MeetingSession) async -> (success: Bool, message: String) {
        guard !isPushingWebhook else { return (false, "正在推送中...") }
        isPushingWebhook = true
        defer { isPushingWebhook = false }
        do {
            try await WebhookPushService.shared.push(
                meeting: meeting,
                provider: settings.webhookProvider,
                webhookURL: settings.webhookURL,
                secret: settings.webhookSecret
            )
            let msg = "已推送「\(meeting.title)」到 \(settings.webhookProvider.displayName)"
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
            title: "Sonote（声记）Webhook 连通性测试",
            sourceAppName: "Sonote v1.5",
            duration: 60,
            status: .completed,
            minutes: SmartMinutes(
                overview: "这是一条来自「Sonote 声记」的 Webhook 测试卡片，配置已生效。",
                decisions: ["确认 Webhook 推送链路正常"],
                actionItems: [ActionItem(task: "会后点击「导出 / 复制 → 推送到 Webhook」即可一键同步纪要", owner: settings.localUserName.isEmpty ? "我" : settings.localUserName)]
            ),
            tags: ["测试"]
        )
        return await pushMeetingToWebhook(testSession)
    }

    public func preloadLocalMLXLLM() async {
        guard !isPreloadingLocalLLM else { return }
        isPreloadingLocalLLM = true
        statusBannerMessage = "正在下载/初始化内置离线 MLX 模型..."
        do {
            _ = try await LocalMLXLLMEngine.shared.ensureLoaded(
                modelID: settings.localMLXLLMModelID,
                hfHost: settings.mlxHuggingFaceHost
            )
            refreshAuthInspection()
            statusBannerMessage = "内置离线 MLX 模型已就绪"
        } catch {
            statusBannerMessage = "内置离线 MLX 模型加载失败：\(error.localizedDescription)"
        }
        isPreloadingLocalLLM = false
    }

    public func unloadLocalMLXLLM() async {
        await LocalMLXLLMEngine.shared.unload()
        statusBannerMessage = "已释放内置离线 MLX 模型显存"
    }

    public func exportBackupArchiveWithSavePanel(includeAudio: Bool) -> String? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmm"
        panel.nameFieldStringValue = "Sonote-Backup-\(df.string(from: Date())).zip"
        panel.title = "导出 Sonote（声记）全库备份（不含 API 密钥）"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try ArchiveBackupService.exportArchive(to: url, includeAudioFiles: includeAudio)
            let msg = "已导出全库备份至 \(url.lastPathComponent)"
            statusBannerMessage = msg
            return msg
        } catch {
            let msg = "备份导出失败：\(error.localizedDescription)"
            statusBannerMessage = msg
            return msg
        }
    }

    public func importBackupArchiveWithOpenPanel(restoreSettings: Bool = true) -> String? {
        let panel = NSOpenPanel()
        panel.title = "选择 Sonote（声记）备份包 (.zip) 进行合并恢复"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            let summary = try ArchiveBackupService.importArchive(from: url, restoreSettings: restoreSettings)
            // Reload all stores into live UI
            self.meetings = store.loadMeetings()
            self.voiceprints = voiceprintStore.loadProfiles()
            self.dailyTokenLedger = store.loadTokenLedger(seedFrom: self.meetings)
            self.audioStorageStats = store.audioStorageStats()
            if restoreSettings {
                self.settings = store.loadSettings()
            }
            let msg = "恢复完成：合并 \(summary.meetingsImported) 场会议、\(summary.voiceprintsImported) 份声纹、\(summary.audioFilesRestored) 个音频"
            statusBannerMessage = msg
            return msg
        } catch {
            let msg = "备份恢复失败：\(error.localizedDescription)"
            statusBannerMessage = msg
            return msg
        }
    }

    public func copyMermaidMindMapToClipboard(for meeting: MeetingSession) {
        let mermaid = MeetingStore.exportMermaidMindMap(for: meeting)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(mermaid, forType: .string)
        statusBannerMessage = "已复制 Mermaid 思维导图代码到剪贴板"
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

    private func recordDailyTokenUsage(_ usage: TokenUsage) {
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
            statusBannerMessage = "已清理 \(result.removedFiles) 个录音文件，释放 \(fmt)（文字纪要已保留）"
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
        guard let idx = meetings.firstIndex(where: { $0.id == id }) else { return }
        mutate(&meetings[idx])
        if persist {
            store.saveMeeting(meetings[idx])
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
            title: cleanTitle.isEmpty ? "新纪要" : cleanTitle,
            sourceAppName: "文本导入",
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
            title: "Q4 智能纪要 Mac 客户端评审会（示例）",
            sourceAppName: "腾讯会议",
            sourceBundleId: "com.tencent.meeting",
            startedAt: now.addingTimeInterval(-1260),
            endedAt: now,
            duration: 1260,
            status: .completed,
            segments: [
                TranscriptSegment(timestamp: 12, speaker: .remote, text: "大家好，今天我们主要过一下 Mac 端智能会议纪要的 MVP 方案，参考豆包工作的体验。"),
                TranscriptSegment(timestamp: 38, speaker: .me, text: "核心痛点有两个：一是加入腾讯会议或者飞书会议后，最好能自动弹窗提醒是否开启记录，免得忘记点录音；二是系统声音和麦克风要一起采。"),
                TranscriptSegment(timestamp: 85, speaker: .remote, text: "对，而且会中需要边听边提炼要点和待办事项，不能等到散会后才看一大段逐字稿。模型方面先接 GPT，支持读取本机 auth 文件和手动填 API Key。"),
                TranscriptSegment(timestamp: 142, speaker: .me, text: "没问题，我们用 CoreAudio Process Tap 采集系统声音，配合本机实时语音转写，这周五前把第一个可用版本交付出来测试。")
            ],
            manualNotes: "重点：确保支持 ~/.codex/auth.json 和手动 API Key 两种认证方式。",
            minutes: SmartMinutes(
                suggestedTitle: "Q4 智能纪要 Mac 客户端评审会",
                overview: "本次会议明确了 Mac 端智能会议纪要工具的 MVP 核心范围，参考豆包工作体验，聚焦自动会议检测、双通道音频采集、会中实时纪要提炼及 GPT 多凭证接入。",
                topics: [
                    TopicSection(title: "自动会议检测与无感启动", points: [
                        "加入腾讯会议、飞书、Zoom 等线上会议后自动在桌面右上角弹出轻量提醒卡片。",
                        "支持一键开启、稍后提醒或仅此次忽略，避免打断会议操作。"
                    ]),
                    TopicSection(title: "双通道采集与会中实时记录", points: [
                        "采用 CoreAudio Process Tap 采集系统声音（远端参会人）并同步采集本机麦克风（我）。",
                        "会中周期性自动提炼议题要点、决议与待办，并支持会中随手记与 AI 追问。"
                    ]),
                    TopicSection(title: "AI 模型接入策略", points: [
                        "首期聚焦 GPT 系列模型，支持自动读取本机 ~/.codex/auth.json 或自定义 Auth 文件，也支持手动输入 OpenAI API Key 与代理地址。"
                    ])
                ],
                decisions: [
                    "Mac 客户端采用原生 SwiftUI + CoreAudio Process Tap 实现，兼顾低占用与无录屏权限弹窗体验。",
                    "首版优先支持 GPT 模型及双轨实时转写。"
                ],
                actionItems: [
                    ActionItem(task: "完成 Mac 客户端首版开发与音频采集联调", owner: "我", dueDate: "本周五"),
                    ActionItem(task: "验证腾讯会议 / 飞书自动检测触发与悬浮提示体验", owner: "产品与测试", dueDate: "下周一")
                ],
                openQuestions: [
                    "后续是否扩展支持 Claude / Gemini / 本地 Ollama 模型切换？"
                ],
                participants: ["我", "产品负责人（远端）"],
                lastUpdatedAt: now,
                isFinalized: true
            )
        )
        meetings.insert(demo, at: 0)
        selectedMeetingID = demo.id
        store.saveMeeting(demo)
    }

    // MARK: - Export & System Settings Helpers

    public func copyMarkdownToClipboard(for meeting: MeetingSession, includeTranscript: Bool = true) {
        let md = MeetingStore.exportMarkdown(for: meeting, includeTranscript: includeTranscript)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(md, forType: .string)
        statusBannerMessage = "已复制 Markdown 会议纪要到剪贴板"
    }

    public func exportMarkdownWithSavePanel(for meeting: MeetingSession) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        let safeName = meeting.title.replacingOccurrences(of: "/", with: "-")
        panel.nameFieldStringValue = "\(safeName).md"
        panel.title = "导出智能会议纪要 (Markdown)"
        if panel.runModal() == .OK, let url = panel.url {
            let md = MeetingStore.exportMarkdown(for: meeting, includeTranscript: true)
            try? md.write(to: url, atomically: true, encoding: .utf8)
            statusBannerMessage = "已导出至 \(url.lastPathComponent)"
        }
    }

    public func openPrivacySettings(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
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
}
