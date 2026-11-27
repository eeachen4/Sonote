import Foundation
import AVFoundation

/// Cross-track acoustic echo / bleed deduplicator for loudspeaker meetings:
/// detects when the microphone (`me`) captures a near-duplicate of recent system audio (`remote`).
public final class EchoDeduplicator: @unchecked Sendable {
    private let lock = NSLock()
    private var recentSegments: [(speaker: SpeakerSource, timestamp: TimeInterval, normalized: String)] = []
    private let windowSeconds: TimeInterval

    public init(windowSeconds: TimeInterval = 4.5) {
        self.windowSeconds = windowSeconds
    }

    public func reset() {
        lock.withLock { recentSegments.removeAll() }
    }

    /// Returns `true` if `candidate` is an acoustic bleed duplicate of an opposite-channel segment.
    public func shouldDropAsEcho(_ candidate: TranscriptSegment) -> Bool {
        let norm = Self.normalize(candidate.text)
        guard norm.count >= 4 else { return false }

        return lock.withLock {
            // Prune entries outside time window
            recentSegments.removeAll { abs(candidate.timestamp - $0.timestamp) > windowSeconds }

            // Primarily suppress mic (.me) echoing recent remote (.remote) speaker audio,
            // or exact duplicate within window across channels
            for entry in recentSegments where entry.speaker != candidate.speaker {
                let sim = Self.diceSimilarity(entry.normalized, norm)
                let isContained = entry.normalized.contains(norm) || norm.contains(entry.normalized)
                if sim >= 0.72 || (isContained && min(entry.normalized.count, norm.count) >= 6) {
                    // Prefer keeping `.remote` over `.me` bleed; if `.remote` arrived slightly after `.me`, still suppress duplicate
                    return true
                }
            }

            recentSegments.append((speaker: candidate.speaker, timestamp: candidate.timestamp, normalized: norm))
            return false
        }
    }

    public static func normalize(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    public static func diceSimilarity(_ a: String, _ b: String) -> Double {
        if a == b { return 1.0 }
        let charsA = Array(a)
        let charsB = Array(b)
        guard charsA.count >= 2 && charsB.count >= 2 else { return 0 }

        var countsA: [String: Int] = [:]
        for i in 0..<(charsA.count - 1) {
            let bg = String([charsA[i], charsA[i + 1]])
            countsA[bg, default: 0] += 1
        }
        var overlap = 0
        for i in 0..<(charsB.count - 1) {
            let bg = String([charsB[i], charsB[i + 1]])
            if let rem = countsA[bg], rem > 0 {
                overlap += 1
                countsA[bg] = rem - 1
            }
        }
        let total = (charsA.count - 1) + (charsB.count - 1)
        return total > 0 ? (2.0 * Double(overlap) / Double(total)) : 0
    }
}

/// Coordinates dual-track real-time transcription (System Audio = Remote, Microphone = Me),
/// supporting MLX Qwen3-ASR (+ Silero VAD), Apple Speech, OpenAI Transcribe, and cross-track echo dedup.
public final class TranscriptionCoordinator: @unchecked Sendable {
    private var remoteTranscriber: AudioTrackTranscriber?
    private var micTranscriber: AudioTrackTranscriber?
    private let echoDeduplicator = EchoDeduplicator()
    private var sessionStartDate: Date = Date()
    private var activeSettings: AppSettings = AppSettings()

    public var onVolatileUpdate: (@Sendable (SpeakerSource, String) -> Void)?
    public var onCommittedSegment: (@Sendable (TranscriptSegment) -> Void)?
    public var onStatusNotice: (@Sendable (String) -> Void)?
    public var onMLXModelStateChange: (@Sendable (MLXModelState) -> Void)?

    public init() {}

    public func start(
        settings: AppSettings,
        captureRemote: Bool,
        captureMic: Bool,
        sessionStartDate: Date,
        extraContextHint: String = "",
        voiceprintProfiles: [VoiceprintProfile] = []
    ) async -> [String] {
        self.sessionStartDate = sessionStartDate
        self.activeSettings = settings
        self.echoDeduplicator.reset()
        var notices: [String] = []

        var mlxReady = false
        if settings.transcriptionEngine == .mlxQwen3ASR {
            do {
                _ = try await MLXQwen3ASREngine.shared.ensureLoaded(
                    modelID: settings.mlxQwen3ModelID,
                    hfHost: settings.mlxHuggingFaceHost,
                    onStateChange: onMLXModelStateChange
                )
                mlxReady = true
            } catch {
                let fallbackNotice = "MLX Qwen3-ASR 加载失败（已自动回退到 Apple 本机识别）：\(error.localizedDescription)"
                notices.append(fallbackNotice)
                onStatusNotice?(fallbackNotice)
            }
        }

        let liveBank: OnlineSpeakerClusterBank? = settings.enableLiveSpeakerDiarization
            ? OnlineSpeakerClusterBank(
                enrolledProfiles: voiceprintProfiles,
                knownMatchThreshold: settings.voiceprintMatchThreshold,
                newClusterThreshold: 0.58
            )
            : nil

        if captureRemote {
            let (transcriber, notice) = await startTrack(
                speaker: .remote,
                settings: settings,
                mlxReady: mlxReady,
                extraContextHint: extraContextHint,
                liveSpeakerBank: liveBank
            )
            remoteTranscriber = transcriber
            if let notice { notices.append(notice) }
        }

        if captureMic {
            let (transcriber, notice) = await startTrack(
                speaker: .me,
                settings: settings,
                mlxReady: mlxReady,
                extraContextHint: extraContextHint,
                liveSpeakerBank: nil
            )
            micTranscriber = transcriber
            if let notice { notices.append(notice) }
        }

        return notices
    }

