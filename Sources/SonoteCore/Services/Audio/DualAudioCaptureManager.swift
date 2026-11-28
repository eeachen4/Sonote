import Foundation
import AVFoundation

public struct AudioCaptureStartReport: Sendable {
    public var systemAudioActive: Bool
    public var microphoneActive: Bool
    public var warnings: [String]
    public var backupFilePath: String?

    public var hasAnySource: Bool {
        systemAudioActive || microphoneActive
    }
}

/// Real-time 16 kHz mono dual-track mixer that blends System Audio (remote) and Microphone (me)
/// with soft clipping so backup `.m4a` files always preserve both sides of the conversation.
public final class DualChannelAudioMixer: @unchecked Sendable {
    private let lock = NSLock()
    private var systemPending: [Float] = []
    private var micPending: [Float] = []
    private var systemActive = false
    private var micActive = false

    public init() {}

    public func configure(systemActive: Bool, micActive: Bool) {
        lock.withLock {
            self.systemActive = systemActive
            self.micActive = micActive
            self.systemPending.removeAll(keepingCapacity: true)
            self.micPending.removeAll(keepingCapacity: true)
        }
    }

    public func pushSystem(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        lock.withLock {
            systemPending.append(contentsOf: samples)
            // Guard against unbounded drift if one stream stalls
            if systemPending.count > 16_000 * 5 {
                systemPending.removeFirst(systemPending.count - 16_000 * 2)
            }
        }
    }

    public func pushMic(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        lock.withLock {
            micPending.append(contentsOf: samples)
            if micPending.count > 16_000 * 5 {
                micPending.removeFirst(micPending.count - 16_000 * 2)
            }
        }
    }

    /// Drains synchronized mixed samples (with soft tanh limiting to avoid clipping distortion).
    public func drainMixed(flushAll: Bool = false) -> [Float] {
        lock.withLock {
            let sysCount = systemPending.count
            let micCount = micPending.count

            let count: Int
            if systemActive && micActive {
                if flushAll {
                    count = max(sysCount, micCount)
                } else {
                    let minBoth = min(sysCount, micCount)
                    if minBoth > 0 {
                        count = minBoth
                    } else if max(sysCount, micCount) >= 3_200 {
                        // One stream is temporarily silent/stalled (>200ms); drain the active stream
                        count = max(sysCount, micCount)
                    } else {
                        return []
                    }
                }
            } else {
                count = max(sysCount, micCount)
            }

            guard count > 0 else { return [] }
            var out = [Float](repeating: 0, count: count)

            let sysTake = min(count, sysCount)
            let micTake = min(count, micCount)

            for i in 0..<count {
                let s: Float = i < sysTake ? systemPending[i] : 0
                let m: Float = i < micTake ? micPending[i] : 0
                // Soft limiter preserves loudness without harsh digital clipping
                out[i] = tanhf((s + m) * 0.85)
            }

            if sysTake > 0 { systemPending.removeFirst(sysTake) }
            if micTake > 0 { micPending.removeFirst(micTake) }
            return out
        }
    }
}

/// Coordinates simultaneous System Audio (Process Tap) and Microphone capture,
/// emits per-channel buffers & RMS levels, and mixes BOTH channels into the `.m4a` backup recording.
public final class DualAudioCaptureManager: @unchecked Sendable {
    private let systemCapture = SystemAudioTapCapture()
    private let micCapture = MicrophoneCapture()
    private let mixer = DualChannelAudioMixer()

    private let backupQueue = DispatchQueue(label: "com.sonote.audio-backup")
    private var backupAudioFile: AVAudioFile?
    private var backupFilePath: String?
    private var flushTimer: DispatchSourceTimer?

    public var onSystemBuffer: ((AVAudioPCMBuffer, Float) -> Void)?
    public var onMicBuffer: ((AVAudioPCMBuffer, Float) -> Void)?
    public var onDeviceRouteChanged: ((String) -> Void)?

    public init() {}

