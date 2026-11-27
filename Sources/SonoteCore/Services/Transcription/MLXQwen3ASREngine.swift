import Foundation
import AVFoundation
import MLX
import MLXAudioCore
import MLXAudioSTT
import MLXAudioVAD
import HuggingFace

public enum MLXModelState: Equatable, Sendable {
    case idle
    case downloading(progress: Double, message: String)
    case loading(message: String)
    case ready(modelID: String, peakMemoryGB: Double)
    case failed(String)

    public var statusText: String {
        switch self {
        case .idle:
            return SonoteLocale.t("未加载（录制时按需加载，待机不占内存）", "Idle (loads on demand; 0 MB idle GPU memory)")
        case .downloading(let progress, let msg):
            if progress > 0 && progress <= 1.0 {
                return "\(msg) (\(Int(progress * 100))%)"
            }
            return msg
        case .loading(let msg):
            return msg
        case .ready(let modelID, let peakGB):
            let shortName = modelID.split(separator: "/").last.map(String.init) ?? modelID
            if peakGB > 0.05 {
                return SonoteLocale.isEnglish
                    ? String(format: "Ready · %@ (peak %.2f GB)", shortName, peakGB)
                    : String(format: "已就绪 · %@ (峰值 %.2f GB)", shortName, peakGB)
            }
            return SonoteLocale.t("已就绪 · \(shortName)", "Ready · \(shortName)")
        case .failed(let err):
            return SonoteLocale.t("加载失败：\(err)", "Load failed: \(err)")
        }
    }

    public var isBusy: Bool {
        switch self {
        case .downloading, .loading: return true
        default: return false
        }
    }

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

public struct SpeechAudioSegment: Sendable {
    public var startSeconds: TimeInterval
    public var endSeconds: TimeInterval
    public var samples: [Float]

