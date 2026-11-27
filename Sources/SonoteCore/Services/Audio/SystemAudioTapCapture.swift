import Foundation
import CoreAudio
import AVFoundation

public enum SystemAudioTapError: LocalizedError {
    case failedToCreateTap(OSStatus)
    case failedToReadTapFormat(OSStatus)
    case failedToCreateAggregateDevice(OSStatus)
    case failedToCreateIOProc(OSStatus)
    case failedToStartDevice(OSStatus)
    case invalidAudioFormat

    public var errorDescription: String? {
        switch self {
        case .failedToCreateTap(let status):
            return SonoteLocale.t("无法创建系统声音采集通道 (OSStatus \(status))。请在「系统设置 → 隐私与安全性 → 仅系统音频录制」中允许「Sonote」。", "Failed to create system audio tap (OSStatus \(status)). Enable Sonote in System Settings -> Privacy & Security -> System Audio Recording Only.")
        case .failedToReadTapFormat(let status):
            return SonoteLocale.t("无法读取系统音频格式 (OSStatus \(status))。", "Failed to read system audio format (OSStatus \(status)).")
        case .failedToCreateAggregateDevice(let status):
            return SonoteLocale.t("无法创建虚拟音频聚合设备 (OSStatus \(status))。", "Failed to create audio aggregate device (OSStatus \(status)).")
        case .failedToCreateIOProc(let status):
            return SonoteLocale.t("无法注册音频采集回调 (OSStatus \(status))。", "Failed to register audio IO callback (OSStatus \(status)).")
        case .failedToStartDevice(let status):
            return SonoteLocale.t("无法启动系统声音采集 (OSStatus \(status))。", "Failed to start system audio capture (OSStatus \(status)).")
        case .invalidAudioFormat:
            return SonoteLocale.t("系统音频格式不受支持。", "Unsupported system audio format.")
        }
    }
}