    public func feedSystemAudio(_ buffer: AVAudioPCMBuffer) {
        remoteTranscriber?.append(buffer: buffer)
    }

    public func feedMicrophoneAudio(_ buffer: AVAudioPCMBuffer) {
        micTranscriber?.append(buffer: buffer)
    }

    public func stop() async {
        await remoteTranscriber?.stop()
        await micTranscriber?.stop()
        remoteTranscriber = nil
        micTranscriber = nil

        if activeSettings.transcriptionEngine == .mlxQwen3ASR && activeSettings.mlxAutoUnloadAfterMeeting {
            await MLXQwen3ASREngine.shared.unloadModel(onStateChange: onMLXModelStateChange)
        }
        if activeSettings.enableSpeechEnhancement && activeSettings.mlxAutoUnloadAfterMeeting {
            await SpeechEnhancementService.shared.unload()
        }
        if activeSettings.enableLiveSpeakerDiarization && activeSettings.mlxAutoUnloadAfterMeeting {
            await VoiceprintService.shared.unload()
        }
    }

    private func startTrack(
        speaker: SpeakerSource,
        settings: AppSettings,
        mlxReady: Bool,
        extraContextHint: String,
        liveSpeakerBank: OnlineSpeakerClusterBank?
    ) async -> (AudioTrackTranscriber?, String?) {
        let customLocalName = settings.localUserName.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultLabel: String? = (speaker == .me && !customLocalName.isEmpty) ? customLocalName : nil

        let volatileHandler: @Sendable (String) -> Void = { [weak self] text in
            self?.onVolatileUpdate?(speaker, text)
        }
        let commitWithLabel: @Sendable (String, String?) -> Void = { [weak self] text, dynamicLabel in
            guard let self else { return }
            let elapsed = max(0, Date().timeIntervalSince(self.sessionStartDate))
            let segment = TranscriptSegment(
                timestamp: elapsed,
                createdAt: Date(),
                speaker: speaker,
                speakerLabel: dynamicLabel ?? defaultLabel,
                text: text
            )
            if self.activeSettings.enableEchoDeduplication && self.echoDeduplicator.shouldDropAsEcho(segment) {
                return
            }
            self.onCommittedSegment?(segment)
        }
        let finalHandler: @Sendable (String) -> Void = { text in
            commitWithLabel(text, nil)
        }
        let statusHandler: @Sendable (String) -> Void = { [weak self] msg in
            self?.onStatusNotice?(msg)
        }

        if settings.transcriptionEngine == .mlxQwen3ASR && mlxReady {
            let mlxTrack = MLXQwen3TrackTranscriber(
                speaker: speaker,
                settings: settings,
                extraContextHint: extraContextHint,
                engine: .shared,
                liveSpeakerBank: liveSpeakerBank,
                onFinalSegmentWithSpeaker: commitWithLabel,
                onModelStateChange: onMLXModelStateChange
            )
            do {
                try await mlxTrack.start(
                    onVolatileText: volatileHandler,
                    onFinalSegment: finalHandler,
                    onStatusMessage: statusHandler
                )
                return (mlxTrack, nil)
            } catch {
                statusHandler("[\(speaker.shortLabel)] MLX 引擎初始化失败，切换系统识别：\(error.localizedDescription)")
            }
        }

        if settings.transcriptionEngine == .openAITranscribe {
            if let cred = try? AuthManager.shared.resolveCredential(settings: settings), cred.supportsOpenAIAudioAPI {
                let openAI = OpenAIChunkTranscriber(speaker: speaker, settings: settings)
                do {
                    try await openAI.start(
                        onVolatileText: volatileHandler,
                        onFinalSegment: finalHandler,
                        onStatusMessage: statusHandler
                    )
                    return (openAI, nil)
                } catch {
                    return (nil, "[\(speaker.shortLabel)] OpenAI 转写启动失败：\(error.localizedDescription)")
                }
            } else {
                statusHandler("当前使用 Codex Auth，自动切换为 Apple 本机实时语音识别。")
            }
        }

        if #available(macOS 26.0, *) {
            let modern = ModernSpeechAnalyzerTranscriber(speaker: speaker, language: settings.transcriptionLanguage)
            do {
                try await modern.start(
                    onVolatileText: volatileHandler,
                    onFinalSegment: finalHandler,
                    onStatusMessage: statusHandler
                )
                return (modern, nil)
            } catch {
                statusHandler("[\(speaker.shortLabel)] \(error.localizedDescription)")
            }
        }

        let legacy = LegacySpeechTranscriber(speaker: speaker, language: settings.transcriptionLanguage)
        do {
            try await legacy.start(
                onVolatileText: volatileHandler,
                onFinalSegment: finalHandler,
                onStatusMessage: statusHandler
            )
            return (legacy, nil)
        } catch {
            return (nil, "[\(speaker.shortLabel)] 语音转写启动失败：\(error.localizedDescription)")
        }
    }
}