    public init(startSeconds: TimeInterval, endSeconds: TimeInterval, samples: [Float]) {
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.samples = samples
    }
}

/// Shared actor managing a single Qwen3-ASR + optional Silero VAD MLX instance across both
/// System Audio & Mic tracks, serializing Metal GPU inference cleanly and freeing memory on demand.
public actor MLXQwen3ASREngine {
    public static let shared = MLXQwen3ASREngine()

    private var model: Qwen3ASRModel?
    private var loadedModelID: String?
    private var state: MLXModelState = .idle

    private var vadModel: SileroVAD?
    private var loadedVADModelID: String?
    private var vadLoadFailed = false
    private var streamingVADStates: [UUID: SileroVADStreamingState] = [:]

    public init() {}

    public func currentState() -> MLXModelState {
        state
    }

    public static func isModelCachedLocally(modelID: String) -> Bool {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let expanded = (trimmed as NSString).expandingTildeInPath
        if FileManager.default.fileExists(atPath: (expanded as NSString).appendingPathComponent("config.json")) {
            return true
        }

        let cacheDir = HubCache.default.cacheDirectory
        let subdirName = trimmed.replacingOccurrences(of: "/", with: "_")
        let mlxAudioDir = cacheDir.appendingPathComponent("mlx-audio/\(subdirName)")
        if directoryContainsSafetensors(mlxAudioDir) {
            return true
        }

        let hfModelDir = cacheDir.appendingPathComponent("models/\(trimmed)")
        if directoryContainsSafetensors(hfModelDir) {
            return true
        }

        return false
    }

    private static func directoryContainsSafetensors(_ dir: URL) -> Bool {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else {
            return false
        }
        return contents.contains { $0.hasSuffix(".safetensors") }
    }

    // MARK: - Silero Neural VAD (MLXAudioVAD)

    public func ensureVADLoaded(
        vadModelID: String = "mlx-community/silero-vad-v6",
        hfHost: String = "https://huggingface.co"
    ) async -> SileroVAD? {
        if let vadModel, loadedVADModelID == vadModelID {
            return vadModel
        }
        if vadLoadFailed && loadedVADModelID == vadModelID {
            return nil
        }

        let trimmed = vadModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetID = trimmed.isEmpty ? "mlx-community/silero-vad-v6" : trimmed
        guard let repoID = Repo.ID(rawValue: targetID) else { return nil }

        let hostURL = URL(string: hfHost.trimmingCharacters(in: .whitespacesAndNewlines)) ?? HubClient.defaultHost
        let hfToken = ProcessInfo.processInfo.environment["HF_TOKEN"]
        let client: HubClient = (hfToken?.isEmpty == false)
            ? HubClient(host: hostURL, bearerToken: hfToken!, cache: .default)
            : HubClient(host: hostURL, cache: .default)

        do {
            let modelDir = try await ModelUtils.resolveOrDownloadModel(
                client: client,
                cache: .default,
                repoID: repoID,
                requiredExtension: "safetensors"
            )
            let loaded = try SileroVAD.fromModelDirectory(modelDir)
            self.vadModel = loaded
            self.loadedVADModelID = targetID
            self.vadLoadFailed = false
            return loaded
        } catch {
            self.loadedVADModelID = targetID
            self.vadLoadFailed = true
            return nil
        }
    }

    /// Evaluates one or more 512-sample (32 ms @ 16 kHz) audio frames sequentially through Silero VAD's
    /// recurrent streaming LSTM state for a dedicated audio track. Returns `nil` if Silero VAD is unavailable.
    public func evaluateStreamingVADFrames(
        sessionID: UUID,
        chunks512: [[Float]],
        vadModelID: String,
        hfHost: String
    ) async -> [Float]? {
        guard !chunks512.isEmpty else { return [] }
        guard let vad = await ensureVADLoaded(vadModelID: vadModelID, hfHost: hfHost) else {
            return nil
        }
        do {
            var state = try streamingVADStates[sessionID] ?? vad.initialState(batchSize: 1, sampleRate: 16_000)
            var probs: [Float] = []
            probs.reserveCapacity(chunks512.count)
            for chunk in chunks512 where chunk.count == 512 {
                let (probArr, nextState) = try vad.feed(chunk: MLXArray(chunk), state: state, sampleRate: 16_000)
                state = nextState
                let p = probArr.asArray(Float.self).first ?? 0
                probs.append(p)
            }
            streamingVADStates[sessionID] = state
            return probs
        } catch {
            return nil
        }
    }

    public func removeStreamingVADSession(_ sessionID: UUID) {
        streamingVADStates.removeValue(forKey: sessionID)
    }

    /// Runs Silero neural VAD on a 16kHz PCM buffer and returns true if human speech is present
    /// (filtering keyboard clicks, fan noise, and dead air before invoking Qwen3-ASR).
    public func containsHumanSpeech(
        samples: [Float],
        vadModelID: String,
        hfHost: String,
        threshold: Float = 0.38
    ) async -> Bool {
        guard samples.count >= 1024 else { return false }
        guard let vad = await ensureVADLoaded(vadModelID: vadModelID, hfHost: hfHost) else {
            // Graceful fallback to energy gate when offline / VAD unavailable
            return true
        }
        do {
            let audio = MLXArray(samples)
            let probs = try vad.predictProba(audio, sampleRate: 16_000)
            let values = probs.asArray(Float.self)
            Memory.clearCache()
            guard !values.isEmpty else { return false }
            let speechFrames = values.filter { $0 >= threshold }.count
            // Require at least 2 speech frames (~64ms) or >8% speech ratio
            return speechFrames >= 2 || (Float(speechFrames) / Float(values.count)) >= 0.08
        } catch {
            return true
        }
    }

    /// Segments a long 16kHz mono PCM recording into clean speech regions using Silero VAD
    /// (falls back to energy segmentation if Silero VAD is unavailable).
    public func segmentAudio(
        samples: [Float],
        useNeuralVAD: Bool,
        vadModelID: String,
        hfHost: String,
        maxChunkSeconds: Float = 18.0
    ) async -> [SpeechAudioSegment] {
        guard !samples.isEmpty else { return [] }
        let sampleRate = 16_000

        if useNeuralVAD, let vad = await ensureVADLoaded(vadModelID: vadModelID, hfHost: hfHost) {
            do {
                let audio = MLXArray(samples)
                let timestamps = try vad.getSpeechTimestamps(
                    audio,
                    sampleRate: sampleRate,
                    threshold: 0.42,
                    minSpeechDurationMs: 300,
                    minSilenceDurationMs: 450,
                    speechPadMs: 120
                )
                Memory.clearCache()

                if !timestamps.isEmpty {
                    var results: [SpeechAudioSegment] = []
                    let maxSamples = Int(maxChunkSeconds * Float(sampleRate))

                    for ts in timestamps {
                        let start = max(0, min(samples.count, ts.start))
                        let end = max(start, min(samples.count, ts.end))
                        guard end - start >= sampleRate / 4 else { continue }

                        // Sub-split very long uninterrupted monologues
                        var cursor = start
                        while cursor < end {
                            let nextEnd = min(end, cursor + maxSamples)
                            let slice = Array(samples[cursor..<nextEnd])
                            results.append(SpeechAudioSegment(
                                startSeconds: Double(cursor) / Double(sampleRate),
                                endSeconds: Double(nextEnd) / Double(sampleRate),
                                samples: slice
                            ))
                            cursor = nextEnd
                        }
                    }
                    if !results.isEmpty {
                        return results
                    }
                }
            } catch {
                // Fall through to energy segmentation
            }
        }

        // Energy-based fallback segmentation
        return Self.energySegmentAudio(samples: samples, sampleRate: sampleRate, maxChunkSeconds: maxChunkSeconds)
    }

    public static func energySegmentAudio(
        samples: [Float],
        sampleRate: Int = 16_000,
        maxChunkSeconds: Float = 18.0
    ) -> [SpeechAudioSegment] {
        let frameSize = sampleRate / 10 // 100ms frames
        let maxSamples = Int(maxChunkSeconds * Float(sampleRate))
        var segments: [SpeechAudioSegment] = []

        var inSpeech = false
        var segStart = 0
        var silenceFrames = 0

        var offset = 0
        while offset < samples.count {
            let end = min(samples.count, offset + frameSize)
            var sumSq: Float = 0
            for i in offset..<end { sumSq += samples[i] * samples[i] }
            let rms = sqrt(sumSq / Float(max(1, end - offset)))

            if rms >= 0.012 {
                if !inSpeech {
                    inSpeech = true
                    segStart = max(0, offset - frameSize)
                }
                silenceFrames = 0
            } else if inSpeech {
                silenceFrames += 1
            }

            let reachedMax = inSpeech && (end - segStart) >= maxSamples
            let reachedPause = inSpeech && silenceFrames >= 7 && (end - segStart) >= sampleRate / 2

            if reachedMax || reachedPause {
                let slice = Array(samples[segStart..<end])
                segments.append(SpeechAudioSegment(
                    startSeconds: Double(segStart) / Double(sampleRate),
                    endSeconds: Double(end) / Double(sampleRate),
                    samples: slice
                ))
                inSpeech = false
                silenceFrames = 0
            }
            offset = end
        }

        if inSpeech && (samples.count - segStart) >= sampleRate / 3 {
            let slice = Array(samples[segStart..<samples.count])
            segments.append(SpeechAudioSegment(
                startSeconds: Double(segStart) / Double(sampleRate),
                endSeconds: Double(samples.count) / Double(sampleRate),
                samples: slice
            ))
        }

        return segments
    }

    // MARK: - Qwen3-ASR Loading & Inference

    public func ensureLoaded(
        modelID: String,
        hfHost: String = "https://huggingface.co",
        onStateChange: (@Sendable (MLXModelState) -> Void)? = nil
    ) async throws -> Qwen3ASRModel {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetID = trimmed.isEmpty ? "mlx-community/Qwen3-ASR-1.7B-8bit" : trimmed

        if let existing = model, loadedModelID == targetID {
            return existing
        }

        if model != nil {
            unloadModel(onStateChange: nil)
        }

        let shortName = targetID.split(separator: "/").last.map(String.init) ?? targetID

        let expandedPath = (targetID as NSString).expandingTildeInPath
        let modelDir: URL
        if FileManager.default.fileExists(atPath: (expandedPath as NSString).appendingPathComponent("config.json")) {
            modelDir = URL(fileURLWithPath: expandedPath)
        } else {
            guard let repoID = Repo.ID(rawValue: targetID) else {
                let err = "无效的模型 ID：\(targetID)"
                updateState(.failed(err), notify: onStateChange)
                throw NSError(domain: "Sonote.MLX", code: 1, userInfo: [NSLocalizedDescriptionKey: err])
            }

            let cached = Self.isModelCachedLocally(modelID: targetID)
            if !cached {
                updateState(.downloading(progress: 0.0, message: "正在下载 \(shortName)"), notify: onStateChange)
            } else {
                updateState(.loading(message: "正在加载本地缓存 \(shortName)..."), notify: onStateChange)
            }

            let hostString = hfHost.trimmingCharacters(in: .whitespacesAndNewlines)
            let hostURL = URL(string: hostString.isEmpty ? "https://huggingface.co" : hostString) ?? HubClient.defaultHost
            let hfToken = ProcessInfo.processInfo.environment["HF_TOKEN"]
            let client: HubClient
            if let hfToken, !hfToken.isEmpty {
                client = HubClient(host: hostURL, bearerToken: hfToken, cache: .default)
            } else {
                client = HubClient(host: hostURL, cache: .default)
            }

            do {
                modelDir = try await ModelUtils.resolveOrDownloadModel(
                    client: client,
                    cache: .default,
                    repoID: repoID,
                    requiredExtension: "safetensors",
                    progressHandler: { progress in
                        let fraction = progress.fractionCompleted
                        let msg = "正在下载 \(shortName)"
                        onStateChange?(.downloading(progress: fraction, message: msg))
                    }
                )
            } catch {
                let errMsg = "模型下载失败（可在设置中切换 hf-mirror.com 镜像）：\(error.localizedDescription)"
                updateState(.failed(errMsg), notify: onStateChange)
                throw error
            }
        }

        updateState(.loading(message: "正在初始化 MLX Metal 权重 (\(shortName))..."), notify: onStateChange)
        do {
            let loaded = try await Qwen3ASRModel.fromModelDirectory(modelDir)
            self.model = loaded
            self.loadedModelID = targetID
            let peakGB = Double(Memory.peakMemory) / 1e9
            updateState(.ready(modelID: targetID, peakMemoryGB: peakGB), notify: onStateChange)
            return loaded
        } catch {
            let errMsg = "模型初始化失败：\(error.localizedDescription)"
            updateState(.failed(errMsg), notify: onStateChange)
            throw error
        }
    }

    public func transcribe(
        samples: [Float],
        language: TranscriptionLanguage,
        context: String,
        modelID: String,
        hfHost: String,
        useNeuralVADGate: Bool = false,
        vadModelID: String = "mlx-community/silero-vad-v6",
        enableSpeechEnhancement: Bool = false,
        speechEnhancementModelID: String = "mlx-community/DeepFilterNet-mlx",
        onStateChange: (@Sendable (MLXModelState) -> Void)? = nil
    ) async throws -> String {
        guard samples.count >= 4_000 else { return "" }

        if useNeuralVADGate {
            let hasSpeech = await containsHumanSpeech(
                samples: samples,
                vadModelID: vadModelID,
                hfHost: hfHost
            )
            if !hasSpeech { return "" }
        }

        let effectiveSamples: [Float]
        if enableSpeechEnhancement {
            effectiveSamples = await SpeechEnhancementService.shared.enhance16k(
                samples: samples,
                modelID: speechEnhancementModelID,
                hfHost: hfHost
            )
        } else {
            effectiveSamples = samples
        }

        let loadedModel = try await ensureLoaded(
            modelID: modelID,
            hfHost: hfHost,
            onStateChange: onStateChange
        )

        let audioArray = MLXArray(effectiveSamples)
        let output = loadedModel.generate(
            audio: audioArray,
            maxTokens: 512,
            temperature: 0.0,
            context: context,
            language: language.qwen3LanguageName,
            chunkDuration: 30.0,
            minChunkDuration: 0.5
        )
        Memory.clearCache()

        let peakGB = Double(Memory.peakMemory) / 1e9
        if let activeID = loadedModelID {
            updateState(.ready(modelID: activeID, peakMemoryGB: peakGB), notify: onStateChange)
        }

        return Self.cleanTranscriptText(output.text)
    }

    public func unloadModel(onStateChange: (@Sendable (MLXModelState) -> Void)? = nil) {
        model = nil
        loadedModelID = nil
        vadModel = nil
        loadedVADModelID = nil
        streamingVADStates.removeAll()
        Memory.clearCache()
        updateState(.idle, notify: onStateChange)
    }

    private func updateState(_ newState: MLXModelState, notify: (@Sendable (MLXModelState) -> Void)?) {
        self.state = newState
        notify?(newState)
    }

    public static func cleanTranscriptText(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = text.range(of: "<asr_text>") {
            text = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let stripped = text.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines))
        if stripped.isEmpty { return "" }
        return text
    }
}

