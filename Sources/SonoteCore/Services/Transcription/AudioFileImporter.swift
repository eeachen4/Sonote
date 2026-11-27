import Foundation
import AVFoundation

public enum AudioFileImportError: LocalizedError {
    case unreadableMedia(String)
    case noAudioTrack

    public var errorDescription: String? {
        switch self {
        case .unreadableMedia(let msg): return "无法读取音视频文件：\(msg)"
        case .noAudioTrack: return "该文件中未找到音轨。"
        }
    }
}

public struct AudioFileImportProgress: Sendable {
    public var fraction: Double
    public var message: String

    public init(fraction: Double, message: String) {
        self.fraction = fraction
        self.message = message
    }
}

/// Decodes local audio/video files (.m4a, .mp3, .wav, .mp4, .mov) to 16 kHz mono Float32 PCM,
/// segments speech via Silero VAD, optionally runs Sortformer multi-speaker diarization,
/// and transcribes every utterance via MLX Qwen3-ASR.
public enum AudioFileImporter {

    public static let videoFileExtensions: Set<String> = ["mp4", "mov", "m4v", "mkv", "avi", "webm"]

    /// Copies pure audio files directly or extracts a lightweight `.m4a` audio track from video files
    /// so playback is universally fast and disk footprint stays small.
    public static func preparePlayableAudioBackup(from sourceURL: URL, destinationBaseURL: URL) async throws -> URL {
        let ext = sourceURL.pathExtension.lowercased()
        let isVideo = videoFileExtensions.contains(ext)

        if !isVideo {
            let finalExt = ext.isEmpty ? "m4a" : ext
            let dest = destinationBaseURL.deletingPathExtension().appendingPathExtension(finalExt)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: sourceURL, to: dest)
            return dest
        }

        let m4aDest = destinationBaseURL.deletingPathExtension().appendingPathExtension("m4a")
        try? FileManager.default.removeItem(at: m4aDest)

