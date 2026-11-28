import Foundation
import AVFoundation

/// Extracts normalized RMS amplitude bins and duration from audio or video files.
/// Uses fast `AVAudioFile` decoding first and falls back to `AVAssetReader` for video containers (`.mp4`, `.mov`, etc.).
public enum AudioWaveformExtractor {
    public struct Result: Sendable, Equatable {
        public let bins: [Float]
        public let duration: TimeInterval

        public init(bins: [Float], duration: TimeInterval) {
            self.bins = bins
            self.duration = duration
        }
    }

    public static func extract(from url: URL, binCount: Int = 88) -> Result {
        guard binCount > 0 else { return Result(bins: [], duration: 0) }
        if let fast = extractWithAVAudioFile(from: url, binCount: binCount), !fast.bins.isEmpty {
            return fast
        }
        if let reader = extractWithAVAssetReader(from: url, binCount: binCount), !reader.bins.isEmpty {
            return reader
        }
        return Result(bins: [], duration: 0)
    }

    public static func extractBins(from url: URL, binCount: Int = 88) -> [Float] {
        extract(from: url, binCount: binCount).bins
    }

    // MARK: - Fast Path: AVAudioFile (.wav, .m4a, .mp3, .aac, .caf, .flac)

    private static func extractWithAVAudioFile(from url: URL, binCount: Int) -> Result? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let totalFrames = Int(file.length)
        guard totalFrames > 0 else { return nil }

        let format = file.processingFormat
        let duration = format.sampleRate > 0 ? Double(totalFrames) / format.sampleRate : 0
        let framesPerBin = max(1, totalFrames / binCount)
        let chunkSize = min(65_536, max(4096, framesPerBin))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(chunkSize)) else {
            return nil
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

        guard globalFrame > 0 else { return nil }
        return Result(bins: normalize(rawBins: rawBins, counts: counts), duration: duration)
    }

    // MARK: - Universal Fallback: AVAssetReader (.mp4, .mov, multi-track containers)

    private static func extractWithAVAssetReader(from url: URL, binCount: Int) -> Result? {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .audio).first else { return nil }
        guard let reader = try? AVAssetReader(asset: asset) else { return nil }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 16_000
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }

        let durationSec = CMTimeGetSeconds(asset.duration)
        let validDuration = durationSec.isFinite && durationSec > 0 ? durationSec : 0

        // Downsample into fine buckets during streaming, then collapse to `binCount`
        var chunkRMS: [Float] = []
        chunkRMS.reserveCapacity(binCount * 8)

        while reader.status == .reading, let sampleBuffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let length = CMBlockBufferGetDataLength(blockBuffer)
            let sampleCount = length / MemoryLayout<Float>.size
            guard sampleCount > 0 else { continue }

            var floats = [Float](repeating: 0, count: sampleCount)
            CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: sampleCount * MemoryLayout<Float>.size, destination: &floats)

            let subWindow = max(256, sampleCount / 4)
            var offset = 0
            while offset < sampleCount {
                let end = min(sampleCount, offset + subWindow)
                var sumSq: Float = 0
                let strideStep = max(1, (end - offset) / 512)
                var count = 0
                var idx = offset
                while idx < end {
                    let s = floats[idx]
                    sumSq += s * s
                    count += 1
                    idx += strideStep
                }
                if count > 0 {
                    chunkRMS.append(sqrt(sumSq / Float(count)))
                }
                offset = end
            }
        }

        guard !chunkRMS.isEmpty else { return nil }

        var rawBins = [Float](repeating: 0, count: binCount)
        var counts = [Int](repeating: 0, count: binCount)
        for (idx, rms) in chunkRMS.enumerated() {
            let binIdx = min(binCount - 1, idx * binCount / chunkRMS.count)
            rawBins[binIdx] += rms * rms
            counts[binIdx] += 1
        }
        return Result(bins: normalize(rawBins: rawBins, counts: counts), duration: validDuration)
    }

    private static func normalize(rawBins: [Float], counts: [Int]) -> [Float] {
        var rmsBins = [Float](repeating: 0, count: rawBins.count)
        var maxRMS: Float = 0.0001
        for i in 0..<rawBins.count {
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
}