// MARK: - Streaming Frame-by-Frame VAD Endpointing State Machine

public enum StreamingVADAction: Equatable, Sendable {
    case none
    case preview([Float])
    case commit([Float])
}

/// Hysteresis-based streaming speech endpoint detector operating on 512-sample (32 ms @ 16 kHz) frames.
/// Uses separate start/continue probability thresholds to pick up quiet speech without clipping word endings.
public struct StreamingVADEndpointMachine: Sendable {
    public let sampleRate: Int
    public let speechStartThreshold: Float
    public let speechContinueThreshold: Float
    public let preRollLimit: Int
    public let minCommitSamples: Int
    public let maxCommitSamples: Int
    public let silenceEndpointSamples: Int
    public let previewStrideSamples: Int
    public let minPreviewSamples: Int

    public private(set) var isInSpeech: Bool = false
    private var preRollBuffer: [Float] = []
    private var activeSpeechBuffer: [Float] = []
    private var silenceSamples: Int = 0
    private var samplesSinceLastPreview: Int = 0

    public init(
        sampleRate: Int = 16_000,
        speechStartThreshold: Float = 0.48,
        speechContinueThreshold: Float = 0.30,
        preRollLimit: Int = 16_000 / 3,
        minCommitSamples: Int = 16_000 * 6 / 10,
        maxCommitSamples: Int = 16_000 * 10,
        silenceEndpointSamples: Int = 16_000 * 8 / 10,
        previewStrideSamples: Int = 16_000 * 24 / 10,
        minPreviewSamples: Int = 16_000 * 2
    ) {
        self.sampleRate = sampleRate
        self.speechStartThreshold = speechStartThreshold
        self.speechContinueThreshold = speechContinueThreshold
        self.preRollLimit = preRollLimit
        self.minCommitSamples = minCommitSamples
        self.maxCommitSamples = maxCommitSamples
        self.silenceEndpointSamples = silenceEndpointSamples
        self.previewStrideSamples = previewStrideSamples
        self.minPreviewSamples = minPreviewSamples
    }

