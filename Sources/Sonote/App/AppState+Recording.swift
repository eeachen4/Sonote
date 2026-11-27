import Foundation
import SonoteCore

// MARK: - Meeting Lifecycle, Floating Capsule & Periodic Timers

extension AppState {

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

        let title = calendarContext?.title ?? detectedApp?.appName ?? L("新录音", "New Recording")
        let calendarAttendees = calendarContext?.attendees ?? []
        let calendarHotwords = calendarContext?.asrHotwordHint ?? ""
        let combinedHotwords = [calendarHotwords, combinedVoiceprintHotwords]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")

        let session = MeetingSession(
            title: title,
            sourceAppName: detectedApp?.appName ?? L("新录音", "New Recording"),
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
            runtimeWarnings.append(L("未能开启任何音频源（系统声音或麦克风）。请授予对应系统权限后重试，或先使用手动笔记。", "Could not start any audio source. Please grant Mic / System Audio permission and try again."))
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

    func startTimers() {
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

    func stopTimers() {
        durationTimer?.invalidate()
        durationTimer = nil
        liveSummaryTimer?.invalidate()
        liveSummaryTimer = nil
    }

    func triggerLiveMinutesIfNeeded() async {
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
}
