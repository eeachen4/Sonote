import Foundation
import AVFoundation

public enum WAVEncoder {
    /// Converts Float32 mono/multi-channel PCM buffer into 16kHz mono 16-bit PCM WAV data.
    public static func encodeMono16kWAV(samples: [Float], sampleRate: Double = 16_000) -> Data {
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = numChannels * (bitsPerSample / 8)
        let dataSize = UInt32(samples.count * MemoryLayout<Int16>.size)
        let chunkSize = 36 + dataSize

        var data = Data(capacity: Int(44 + dataSize))
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        appendLittleEndian(&data, chunkSize)
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
        data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        appendLittleEndian(&data, UInt32(16))             // PCM subchunk size
        appendLittleEndian(&data, UInt16(1))              // AudioFormat = PCM
        appendLittleEndian(&data, numChannels)
        appendLittleEndian(&data, UInt32(sampleRate))
        appendLittleEndian(&data, byteRate)
        appendLittleEndian(&data, blockAlign)
        appendLittleEndian(&data, bitsPerSample)
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        appendLittleEndian(&data, dataSize)

        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let int16 = Int16(clamped * Float(Int16.max))
            appendLittleEndian(&data, int16)
        }
        return data
    }

    public static func computeRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let floatData = buffer.floatChannelData else { return 0 }
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameLength > 0, channelCount > 0 else { return 0 }

        var sumSquares: Float = 0
        for ch in 0..<channelCount {
            let channelPtr = floatData[ch]
            for i in 0..<frameLength {
                let v = channelPtr[i]
                sumSquares += v * v
            }
        }
        let rms = sqrt(sumSquares / Float(frameLength * channelCount))
        // Normalize perceptual loudness for UI level meter (0...1)
        return min(1.0, max(0.0, rms * 4.5))
    }

    public static func extractMono16kSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ) else { return [] }

        if buffer.format.sampleRate == 16_000,
           buffer.format.channelCount == 1,
           buffer.format.commonFormat == .pcmFormatFloat32,
           let ptr = buffer.floatChannelData?[0] {
            return Array(UnsafeBufferPointer(start: ptr, count: Int(buffer.frameLength)))
        }

        guard let converter = AVAudioConverter(from: buffer.format, to: targetFormat) else {
            return []
        }

        let ratio = 16_000.0 / max(1.0, buffer.format.sampleRate)
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            return []
        }

        var consumed = false
        var error: NSError?
        let status = converter.convert(to: outBuffer, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, error == nil, let ptr = outBuffer.floatChannelData?[0] else {
            return []
        }
        return Array(UnsafeBufferPointer(start: ptr, count: Int(outBuffer.frameLength)))
    }

    /// Resamples mono Float32 PCM samples between arbitrary sample rates (e.g. 16 kHz <-> 48 kHz for DeepFilterNet3).
    public static func resampleMono(samples: [Float], from sourceRate: Double, to targetRate: Double) -> [Float] {
        guard !samples.isEmpty, sourceRate > 0, targetRate > 0 else { return samples }
        if abs(sourceRate - targetRate) < 1.0 { return samples }

        guard let inFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sourceRate, channels: 1, interleaved: false),
              let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: targetRate, channels: 1, interleaved: false),
              let inBuffer = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: AVAudioFrameCount(samples.count)),
              let converter = AVAudioConverter(from: inFormat, to: outFormat) else {
            return samples
        }

        inBuffer.frameLength = AVAudioFrameCount(samples.count)
        if let dst = inBuffer.floatChannelData?[0] {
            samples.withUnsafeBufferPointer { src in
                if let base = src.baseAddress {
                    dst.update(from: base, count: samples.count)
                }
            }
        }

        let ratio = targetRate / sourceRate
        let outCapacity = AVAudioFrameCount(ceil(Double(samples.count) * ratio)) + 128
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: outCapacity) else {
            return samples
        }

        var consumed = false
        var err: NSError?
        let status = converter.convert(to: outBuffer, error: &err) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return inBuffer
        }

        guard status != .error, err == nil, let outPtr = outBuffer.floatChannelData?[0] else {
            return samples
        }
        return Array(UnsafeBufferPointer(start: outPtr, count: Int(outBuffer.frameLength)))
    }

    private static func appendLittleEndian<T: FixedWidthInteger>(_ data: inout Data, _ value: T) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }
}