    public mutating func ingest(frame: [Float], speechProbability: Float, previewBusy: Bool = false) -> StreamingVADAction {
        guard !frame.isEmpty else { return .none }

        if !isInSpeech {
            if speechProbability >= speechStartThreshold {
                isInSpeech = true
                silenceSamples = 0
                samplesSinceLastPreview = 0
                activeSpeechBuffer = preRollBuffer
                activeSpeechBuffer.append(contentsOf: frame)
                preRollBuffer.removeAll(keepingCapacity: true)
            } else {
                preRollBuffer.append(contentsOf: frame)
                if preRollBuffer.count > preRollLimit {
                    preRollBuffer.removeFirst(preRollBuffer.count - preRollLimit)
                }
            }
            return .none
        }

        activeSpeechBuffer.append(contentsOf: frame)
        samplesSinceLastPreview += frame.count

        if speechProbability >= speechContinueThreshold {
            silenceSamples = 0
        } else {
            silenceSamples += frame.count
        }

        let hitMaxWindow = activeSpeechBuffer.count >= maxCommitSamples
        let hitSilenceBreak = activeSpeechBuffer.count >= minCommitSamples && silenceSamples >= silenceEndpointSamples

        if hitMaxWindow || hitSilenceBreak {
            let chunk = activeSpeechBuffer
            activeSpeechBuffer.removeAll(keepingCapacity: true)
            isInSpeech = false
            silenceSamples = 0
            samplesSinceLastPreview = 0
            return .commit(chunk)
        }

        if samplesSinceLastPreview >= previewStrideSamples,
           activeSpeechBuffer.count >= minPreviewSamples,
           !previewBusy {
            samplesSinceLastPreview = 0
            return .preview(activeSpeechBuffer)
        }

        return .none
    }