/// Captures macOS system output audio via CoreAudio Process Tap (macOS 14.2+),
/// requiring only System Audio Recording permission (no Screen Recording permission).
public final class SystemAudioTapCapture: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.sonote.system-audio-tap", qos: .userInteractive)
    private let controlQueue = DispatchQueue(label: "com.sonote.system-audio-tap.control")
    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?
    private var tapFormat: AVAudioFormat?
    private var isRunning = false
    private var isPaused = false
    private var routeListenerRegistered = false
    private var routeListenerBlock: AudioObjectPropertyListenerBlock?
    private var pendingReconnectWork: DispatchWorkItem?
    private var currentOutputUID: String?

    public var onAudioBuffer: ((AVAudioPCMBuffer, Float) -> Void)?
    public var onRouteChanged: ((String) -> Void)?

    public init() {}

    deinit {
        stop()
    }

    public func setPaused(_ paused: Bool) {
        queue.async { [weak self] in
            self?.isPaused = paused
        }
    }

    public func start() throws {
        try controlQueue.sync {
            guard !isRunning else { return }
            try startTapLocked(preservePausedState: false)
            isRunning = true
            registerDefaultOutputDeviceListenerLocked()
        }
    }

    public func stop() {
        controlQueue.sync {
            isRunning = false
            pendingReconnectWork?.cancel()
            pendingReconnectWork = nil
            unregisterDefaultOutputDeviceListenerLocked()
            cleanupLocked()
        }
    }

    private func startTapLocked(preservePausedState: Bool) throws {
        // Exclude our own app process so we never create feedback loops
        var excludedProcesses: [AudioObjectID] = []
        if let ownProcessObj = Self.translatePIDToAudioObjectID(ProcessInfo.processInfo.processIdentifier) {
            excludedProcesses.append(ownProcessObj)
        }

        let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: excludedProcesses)
        tapDescription.uuid = UUID()
        tapDescription.name = "Sonote System Audio Tap"
        tapDescription.muteBehavior = .unmuted
        tapDescription.isPrivate = true

        var createdTapID: AudioObjectID = kAudioObjectUnknown
        let tapStatus = AudioHardwareCreateProcessTap(tapDescription, &createdTapID)
        guard tapStatus == noErr, createdTapID != kAudioObjectUnknown else {
            throw SystemAudioTapError.failedToCreateTap(tapStatus)
        }
        self.tapID = createdTapID

        // Read tap stream description (ASBD)
        var asbd = AudioStreamBasicDescription()
        var asbdSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var formatAddress = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let fmtStatus = AudioObjectGetPropertyData(createdTapID, &formatAddress, 0, nil, &asbdSize, &asbd)
        guard fmtStatus == noErr else {
            cleanupLocked()
            throw SystemAudioTapError.failedToReadTapFormat(fmtStatus)
        }

        guard let avFormat = AVAudioFormat(streamDescription: &asbd) else {
            cleanupLocked()
            throw SystemAudioTapError.invalidAudioFormat
        }
        self.tapFormat = avFormat

        // Create a private Aggregate Device backed by the Process Tap
        let aggregateUID = "com.sonote.aggregate.\(UUID().uuidString)"
        var aggregateDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Sonote System Tap Aggregate",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapDescription.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: true
                ]
            ]
        ]

        let defaultOutputUID = Self.defaultOutputDeviceUID()
        self.currentOutputUID = defaultOutputUID
        if let defaultOutputUID {
            aggregateDesc[kAudioAggregateDeviceMainSubDeviceKey] = defaultOutputUID
            aggregateDesc[kAudioAggregateDeviceClockDeviceKey] = defaultOutputUID
            aggregateDesc[kAudioAggregateDeviceSubDeviceListKey] = [
                [kAudioSubDeviceUIDKey: defaultOutputUID]
            ]
        }

        var createdAggregateID: AudioObjectID = kAudioObjectUnknown
        let aggStatus = AudioHardwareCreateAggregateDevice(aggregateDesc as CFDictionary, &createdAggregateID)
        guard aggStatus == noErr, createdAggregateID != kAudioObjectUnknown else {
            cleanupLocked()
            throw SystemAudioTapError.failedToCreateAggregateDevice(aggStatus)
        }
        self.aggregateDeviceID = createdAggregateID

        // Attach IOProc block
        var createdIOProcID: AudioDeviceIOProcID?
        let ioStatus = AudioDeviceCreateIOProcIDWithBlock(&createdIOProcID, createdAggregateID, queue) { [weak self] _, inInputData, _, _, _ in
            guard let self, !self.isPaused, let format = self.tapFormat else { return }
            guard let pcmBuffer = Self.makePCMBuffer(from: inInputData, format: format) else { return }
            let rms = WAVEncoder.computeRMS(buffer: pcmBuffer)
            self.onAudioBuffer?(pcmBuffer, rms)
        }
        guard ioStatus == noErr, let validIOProc = createdIOProcID else {
            cleanupLocked()
            throw SystemAudioTapError.failedToCreateIOProc(ioStatus)
        }
        self.ioProcID = validIOProc

        let startStatus = AudioDeviceStart(createdAggregateID, validIOProc)
        guard startStatus == noErr else {
            cleanupLocked()
            throw SystemAudioTapError.failedToStartDevice(startStatus)
        }

        if !preservePausedState {
            queue.sync { self.isPaused = false }
        }
    }

    private func registerDefaultOutputDeviceListenerLocked() {
        guard !routeListenerRegistered else { return }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.scheduleTapReconnect()
        }
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            controlQueue,
            block
        )
        if status == noErr {
            routeListenerBlock = block
            routeListenerRegistered = true
        }
    }

    private func unregisterDefaultOutputDeviceListenerLocked() {
        guard routeListenerRegistered, let block = routeListenerBlock else { return }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            controlQueue,
            block
        )
        routeListenerBlock = nil
        routeListenerRegistered = false
    }

    private func scheduleTapReconnect() {
        guard isRunning else { return }
        pendingReconnectWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isRunning else { return }
            let newUID = Self.defaultOutputDeviceUID()
            guard newUID != self.currentOutputUID else { return }
            self.cleanupLocked()
            do {
                try self.startTapLocked(preservePausedState: true)
                self.onRouteChanged?("系统输出设备已切换，系统音频采集已自动重连")
            } catch {
                // Retry once after 0.6s in case Bluetooth headset is still negotiating profile
                self.controlQueue.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    guard let self, self.isRunning else { return }
                    self.cleanupLocked()
                    if (try? self.startTapLocked(preservePausedState: true)) != nil {
                        self.onRouteChanged?("系统输出设备已切换，系统音频采集已自动重连")
                    }
                }
            }
        }
        pendingReconnectWork = work
        controlQueue.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func cleanupLocked() {
        if aggregateDeviceID != kAudioObjectUnknown {
            if let proc = ioProcID {
                AudioDeviceStop(aggregateDeviceID, proc)
                AudioDeviceDestroyIOProcID(aggregateDeviceID, proc)
                ioProcID = nil
            }
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = kAudioObjectUnknown
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
        tapFormat = nil
    }

    private static func makePCMBuffer(
        from inputListPtr: UnsafePointer<AudioBufferList>,
        format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputListPtr))
        guard let firstBuf = abl.first, firstBuf.mDataByteSize > 0 else { return nil }

        let bytesPerFrame = max(1, Int(format.streamDescription.pointee.mBytesPerFrame))
        let frameCount = AVAudioFrameCount(Int(firstBuf.mDataByteSize) / bytesPerFrame)
        guard frameCount > 0 else { return nil }

        // Convert to standard non-interleaved Float32 format so AVAudioConverter / SpeechAnalyzer always accept it cleanly
        guard let floatFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: format.sampleRate,
            channels: format.channelCount,
            interleaved: false
        ), let outBuffer = AVAudioPCMBuffer(pcmFormat: floatFormat, frameCapacity: frameCount) else {
            return nil
        }
        outBuffer.frameLength = frameCount

        let isFloat = (format.streamDescription.pointee.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isNonInterleaved = (format.streamDescription.pointee.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
        let channels = Int(format.channelCount)
        let frames = Int(frameCount)

        guard let dstChannels = outBuffer.floatChannelData else { return nil }

        if isFloat {
            if isNonInterleaved {
                for ch in 0..<min(channels, abl.count) {
                    guard let src = abl[ch].mData?.assumingMemoryBound(to: Float.self) else { continue }
                    dstChannels[ch].update(from: src, count: frames)
                }
            } else if let src = firstBuf.mData?.assumingMemoryBound(to: Float.self) {
                for f in 0..<frames {
                    for ch in 0..<channels {
                        dstChannels[ch][f] = src[f * channels + ch]
                    }
                }
            }
            return outBuffer
        } else {
            // Fallback for Int16 PCM streams
            if !isNonInterleaved, let src = firstBuf.mData?.assumingMemoryBound(to: Int16.self) {
                let scale = 1.0 / Float(Int16.max)
                for f in 0..<frames {
                    for ch in 0..<channels {
                        dstChannels[ch][f] = Float(src[f * channels + ch]) * scale
                    }
                }
                return outBuffer
            }
        }
        return nil
    }

    private static func translatePIDToAudioObjectID(_ pid: pid_t) -> AudioObjectID? {
        var mutablePID = pid
        var processObjID: AudioObjectID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            UInt32(MemoryLayout<pid_t>.size),
            &mutablePID,
            &size,
            &processObjID
        )
        if status == noErr && processObjID != kAudioObjectUnknown {
            return processObjID
        }
        return nil
    }

    private static func defaultOutputDeviceUID() -> String? {
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        ) == noErr, deviceID != kAudioObjectUnknown else {
            return nil
        }

        var uidRef: Unmanaged<CFString>?
        var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var uidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            deviceID,
            &uidAddress,
            0,
            nil,
            &uidSize,
            &uidRef
        ) == noErr, let cfStr = uidRef?.takeRetainedValue() else {
            return nil
        }
        return cfStr as String
    }
}
