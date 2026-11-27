import Foundation
import CoreAudio
import AppKit

public struct AudioProcessSnapshot: Equatable, Sendable {
    public var pid: Int32
    public var bundleID: String
    public var appName: String
    public var isRunningInput: Bool
    public var isRunningOutput: Bool

    public init(pid: Int32, bundleID: String, appName: String, isRunningInput: Bool, isRunningOutput: Bool) {
        self.pid = pid
        self.bundleID = bundleID
        self.appName = appName
        self.isRunningInput = isRunningInput
        self.isRunningOutput = isRunningOutput
    }
}

/// Continuously monitors CoreAudio Process Objects (macOS 14.2+) to detect when
/// the user joins or leaves a meeting across Zoom, Tencent Meeting, Feishu, DingTalk,
/// Teams, Slack, WeChat, and WebRTC browser meetings (Chrome/Safari/Arc/Edge).
public final class MeetingDetector: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.sonote.meeting-detector", qos: .utility)
    private var timer: DispatchSourceTimer?

    private var settings: AppSettings = AppSettings()
    private var isRecordingProvider: () -> Bool = { false }

    // Tracking state
    private var outputStartTimes: [String: Date] = [:]
    private var dismissedSessionKeys: Set<String> = []
    private var snoozeUntilByKey: [String: Date] = [:]
    private var currentActiveMeeting: DetectedMeetingApp?
    private var currentMeetingInactiveSince: Date?
    private var lastPromptedKey: String?

    public var onMeetingDetected: ((DetectedMeetingApp) -> Void)?
    public var onActiveMeetingEnded: ((DetectedMeetingApp) -> Void)?

    public init() {}

    deinit {
        stop()
    }

    public func configure(settings: AppSettings, isRecordingProvider: @escaping () -> Bool) {
        queue.async { [weak self] in
            self?.settings = settings
            self?.isRecordingProvider = isRecordingProvider
        }
    }

    public func start() {
        queue.async { [weak self] in
            guard let self, self.timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + 1.5, repeating: 2.0)
            timer.setEventHandler { [weak self] in
                self?.pollAudioProcesses()
            }
            timer.resume()
            self.timer = timer
        }
    }

    public func stop() {
        queue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
        }
    }

    public func dismissCurrentMeeting(_ meeting: DetectedMeetingApp) {
        queue.async { [weak self] in
            let key = meeting.bundleIdentifier.lowercased()
            self?.dismissedSessionKeys.insert(key)
        }
    }

    public func snoozeMeeting(_ meeting: DetectedMeetingApp, duration: TimeInterval = 300) {
        queue.async { [weak self] in
            let key = meeting.bundleIdentifier.lowercased()
            self?.snoozeUntilByKey[key] = Date().addingTimeInterval(duration)
            if self?.lastPromptedKey == key {
                self?.lastPromptedKey = nil
            }
        }
    }

    public func markRecordingStarted(for meeting: DetectedMeetingApp?) {
        queue.async { [weak self] in
            guard let self else { return }
            if let meeting {
                self.currentActiveMeeting = meeting
                self.currentMeetingInactiveSince = nil
                self.lastPromptedKey = meeting.bundleIdentifier.lowercased()
            }
        }
    }

    public func resetAfterRecordingStopped() {
        queue.async { [weak self] in
            self?.currentMeetingInactiveSince = nil
            if let active = self?.currentActiveMeeting {
                self?.dismissedSessionKeys.insert(active.bundleIdentifier.lowercased())
            }
            self?.currentActiveMeeting = nil
            self?.lastPromptedKey = nil
        }
    }

    private func pollAudioProcesses() {
        guard settings.autoDetectMeetings else { return }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let snapshots = Self.fetchAudioProcesses(excludingPID: ownPID)
        let now = Date()

        // Update sustained output tracking
        var seenOutputKeys: Set<String> = []
        for snap in snapshots where snap.isRunningOutput {
            let key = Self.canonicalBundleID(for: snap.bundleID)
            seenOutputKeys.insert(key)
            if outputStartTimes[key] == nil {
                outputStartTimes[key] = now
            }
        }
        for existingKey in Array(outputStartTimes.keys) where !seenOutputKeys.contains(existingKey) {
            outputStartTimes.removeValue(forKey: existingKey)
        }

        let durations: [String: TimeInterval] = outputStartTimes.mapValues { now.timeIntervalSince($0) }
        let detected = Self.classifyActiveMeeting(
            processes: snapshots,
            settings: settings,
            sustainedOutputDurations: durations
        )

        // Clear dismissed keys once a dismissed app completely stops all audio activity
        let activeKeys = Set(snapshots.filter { $0.isRunningInput || $0.isRunningOutput }.map {
            Self.canonicalBundleID(for: $0.bundleID).lowercased()
        })
        dismissedSessionKeys = dismissedSessionKeys.filter { activeKeys.contains($0) }

        let currentlyRecording = isRecordingProvider()

        if let detected {
            let key = detected.bundleIdentifier.lowercased()
            currentActiveMeeting = detected
            currentMeetingInactiveSince = nil

            guard !currentlyRecording else { return }
            if dismissedSessionKeys.contains(key) { return }
            if let snoozeUntil = snoozeUntilByKey[key], now < snoozeUntil { return }
            if lastPromptedKey == key { return }

            lastPromptedKey = key
            DispatchQueue.main.async { [weak self] in
                self?.onMeetingDetected?(detected)
            }
        } else {
            // No active meeting detected right now
            if !currentlyRecording {
                lastPromptedKey = nil
                currentActiveMeeting = nil
                currentMeetingInactiveSince = nil
            } else if settings.promptOnMeetingEnd, let active = currentActiveMeeting {
                if currentMeetingInactiveSince == nil {
                    currentMeetingInactiveSince = now
                } else if let since = currentMeetingInactiveSince, now.timeIntervalSince(since) >= 8.0 {
                    let endedMeeting = active
                    currentActiveMeeting = nil
                    currentMeetingInactiveSince = nil
                    DispatchQueue.main.async { [weak self] in
                        self?.onActiveMeetingEnded?(endedMeeting)
                    }
                }
            }
        }
    }

    // MARK: - Pure Classification Logic (Unit-Testable)

    public static func canonicalBundleID(for rawBundleID: String) -> String {
        let lower = rawBundleID.lowercased()
        // Normalize Chromium / Electron / Meeting app helper subprocess bundle IDs to their parent app
        for descriptor in MeetingAppCatalog.all {
            let base = descriptor.bundleID.lowercased()
            if lower == base || lower.hasPrefix(base + ".") {
                return descriptor.bundleID
            }
        }
        if lower.contains("zoom") && lower.contains("cpthost") {
            return "us.zoom.xos"
        }
        if lower.contains("tencent.meeting") || lower.contains("wemeet") {
            return "com.tencent.meeting"
        }
        if lower.contains("lark") || lower.contains("feishu") {
            return "com.electron.lark"
        }
        if lower.contains("dingtalk") {
            return "com.alibaba.DingTalkMac"
        }
        if lower.contains("teams") && lower.contains("microsoft") {
            return "com.microsoft.teams2"
        }
        return rawBundleID
    }

    public static func classifyActiveMeeting(
        processes: [AudioProcessSnapshot],
        settings: AppSettings,
        sustainedOutputDurations: [String: TimeInterval]
    ) -> DetectedMeetingApp? {
        let monitoredSet = Set(settings.monitoredBundleIDs.map { $0.lowercased() })
        let ignoredList = settings.ignoredBundleIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }

        func isIgnored(_ bundleID: String) -> Bool {
            let lower = bundleID.lowercased()
            return ignoredList.contains { rule in
                lower == rule || lower.hasPrefix(rule + ".")
            }
        }

        // Aggregate per canonical bundle ID (since Electron/Chrome may have multiple audio helpers)
        struct AggregatedApp {
            var canonicalID: String
            var displayName: String
            var pid: Int32
            var isInput: Bool
            var isOutput: Bool
            var descriptor: MeetingAppDescriptor?
        }

        var byCanonical: [String: AggregatedApp] = [:]
        for proc in processes {
            guard proc.isRunningInput || proc.isRunningOutput else { continue }
            let canonical = canonicalBundleID(for: proc.bundleID)
            if canonical.lowercased() == "com.sonote.app" || canonical.lowercased() == "com.ttminutes.app" { continue }
            if isIgnored(proc.bundleID) || isIgnored(canonical) { continue }

            let desc = MeetingAppCatalog.descriptor(for: canonical)
            let name = desc?.displayName ?? (proc.appName.isEmpty ? canonical : proc.appName)

            if var existing = byCanonical[canonical.lowercased()] {
                existing.isInput = existing.isInput || proc.isRunningInput
                existing.isOutput = existing.isOutput || proc.isRunningOutput
                byCanonical[canonical.lowercased()] = existing
            } else {
                byCanonical[canonical.lowercased()] = AggregatedApp(
                    canonicalID: canonical,
                    displayName: name,
                    pid: proc.pid,
                    isInput: proc.isRunningInput,
                    isOutput: proc.isRunningOutput,
                    descriptor: desc
                )
            }
        }

        // Priority 1: Monitored non-browser meeting app using Microphone (strongest signal)
        for app in byCanonical.values {
            guard let desc = app.descriptor, !desc.isBrowser else { continue }
            guard monitoredSet.contains(desc.bundleID.lowercased()) else { continue }
            if app.isInput {
                return DetectedMeetingApp(
                    bundleIdentifier: app.canonicalID,
                    appName: app.displayName,
                    pid: app.pid,
                    isUsingMicrophone: true,
                    isPlayingAudio: app.isOutput
                )
            }
        }

        // Priority 2: Dedicated meeting app (Zoom / 腾讯会议 / Teams / FaceTime) playing audio continuously >= 4s (muted listener)
        for app in byCanonical.values {
            guard let desc = app.descriptor, desc.isDedicatedMeetingApp else { continue }
            guard monitoredSet.contains(desc.bundleID.lowercased()) else { continue }
            if app.isOutput, (sustainedOutputDurations[app.canonicalID] ?? 0) >= 4.0 {
                return DetectedMeetingApp(
                    bundleIdentifier: app.canonicalID,
                    appName: app.displayName,
                    pid: app.pid,
                    isUsingMicrophone: app.isInput,
                    isPlayingAudio: true
                )
            }
        }

        // Priority 3: Monitored Web Browser actively using Microphone (Google Meet, Feishu Web, Tencent Meeting Web, etc.)
        if settings.detectBrowserCalls {
            for app in byCanonical.values {
                guard let desc = app.descriptor, desc.isBrowser else { continue }
                guard monitoredSet.contains(desc.bundleID.lowercased()) else { continue }
                if app.isInput {
                    return DetectedMeetingApp(
                        bundleIdentifier: app.canonicalID,
                        appName: app.displayName,
                        pid: app.pid,
                        isUsingMicrophone: true,
                        isPlayingAudio: app.isOutput
                    )
                }
            }
        }

        // Priority 4: Unknown third-party app using BOTH microphone input AND audio output simultaneously (VoIP/call signature)
        let ignoredSystemPrefixes = ["com.apple.coreaudio", "com.apple.audio", "com.apple.siri", "com.apple.dictation"]
        for app in byCanonical.values where app.descriptor == nil {
            let lower = app.canonicalID.lowercased()
            if ignoredSystemPrefixes.contains(where: { lower.hasPrefix($0) }) { continue }
            if app.isInput && app.isOutput {
                return DetectedMeetingApp(
                    bundleIdentifier: app.canonicalID,
                    appName: app.displayName,
                    pid: app.pid,
                    isUsingMicrophone: true,
                    isPlayingAudio: true
                )
            }
        }

        return nil
    }

    // MARK: - CoreAudio Process Object Introspection

    public static func fetchAudioProcesses(excludingPID: pid_t) -> [AudioProcessSnapshot] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        ) == noErr, dataSize > 0 else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var processIDs = Array(repeating: AudioObjectID(0), count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &processIDs
        ) == noErr else {
            return []
        }

        var results: [AudioProcessSnapshot] = []
        results.reserveCapacity(count)

        for objID in processIDs {
            var pid: pid_t = 0
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            var pidAddr = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyPID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            guard AudioObjectGetPropertyData(objID, &pidAddr, 0, nil, &pidSize, &pid) == noErr else {
                continue
            }
            if pid == excludingPID || pid <= 0 { continue }

            let isInput = readBoolProperty(objID: objID, selector: kAudioProcessPropertyIsRunningInput)
            let isOutput = readBoolProperty(objID: objID, selector: kAudioProcessPropertyIsRunningOutput)
            if !isInput && !isOutput { continue }

            var bundleID = readStringProperty(objID: objID, selector: kAudioProcessPropertyBundleID) ?? ""
            var appName = ""
            if let runningApp = NSRunningApplication(processIdentifier: pid) {
                if bundleID.isEmpty, let bid = runningApp.bundleIdentifier {
                    bundleID = bid
                }
                appName = runningApp.localizedName ?? ""
            }
            if bundleID.isEmpty {
                bundleID = "pid.\(pid)"
            }
            if appName.isEmpty {
                appName = bundleID
            }

            results.append(AudioProcessSnapshot(
                pid: pid,
                bundleID: bundleID,
                appName: appName,
                isRunningInput: isInput,
                isRunningOutput: isOutput
            ))
        }

        return results
    }

    private static func readBoolProperty(objID: AudioObjectID, selector: AudioObjectPropertySelector) -> Bool {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(objID, &addr, 0, nil, &size, &value)
        return status == noErr && value != 0
    }

    private static func readStringProperty(objID: AudioObjectID, selector: AudioObjectPropertySelector) -> String? {
        var cfRef: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(objID, &addr, 0, nil, &size, &cfRef)
        guard status == noErr, let cfStr = cfRef?.takeRetainedValue() else {
            return nil
        }
        return cfStr as String
    }
}