    public mutating func flushRemaining() -> [Float] {
        let left = (isInSpeech && activeSpeechBuffer.count >= minCommitSamples) ? activeSpeechBuffer : []
        activeSpeechBuffer.removeAll()
        preRollBuffer.removeAll()
        isInSpeech = false
        silenceSamples = 0
        samplesSinceLastPreview = 0
        return left
    }
}

// MARK: - Per-Track Streaming Silero-VAD + Qwen3-ASR Real-Time Transcriber

public final class MLXQwen3TrackTranscriber: AudioTrackTranscriber, @unchecked Sendable {
    public let speaker: SpeakerSource
    private let settings: AppSettings
    private let extraContextHint: String
    private let engine: MLXQwen3ASREngine
    private let liveSpeakerBank: OnlineSpeakerClusterBank?
    private let onModelStateChange: (@Sendable (MLXModelState) -> Void)?
    private let onFinalSegmentWithSpeaker: (@Sendable (String, String?) -> Void)?
    private let vadSessionID = UUID()

    private let stateQueue = DispatchQueue(label: "com.sonote.mlx-qwen3-track")
    private var pendingSamples: [Float] = []
    private var endpointMachine = StreamingVADEndpointMachine()
    private var recentContextTail: String = ""
    private var previewInFlight = false
    private var isStopped = false

