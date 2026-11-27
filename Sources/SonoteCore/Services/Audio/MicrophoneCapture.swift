import Foundation
import AVFoundation

public enum MicrophoneCaptureError: LocalizedError {
    case permissionDenied
    case invalidInputFormat

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return SonoteLocale.t("未获得麦克风访问权限。请在「系统设置 → 隐私与安全性 → 麦克风」中允许「Sonote」。", "Microphone permission denied. Enable Sonote in System Settings -> Privacy & Security -> Microphone.")
        case .invalidInputFormat:
            return SonoteLocale.t("无法获取有效的麦克风音频格式，请检查本机音频输入设备。", "Could not read microphone audio format. Check your input device.")
        }
    }
}

public final class MicrophoneCapture: @unchecked Sendable {
    private let controlQueue = DispatchQueue(label: "com.sonote.mic-capture.control")
    private var engine = AVAudioEngine()
    private var isRunning = false
    private var isPaused = false
    private var configChangeObserver: NSObjectProtocol?
    private var pendingReconnectWork: DispatchWorkItem?

    public var onAudioBuffer: ((AVAudioPCMBuffer, Float) -> Void)?
    public var onRouteChanged: ((String) -> Void)?

    public init() {}

    deinit {
        stop()
    }

    public static func authorizationStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    public static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        default:
            return false
        }
    }

    public func setPaused(_ paused: Bool) {
        controlQueue.async { [weak self] in
            self?.isPaused = paused
        }
    }

    public func start() async throws {
        let alreadyRunning = controlQueue.sync { isRunning }
        guard !alreadyRunning else { return }

        let granted = await Self.requestPermission()
        guard granted else {
            throw MicrophoneCaptureError.permissionDenied
        }

        try controlQueue.sync {
            guard !isRunning else { return }
            try installTapAndStartLocked(preservePausedState: false)
            isRunning = true
            observeConfigurationChangesLocked()
        }
    }

    public func stop() {
        controlQueue.sync {
            isRunning = false
            pendingReconnectWork?.cancel()
            pendingReconnectWork = nil
            removeConfigurationObserverLocked()
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
    }

    private func installTapAndStartLocked(preservePausedState: Bool) throws {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        engine.reset()

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw MicrophoneCaptureError.invalidInputFormat
        }

        inputNode.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self, !self.isPaused else { return }
            let rms = WAVEncoder.computeRMS(buffer: buffer)
            self.onAudioBuffer?(buffer, rms)
        }

        engine.prepare()
        try engine.start()
        if !preservePausedState {
            isPaused = false
        }
    }

    private func observeConfigurationChangesLocked() {
        removeConfigurationObserverLocked()
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            self?.scheduleReconnect()
        }
    }

    private func removeConfigurationObserverLocked() {
        if let observer = configChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            configChangeObserver = nil
        }
    }

    private func scheduleReconnect() {
        controlQueue.async { [weak self] in
            guard let self, self.isRunning else { return }
            self.pendingReconnectWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.isRunning else { return }
                do {
                    try self.installTapAndStartLocked(preservePausedState: true)
                    self.onRouteChanged?("麦克风输入设备已切换，采集已自动重连")
                } catch {
                    // Retry once after Bluetooth HFP/A2DP profile handoff settles
                    self.controlQueue.asyncAfter(deadline: .now() + 0.65) { [weak self] in
                        guard let self, self.isRunning else { return }
                        if (try? self.installTapAndStartLocked(preservePausedState: true)) != nil {
                            self.onRouteChanged?("麦克风输入设备已切换，采集已自动重连")
                        }
                    }
                }
            }
            self.pendingReconnectWork = work
            self.controlQueue.asyncAfter(deadline: .now() + 0.3, execute: work)
        }
    }
}