    public func start(
        mode: AudioCaptureMode,
        saveBackupTo backupURL: URL?
    ) async -> AudioCaptureStartReport {
        var warnings: [String] = []
        var systemActive = false
        var micActive = false

        setupBackupFile(at: backupURL)

        if mode.capturesSystem {
            systemCapture.onAudioBuffer = { [weak self] buffer, level in
                self?.onSystemBuffer?(buffer, level)
                guard let self, let copied = Self.copyPCMBuffer(buffer) else { return }
                self.backupQueue.async { [weak self] in
                    guard let self, self.backupAudioFile != nil else { return }
                    let mono = WAVEncoder.extractMono16kSamples(from: copied)
                    self.mixer.pushSystem(mono)
                }
            }
            systemCapture.onRouteChanged = { [weak self] notice in
                self?.onDeviceRouteChanged?(notice)
            }
            do {
                try systemCapture.start()
                systemActive = true
            } catch {
                warnings.append("系统声音采集启动失败：\(error.localizedDescription)")
            }
        }

        if mode.capturesMic {
            micCapture.onAudioBuffer = { [weak self] buffer, level in
                self?.onMicBuffer?(buffer, level)
                guard let self, let copied = Self.copyPCMBuffer(buffer) else { return }
                self.backupQueue.async { [weak self] in
                    guard let self, self.backupAudioFile != nil else { return }
                    let mono = WAVEncoder.extractMono16kSamples(from: copied)
                    self.mixer.pushMic(mono)
                }
            }
            micCapture.onRouteChanged = { [weak self] notice in
                self?.onDeviceRouteChanged?(notice)
            }
            do {
                try await micCapture.start()
                micActive = true
            } catch {
                warnings.append("麦克风采集启动失败：\(error.localizedDescription)")
            }
        }

        mixer.configure(systemActive: systemActive, micActive: micActive)
        if backupURL != nil && (systemActive || micActive) {
            startBackupFlushTimer()
        }

        return AudioCaptureStartReport(
            systemAudioActive: systemActive,
            microphoneActive: micActive,
            warnings: warnings,
            backupFilePath: backupFilePath
        )
    }

    public func setPaused(_ paused: Bool) {
        systemCapture.setPaused(paused)
        micCapture.setPaused(paused)
    }

    public func stop() {
        systemCapture.stop()
        micCapture.stop()
        backupQueue.sync {
            flushTimer?.cancel()
            flushTimer = nil
            let leftover = mixer.drainMixed(flushAll: true)
            if !leftover.isEmpty {
                writeSamplesLocked(leftover)
            }
            backupAudioFile = nil
        }
    }

    private func setupBackupFile(at url: URL?) {
        backupQueue.sync {
            flushTimer?.cancel()
            flushTimer = nil
            backupAudioFile = nil
            backupFilePath = nil
            guard let url else { return }
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            if let file = try? AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false) {
                backupAudioFile = file
                backupFilePath = url.path
            }
        }
    }

    private func startBackupFlushTimer() {
        backupQueue.async { [weak self] in
            guard let self else { return }
            let timer = DispatchSource.makeTimerSource(queue: self.backupQueue)
            timer.schedule(deadline: .now() + 0.15, repeating: 0.15)
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                let mixed = self.mixer.drainMixed(flushAll: false)
                if !mixed.isEmpty {
                    self.writeSamplesLocked(mixed)
                }
            }
            timer.resume()
            self.flushTimer = timer
        }
    }

    private func writeSamplesLocked(_ samples: [Float]) {
        guard let file = backupAudioFile, !samples.isEmpty else { return }
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ), let outBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            return
        }
        outBuf.frameLength = AVAudioFrameCount(samples.count)
        if let dst = outBuf.floatChannelData?[0] {
            samples.withUnsafeBufferPointer { src in
                if let base = src.baseAddress {
                    dst.update(from: base, count: samples.count)
                }
            }
            try? file.write(from: outBuf)
        }
    }

    /// Lightweight PCM buffer copy so resampling & mixer locking run off the real-time audio callback thread.
    private static func copyPCMBuffer(_ source: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let frames = source.frameLength
        guard frames > 0, let copy = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: frames) else {
            return nil
        }
        copy.frameLength = frames
        let channelCount = Int(source.format.channelCount)
        if let srcFloat = source.floatChannelData, let dstFloat = copy.floatChannelData {
            let bytes = Int(frames) * MemoryLayout<Float>.size
            if source.format.isInterleaved {
                memcpy(dstFloat[0], srcFloat[0], bytes * channelCount)
            } else {
                for ch in 0..<channelCount {
                    memcpy(dstFloat[ch], srcFloat[ch], bytes)
                }
            }
            return copy
        }
        if let srcInt16 = source.int16ChannelData, let dstInt16 = copy.int16ChannelData {
            let bytes = Int(frames) * MemoryLayout<Int16>.size
            if source.format.isInterleaved {
                memcpy(dstInt16[0], srcInt16[0], bytes * channelCount)
            } else {
                for ch in 0..<channelCount {
                    memcpy(dstInt16[ch], srcInt16[ch], bytes)
                }
            }
            return copy
        }
        return nil
    }
}