    private var frameContinuation: AsyncStream<[[Float]]>.Continuation?
    private var consumerTask: Task<Void, Never>?

    private var onVolatileText: (@Sendable (String) -> Void)?
    private var onFinalSegment: (@Sendable (String) -> Void)?
    private var onStatusMessage: (@Sendable (String) -> Void)?

    private let vadFrameSize = 512      // 32 ms @ 16 kHz (native Silero VAD chunk)
    private let vadBatchFrames = 4      // 128 ms batches to keep GPU overhead minimal
    private let fallbackRMSThreshold: Float = 0.009

    public init(
        speaker: SpeakerSource,
        settings: AppSettings,
        extraContextHint: String = "",
        engine: MLXQwen3ASREngine = .shared,
        liveSpeakerBank: OnlineSpeakerClusterBank? = nil,
        onFinalSegmentWithSpeaker: (@Sendable (String, String?) -> Void)? = nil,
        onModelStateChange: (@Sendable (MLXModelState) -> Void)? = nil
    ) {
        self.speaker = speaker
        self.settings = settings
        self.extraContextHint = extraContextHint
        self.engine = engine
        self.liveSpeakerBank = liveSpeakerBank
        self.onFinalSegmentWithSpeaker = onFinalSegmentWithSpeaker
        self.onModelStateChange = onModelStateChange
    }

    public func start(
        onVolatileText: @escaping @Sendable (String) -> Void,
        onFinalSegment: @escaping @Sendable (String) -> Void,
        onStatusMessage: @escaping @Sendable (String) -> Void
    ) async throws {
        self.onVolatileText = onVolatileText
        self.onFinalSegment = onFinalSegment
        self.onStatusMessage = onStatusMessage

        stateQueue.sync {
            self.isStopped = false
            self.pendingSamples.removeAll(keepingCapacity: true)
            self.endpointMachine = StreamingVADEndpointMachine()
            self.previewInFlight = false
        }

        _ = try await engine.ensureLoaded(
            modelID: settings.mlxQwen3ModelID,
            hfHost: settings.mlxHuggingFaceHost,
            onStateChange: onModelStateChange
        )
        if settings.enableNeuralVAD {
            _ = await engine.ensureVADLoaded(
                vadModelID: settings.sileroVADModelID,
                hfHost: settings.mlxHuggingFaceHost
            )
        }

        let stream = AsyncStream<[[Float]]> { continuation in
            self.stateQueue.sync {
                self.frameContinuation = continuation
            }
        }

        consumerTask = Task { [weak self] in
            guard let self else { return }
            for await batch in stream {
                await self.processFrameBatch(batch)
            }
        }
    }

