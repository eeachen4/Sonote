import Foundation
import AVFoundation

/// Synchronized media player for completed meetings, powering click-to-seek transcript playback.
/// Uses AVPlayer so both audio (.m4a/.mp3/.wav) and video (.mp4/.mov) files play reliably.
@MainActor
final class MeetingAudioPlayer: NSObject, ObservableObject {
    @Published var isPlaying: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var playbackRate: Float = 1.0
    @Published var loadedFilePath: String?
    @Published var waveformSamples: [Float] = []

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var durationLoadTask: Task<Void, Never>?
    private var waveformLoadTask: Task<Void, Never>?

    static let availableRates: [Float] = [1.0, 1.25, 1.5, 2.0]

    deinit {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    func loadIfNeeded(path: String?) {
        guard loadedFilePath != path else { return }
        stop()
        loadedFilePath = path
        guard let path, FileManager.default.fileExists(atPath: path) else {
            duration = 0
            return
        }

        let url = URL(fileURLWithPath: path)
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        let avPlayer = AVPlayer(playerItem: item)
        avPlayer.actionAtItemEnd = .pause
        self.player = avPlayer
        self.currentTime = 0
        self.duration = 0

        // Load exact asset duration asynchronously
        durationLoadTask = Task { [weak self] in
            if let cmDuration = try? await asset.load(.duration) {
                let sec = CMTimeGetSeconds(cmDuration)
                if sec.isFinite && sec > 0 {
                    await MainActor.run { [weak self] in
                        guard let self, self.loadedFilePath == path else { return }
                        self.duration = sec
                    }
                }
            }
        }

        // Compute normalized waveform amplitude bins off the main thread for visual scrubbing
        waveformLoadTask?.cancel()
        waveformSamples = []
        waveformLoadTask = Task.detached(priority: .utility) { [weak self] in
            let bins = Self.extractWaveformBins(from: url, binCount: 88)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self, self.loadedFilePath == path else { return }
                self.waveformSamples = bins
            }
        }

        let interval = CMTime(seconds: 0.12, preferredTimescale: 600)
        timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] cmTime in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let sec = CMTimeGetSeconds(cmTime)
                if sec.isFinite && sec >= 0 {
                    self.currentTime = sec
                }
                if self.duration <= 0, let itemDuration = self.player?.currentItem?.duration {
                    let durSec = CMTimeGetSeconds(itemDuration)
                    if durSec.isFinite && durSec > 0 {
                        self.duration = durSec
                    }
                }
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isPlaying = false
                if self.duration > 0 {
                    self.currentTime = self.duration
                }
            }
        }
    }

    func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if duration > 0 && currentTime >= duration - 0.15 {
                let zero = CMTime.zero
                player.seek(to: zero, toleranceBefore: .zero, toleranceAfter: .zero)
                currentTime = 0
            }
            player.playImmediately(atRate: playbackRate)
            isPlaying = true
        }
    }

    func seek(to time: TimeInterval, autoPlay: Bool = false) {
        guard let player else { return }
        let maxTime = duration > 0 ? duration : max(time, 0)
        let clamped = max(0, min(maxTime, time))
        let target = CMTime(seconds: clamped, preferredTimescale: 600)
        currentTime = clamped
        player.seek(to: target, toleranceBefore: CMTime(seconds: 0.05, preferredTimescale: 600), toleranceAfter: CMTime(seconds: 0.05, preferredTimescale: 600))
        if autoPlay {
            player.playImmediately(atRate: playbackRate)
            isPlaying = true
        }
    }

    func cycleRate() {
        if let idx = Self.availableRates.firstIndex(of: playbackRate) {
            playbackRate = Self.availableRates[(idx + 1) % Self.availableRates.count]
        } else {
            playbackRate = 1.0
        }
        if let player, isPlaying {
            player.rate = playbackRate
        }
    }

    func stop() {
        durationLoadTask?.cancel()
        durationLoadTask = nil
        waveformLoadTask?.cancel()
        waveformLoadTask = nil
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        loadedFilePath = nil
        waveformSamples = []
    }

    /// Reads mono/multi-channel audio frames into `binCount` normalized RMS bars (`0.08...1.0`).
    nonisolated static func extractWaveformBins(from url: URL, binCount: Int = 88) -> [Float] {
        guard binCount > 0, let file = try? AVAudioFile(forReading: url) else { return [] }
        let totalFrames = Int(file.length)
        guard totalFrames > 0 else { return [] }

        let format = file.processingFormat
        let framesPerBin = max(1, totalFrames / binCount)
        let chunkSize = min(65_536, max(4096, framesPerBin))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(chunkSize)) else {
            return []
        }

        var rawBins = [Float](repeating: 0, count: binCount)
        var counts = [Int](repeating: 0, count: binCount)
        var globalFrame = 0

        while globalFrame < totalFrames {
            let remaining = totalFrames - globalFrame
            let toRead = AVAudioFrameCount(min(chunkSize, remaining))
            do {
                try file.read(into: buffer, frameCount: toRead)
            } catch {
                break
            }
            let readCount = Int(buffer.frameLength)
            if readCount == 0 { break }

            if let channelData = buffer.floatChannelData {
                let ptr = channelData[0]
                // Stride for fast decoding on 1-2h recordings while keeping visual accuracy
                let strideStep = max(1, readCount / 2048)
                var i = 0
                while i < readCount {
                    let binIdx = min(binCount - 1, (globalFrame + i) * binCount / totalFrames)
                    let s = ptr[i]
                    rawBins[binIdx] += s * s
                    counts[binIdx] += 1
                    i += strideStep
                }
            }
            globalFrame += readCount
        }

        var rmsBins = [Float](repeating: 0, count: binCount)
        var maxRMS: Float = 0.0001
        for i in 0..<binCount {
            if counts[i] > 0 {
                let rms = sqrt(rawBins[i] / Float(counts[i]))
                rmsBins[i] = rms
                if rms > maxRMS { maxRMS = rms }
            }
        }
        return rmsBins.map { val in
            let normalized = pow(min(1.0, val / maxRMS), 0.72)
            return max(0.10, min(1.0, normalized))
        }
    }

    static func formatTime(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}