        // Fast path: native AVAssetExportSession audio-only M4A extraction
        let asset = AVURLAsset(url: sourceURL)
        if let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) {
            do {
                try await exporter.export(to: m4aDest, as: .m4a)
                if FileManager.default.fileExists(atPath: m4aDest.path) {
                    return m4aDest
                }
            } catch {
                try? FileManager.default.removeItem(at: m4aDest)
            }
        }

        // Bulletproof fallback: decode audio track to 16 kHz PCM and encode compact AAC .m4a
        let (samples, _) = try await decodeToMono16kSamples(url: sourceURL)
        try writeMono16kSamplesToM4A(samples: samples, destinationURL: m4aDest)
        return m4aDest
    }

    public static func writeMono16kSamplesToM4A(samples: [Float], destinationURL: URL) throws {
        try? FileManager.default.removeItem(at: destinationURL)
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let file = try AVAudioFile(forWriting: destinationURL, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false) else {
            throw AudioFileImportError.unreadableMedia("无法初始化音频编码格式")
        }

        let chunkSize = 16_000 * 4
        var offset = 0
        while offset < samples.count {
            let count = min(chunkSize, samples.count - offset)
            guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else { break }
            buf.frameLength = AVAudioFrameCount(count)
            if let dst = buf.floatChannelData?[0] {
                samples.withUnsafeBufferPointer { src in
                    if let base = src.baseAddress {
                        dst.update(from: base.advanced(by: offset), count: count)
                    }
                }
                try file.write(from: buf)
            }
            offset += count
        }
    }

    public static func decodeToMono16kSamples(url: URL) async throws -> (samples: [Float], duration: TimeInterval) {
        let asset = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = audioTracks.first else {
            throw AudioFileImportError.noAudioTrack
        }
        let durationTime = try await asset.load(.duration)
        let durationSec = max(0, CMTimeGetSeconds(durationTime))

        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let trackOutput = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        trackOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(trackOutput) else {
            throw AudioFileImportError.unreadableMedia("无法配置音频解码器")
        }
        reader.add(trackOutput)

        guard reader.startReading() else {
            throw AudioFileImportError.unreadableMedia(reader.error?.localizedDescription ?? "解码启动失败")
        }

        var samples: [Float] = []
        if durationSec > 0 {
            samples.reserveCapacity(Int(durationSec * 16_000) + 16_000)
        }

        while reader.status == .reading {
            guard let sampleBuffer = trackOutput.copyNextSampleBuffer() else { break }
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let length = CMBlockBufferGetDataLength(blockBuffer)
            guard length > 0 else { continue }

            var rawData = Data(count: length)
            rawData.withUnsafeMutableBytes { ptr in
                if let base = ptr.baseAddress {
                    _ = CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: base)
                }
            }
            let floatCount = length / MemoryLayout<Float>.size
            rawData.withUnsafeBytes { rawPtr in
                let floats = rawPtr.bindMemory(to: Float.self)
                samples.append(contentsOf: floats.prefix(floatCount))
            }
        }

        if reader.status == .failed {
            throw AudioFileImportError.unreadableMedia(reader.error?.localizedDescription ?? "音频读取中断")
        }

        let computedDuration = durationSec > 0 ? durationSec : Double(samples.count) / 16_000.0
        return (samples, computedDuration)
    }

    public static func transcribeMediaFile(
        url: URL,
        settings: AppSettings,
        extraHotwords: String = "",
        voiceprintProfiles: [VoiceprintProfile] = [],
        onProgress: @escaping @Sendable (AudioFileImportProgress) -> Void,
        onMLXState: (@Sendable (MLXModelState) -> Void)? = nil
    ) async throws -> (segments: [TranscriptSegment], duration: TimeInterval) {
        onProgress(AudioFileImportProgress(fraction: 0.05, message: "正在解码音视频文件..."))
        let (samples, duration) = try await decodeToMono16kSamples(url: url)

        onProgress(AudioFileImportProgress(fraction: 0.14, message: "正在进行人声端点检测 (VAD)..."))
        let speechSegments = await MLXQwen3ASREngine.shared.segmentAudio(
            samples: samples,
            useNeuralVAD: settings.enableNeuralVAD,
            vadModelID: settings.sileroVADModelID,
            hfHost: settings.mlxHuggingFaceHost,
            maxChunkSeconds: 18.0
        )

        guard !speechSegments.isEmpty else {
            return ([], duration)
        }

        var transcripts: [TranscriptSegment] = []
        var rollingTail = ""
        let total = speechSegments.count

        for (idx, seg) in speechSegments.enumerated() {
            let progress = 0.18 + 0.68 * (Double(idx) / Double(max(1, total)))
            let denoiseNote = settings.enableSpeechEnhancement ? "（降噪增强）" : ""
            onProgress(AudioFileImportProgress(
                fraction: progress,
                message: "正在使用 Qwen3-ASR 离线转写\(denoiseNote) (\(idx + 1)/\(total))..."
            ))

            let context = [settings.asrContextHint, extraHotwords, rollingTail]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")

            let text = try await MLXQwen3ASREngine.shared.transcribe(
                samples: seg.samples,
                language: settings.transcriptionLanguage,
                context: context,
                modelID: settings.mlxQwen3ModelID,
                hfHost: settings.mlxHuggingFaceHost,
                useNeuralVADGate: false,
                enableSpeechEnhancement: settings.enableSpeechEnhancement,
                speechEnhancementModelID: settings.speechEnhancementModelID,
                onStateChange: onMLXState
            )
            if !text.isEmpty {
                rollingTail = String(text.suffix(100))
                transcripts.append(TranscriptSegment(
                    timestamp: seg.startSeconds,
                    speaker: .mixed,
                    text: text
                ))
            }
        }

        if settings.enableSpeakerDiarization && !transcripts.isEmpty {
            if settings.diarizationStrategy == .voiceprintClusteringUnlimited {
                onProgress(AudioFileImportProgress(fraction: 0.88, message: "正在进行 ECAPA 声纹聚类（支持 5~12 人）..."))
                let result = await SpeakerDiarizerService.diarizeByVoiceprintClustering(
                    segments: transcripts,
                    fullSamples16k: samples,
                    meetingDuration: duration,
                    profiles: settings.autoIdentifyVoiceprints ? voiceprintProfiles : [],
                    matchThreshold: settings.voiceprintMatchThreshold,
                    voiceprintModelID: settings.voiceprintModelID,
                    hfHost: settings.mlxHuggingFaceHost,
                    localUserName: settings.localUserName,
                    autoUnloadVoiceprintModel: settings.mlxAutoUnloadAfterMeeting
                )
                transcripts = result.segments
            } else {
                onProgress(AudioFileImportProgress(fraction: 0.88, message: "正在识别多说话人声纹 (Sortformer + ECAPA)..."))
                if let diarization = try? await SpeakerDiarizerService.shared.diarize(
                    samples16k: samples,
                    modelID: settings.diarizationModelID,
                    hfHost: settings.mlxHuggingFaceHost
                ) {
                    if settings.autoIdentifyVoiceprints && !voiceprintProfiles.isEmpty {
                        let result = await SpeakerDiarizerService.assignSpeakerLabelsWithVoiceprints(
                            segments: transcripts,
                            diarization: diarization,
                            fullSamples16k: samples,
                            profiles: voiceprintProfiles,
                            matchThreshold: settings.voiceprintMatchThreshold,
                            voiceprintModelID: settings.voiceprintModelID,
                            hfHost: settings.mlxHuggingFaceHost,
                            localUserName: settings.localUserName,
                            autoUnloadVoiceprintModel: settings.mlxAutoUnloadAfterMeeting
                        )
                        transcripts = result.segments
                    } else {
                        transcripts = SpeakerDiarizerService.assignSpeakerLabels(
                            segments: transcripts,
                            diarization: diarization,
                            localUserName: settings.localUserName
                        )
                    }
                    if settings.mlxAutoUnloadAfterMeeting {
                        await SpeakerDiarizerService.shared.unload()
                    }
                }
            }
        }

        if settings.mlxAutoUnloadAfterMeeting {
            await MLXQwen3ASREngine.shared.unloadModel(onStateChange: onMLXState)
            if settings.enableSpeechEnhancement {
                await SpeechEnhancementService.shared.unload()
            }
        }

        onProgress(AudioFileImportProgress(fraction: 0.95, message: "转写完成，正在生成智能纪要..."))
        return (transcripts, duration)
    }
}