    public func append(buffer: AVAudioPCMBuffer) {
        let samples = WAVEncoder.extractMono16kSamples(from: buffer)
        guard !samples.isEmpty else { return }

        stateQueue.async { [weak self] in
            guard let self, !self.isStopped else { return }
            self.pendingSamples.append(contentsOf: samples)

            let batchSampleCount = self.vadFrameSize * self.vadBatchFrames
            while self.pendingSamples.count >= batchSampleCount {
                var frames: [[Float]] = []
                frames.reserveCapacity(self.vadBatchFrames)
                for i in 0..<self.vadBatchFrames {
                    let start = i * self.vadFrameSize
                    frames.append(Array(self.pendingSamples[start..<(start + self.vadFrameSize)]))
                }
                self.pendingSamples.removeFirst(batchSampleCount)
                self.frameContinuation?.yield(frames)
            }
        }
    }

    public func stop() async {
        let (tailFrames, continuation, task) = stateQueue.sync { () -> ([[Float]], AsyncStream<[[Float]]>.Continuation?, Task<Void, Never>?) in
            self.isStopped = true
            var trailing: [[Float]] = []
            while self.pendingSamples.count >= self.vadFrameSize {
                trailing.append(Array(self.pendingSamples.prefix(self.vadFrameSize)))
                self.pendingSamples.removeFirst(self.vadFrameSize)
            }
            self.pendingSamples.removeAll()
            let cont = self.frameContinuation
            self.frameContinuation = nil
            let t = self.consumerTask
            self.consumerTask = nil
            return (trailing, cont, t)
        }

        if !tailFrames.isEmpty {
            continuation?.yield(tailFrames)
        }
        continuation?.finish()
        await task?.value

        let remaining: [Float] = stateQueue.sync {
            endpointMachine.flushRemaining()
        }

        await engine.removeStreamingVADSession(vadSessionID)

        if !remaining.isEmpty {
            let context = buildContextPrompt()
            if let text = try? await engine.transcribe(
                samples: remaining,
                language: settings.transcriptionLanguage,
                context: context,
                modelID: settings.mlxQwen3ModelID,
                hfHost: settings.mlxHuggingFaceHost,
                useNeuralVADGate: false,
                vadModelID: settings.sileroVADModelID,
                enableSpeechEnhancement: settings.enableSpeechEnhancement,
                speechEnhancementModelID: settings.speechEnhancementModelID,
                onStateChange: onModelStateChange
            ), !text.isEmpty {
                onFinalSegment?(text)
            }
        }
        onVolatileText?("")
    }

    private func processFrameBatch(_ frames: [[Float]]) async {
        guard !frames.isEmpty else { return }

        let neuralProbs: [Float]?
        if settings.enableNeuralVAD {
            neuralProbs = await engine.evaluateStreamingVADFrames(
                sessionID: vadSessionID,
                chunks512: frames,
                vadModelID: settings.sileroVADModelID,
                hfHost: settings.mlxHuggingFaceHost
            )
        } else {
            neuralProbs = nil
        }

        let usedNeural = neuralProbs != nil && neuralProbs?.count == frames.count
        let frameProbs: [Float] = usedNeural
            ? neuralProbs!
            : frames.map { Self.rmsPseudoProbability(frame: $0, threshold: fallbackRMSThreshold) }

        var commits: [[Float]] = []
        var previewChunk: [Float]? = nil

        stateQueue.sync {
            for (frame, prob) in zip(frames, frameProbs) {
                let action = endpointMachine.ingest(
                    frame: frame,
                    speechProbability: prob,
                    previewBusy: previewInFlight
                )
                switch action {
                case .none:
                    break
                case .preview(let snapshot):
                    previewInFlight = true
                    previewChunk = snapshot
                case .commit(let chunk):
                    commits.append(chunk)
                }
            }
        }

        for chunk in commits {
            dispatchFinalTranscription(samples: chunk, usedStreamingNeuralVAD: usedNeural)
        }
        if let previewChunk {
            dispatchPreviewTranscription(samples: previewChunk, usedStreamingNeuralVAD: usedNeural)
        }
    }

    private static func rmsPseudoProbability(frame: [Float], threshold: Float) -> Float {
        guard !frame.isEmpty else { return 0 }
        var sumSq: Float = 0
        for s in frame { sumSq += s * s }
        let rms = sqrt(sumSq / Float(frame.count))
        return rms >= threshold ? 0.9 : 0.0
    }

    private func buildContextPrompt() -> String {
        let userHint = settings.asrContextHint.trimmingCharacters(in: .whitespacesAndNewlines)
        let extra = extraContextHint.trimmingCharacters(in: .whitespacesAndNewlines)
        let tail = stateQueue.sync { recentContextTail }
        return [userHint, extra, tail].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private func dispatchPreviewTranscription(samples: [Float], usedStreamingNeuralVAD: Bool) {
        let context = buildContextPrompt()
        Task { [weak self] in
            guard let self else { return }
            defer {
                self.stateQueue.async { self.previewInFlight = false }
            }
            do {
                let partial = try await self.engine.transcribe(
                    samples: samples,
                    language: self.settings.transcriptionLanguage,
                    context: context,
                    modelID: self.settings.mlxQwen3ModelID,
                    hfHost: self.settings.mlxHuggingFaceHost,
                    useNeuralVADGate: self.settings.enableNeuralVAD && !usedStreamingNeuralVAD,
                    vadModelID: self.settings.sileroVADModelID,
                    onStateChange: self.onModelStateChange
                )
                let stillActive: Bool = self.stateQueue.sync { !self.isStopped && self.endpointMachine.isInSpeech }
                if stillActive && !partial.isEmpty {
                    self.onVolatileText?(partial)
                }
            } catch {
                // Non-fatal for preview pass
            }
        }
    }

    private func dispatchFinalTranscription(samples: [Float], usedStreamingNeuralVAD: Bool) {
        let context = buildContextPrompt()
        Task { [weak self] in
            guard let self else { return }
            do {
                let text = try await self.engine.transcribe(
                    samples: samples,
                    language: self.settings.transcriptionLanguage,
                    context: context,
                    modelID: self.settings.mlxQwen3ModelID,
                    hfHost: self.settings.mlxHuggingFaceHost,
                    useNeuralVADGate: self.settings.enableNeuralVAD && !usedStreamingNeuralVAD,
                    vadModelID: self.settings.sileroVADModelID,
                    enableSpeechEnhancement: self.settings.enableSpeechEnhancement,
                    speechEnhancementModelID: self.settings.speechEnhancementModelID,
                    onStateChange: self.onModelStateChange
                )
                self.onVolatileText?("")
                if !text.isEmpty {
                    self.stateQueue.async {
                        self.recentContextTail = String(text.suffix(100))
                    }
                    var liveSpeakerName: String? = nil
                    if let bank = self.liveSpeakerBank,
                       self.speaker == .remote,
                       self.settings.enableLiveSpeakerDiarization,
                       samples.count >= 16_000 {
                        if let emb = try? await VoiceprintService.shared.extractEmbedding(
                            samples16k: samples,
                            modelID: self.settings.voiceprintModelID,
                            hfHost: self.settings.mlxHuggingFaceHost
                        ) {
                            liveSpeakerName = bank.identifyOrCluster(embedding: emb)
                        }
                    }
                    if let handler = self.onFinalSegmentWithSpeaker {
                        handler(text, liveSpeakerName)
                    } else {
                        self.onFinalSegment?(text)
                    }
                }
            } catch {
                self.onVolatileText?("")
                self.onStatusMessage?("MLX Qwen3-ASR 转写出错：\(error.localizedDescription)")
            }
        }
    }
}
