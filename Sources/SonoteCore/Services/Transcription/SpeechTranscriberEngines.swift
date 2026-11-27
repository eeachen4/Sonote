import Foundation
import AVFoundation
import Speech

public protocol AudioTrackTranscriber: AnyObject, Sendable {
    var speaker: SpeakerSource { get }
    func start(
        onVolatileText: @escaping @Sendable (String) -> Void,
        onFinalSegment: @escaping @Sendable (String) -> Void,
        onStatusMessage: @escaping @Sendable (String) -> Void
    ) async throws
    func append(buffer: AVAudioPCMBuffer)
    func stop() async
}

// MARK: - macOS 26+ Native SpeechAnalyzer / SpeechTranscriber

@available(macOS 26.0, *)
public final class ModernSpeechAnalyzerTranscriber: AudioTrackTranscriber, @unchecked Sendable {
    public let speaker: SpeakerSource
    private let language: TranscriptionLanguage

    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var targetFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var sourceFormatSignature: String = ""
    private let convertLock = NSLock()
    private var isStopped = false

    public init(speaker: SpeakerSource, language: TranscriptionLanguage) {
        self.speaker = speaker
        self.language = language
    }

    public func start(
        onVolatileText: @escaping @Sendable (String) -> Void,
        onFinalSegment: @escaping @Sendable (String) -> Void,
        onStatusMessage: @escaping @Sendable (String) -> Void
    ) async throws {
        guard SpeechTranscriber.isAvailable else {
            throw NSError(domain: "Sonote.Speech", code: 1, userInfo: [NSLocalizedDescriptionKey: "SpeechTranscriber 不可用"])
        }

        let desiredLocale = Locale(identifier: language.appleLocaleIdentifier)
        guard let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: desiredLocale) else {
            throw NSError(domain: "Sonote.Speech", code: 2, userInfo: [NSLocalizedDescriptionKey: "SpeechTranscriber 暂不支持语言 \(language.appleLocaleIdentifier)"])
        }

        let module = SpeechTranscriber(
            locale: supportedLocale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: [.audioTimeRange]
        )

        let assetStatus = await AssetInventory.status(forModules: [module])
        if assetStatus == .unsupported {
            throw NSError(domain: "Sonote.Speech", code: 3, userInfo: [NSLocalizedDescriptionKey: "当前设备不支持该离线语音识别模型"])
        }
        if assetStatus != .installed {
            // Trigger background asset preparation for future meetings, and immediately fall back
            // to SFSpeechRecognizer so live transcription starts in < 1s without blocking.
            Task.detached(priority: .utility) {
                _ = try? await AssetInventory.reserve(locale: supportedLocale)
                if let req = try? await AssetInventory.assetInstallationRequest(supporting: [module]) {
                    try? await req.downloadAndInstall()
                }
            }
            throw NSError(domain: "Sonote.Speech", code: 4, userInfo: [NSLocalizedDescriptionKey: "离线增强语音包后台准备中，已启用即时系统语音识别"])
        }

        guard let bestFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
            throw NSError(domain: "Sonote.Speech", code: 5, userInfo: [NSLocalizedDescriptionKey: "离线语音识别格式未就绪，已切换至即时系统语音识别"])
        }
        self.targetFormat = bestFormat

        let speechAnalyzer = SpeechAnalyzer(modules: [module])
        self.transcriber = module
        self.analyzer = speechAnalyzer
        self.isStopped = false

        var streamContinuation: AsyncStream<AnalyzerInput>.Continuation?
        let inputSequence = AsyncStream<AnalyzerInput> { continuation in
            streamContinuation = continuation
        }
        self.inputContinuation = streamContinuation

        try await speechAnalyzer.prepareToAnalyze(in: bestFormat)
        try await speechAnalyzer.start(inputSequence: inputSequence)

        resultsTask = Task {
            do {
                for try await result in module.results {
                    let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    if result.isFinal {
                        onVolatileText("")
                        onFinalSegment(text)
                    } else {
                        onVolatileText(text)
                    }
                }
            } catch {
                if !self.isStopped {
                    onStatusMessage("[\(self.speaker.shortLabel)] 语音识别流中断：\(error.localizedDescription)")
                }
            }
        }
    }

    public func append(buffer: AVAudioPCMBuffer) {
        guard !isStopped, let continuation = inputContinuation else { return }
        guard let targetFormat else {
            continuation.yield(AnalyzerInput(buffer: buffer))
            return
        }

        guard let converted = convertBuffer(buffer, to: targetFormat) else { return }
        continuation.yield(AnalyzerInput(buffer: converted))
    }

    public func stop() async {
        isStopped = true
        inputContinuation?.finish()
        inputContinuation = nil
        if let analyzer {
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
        }
        resultsTask?.cancel()
        resultsTask = nil
        analyzer = nil
        transcriber = nil
    }

    private func convertBuffer(_ buffer: AVAudioPCMBuffer, to targetFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        if buffer.format == targetFormat {
            return buffer
        }

        convertLock.lock()
        defer { convertLock.unlock() }

        let sig = "\(buffer.format.sampleRate)-\(buffer.format.channelCount)-\(buffer.format.commonFormat.rawValue)-\(buffer.format.isInterleaved)"
        if sig != sourceFormatSignature || converter == nil {
            converter = AVAudioConverter(from: buffer.format, to: targetFormat)
            sourceFormatSignature = sig
        }
        guard let converter else { return nil }

        let ratio = targetFormat.sampleRate / max(1.0, buffer.format.sampleRate)
        let frameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else {
            return nil
        }

        var hasProvidedInput = false
        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if hasProvidedInput {
                outStatus.pointee = .noDataNow
                return nil
            }
            hasProvidedInput = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, error == nil, outputBuffer.frameLength > 0 else {
            return nil
        }
        return outputBuffer
    }
}

// MARK: - Legacy SFSpeechRecognizer with Rolling Auto-Restart

public final class LegacySpeechTranscriber: AudioTrackTranscriber, @unchecked Sendable {
    public let speaker: SpeakerSource
    private let language: TranscriptionLanguage

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var rotationTimer: DispatchSourceTimer?
    private let lock = NSLock()

    private var isStopped = false
    private var lastPartialText = ""
    private var onVolatileText: (@Sendable (String) -> Void)?
    private var onFinalSegment: (@Sendable (String) -> Void)?
    private var onStatusMessage: (@Sendable (String) -> Void)?

    public init(speaker: SpeakerSource, language: TranscriptionLanguage) {
        self.speaker = speaker
        self.language = language
    }

    public static func requestSpeechAuthorization() async -> Bool {
        let current = SFSpeechRecognizer.authorizationStatus()
        if current == .authorized { return true }
        if current == .denied || current == .restricted { return false }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    public func start(
        onVolatileText: @escaping @Sendable (String) -> Void,
        onFinalSegment: @escaping @Sendable (String) -> Void,
        onStatusMessage: @escaping @Sendable (String) -> Void
    ) async throws {
        let granted = await Self.requestSpeechAuthorization()
        guard granted else {
            throw NSError(
                domain: "Sonote.Speech",
                code: 10,
                userInfo: [NSLocalizedDescriptionKey: "未获得语音识别权限，请在「系统设置 → 隐私与安全性 → 语音识别」中允许「Sonote」。"]
            )
        }

        guard let rec = SFSpeechRecognizer(locale: Locale(identifier: language.appleLocaleIdentifier)), rec.isAvailable else {
            throw NSError(
                domain: "Sonote.Speech",
                code: 11,
                userInfo: [NSLocalizedDescriptionKey: "系统语音识别器 (\(language.appleLocaleIdentifier)) 当前不可用。"]
            )
        }

        self.recognizer = rec
        self.onVolatileText = onVolatileText
        self.onFinalSegment = onFinalSegment
        self.onStatusMessage = onStatusMessage
        self.isStopped = false

        startRecognitionCycle()
        startRotationTimer()
    }

    public func append(buffer: AVAudioPCMBuffer) {
        lock.lock()
        let activeRequest = request
        lock.unlock()
        activeRequest?.append(buffer)
    }

    public func stop() async {
        let pending: String = lock.withLock {
            isStopped = true
            rotationTimer?.cancel()
            rotationTimer = nil
            let text = lastPartialText.trimmingCharacters(in: .whitespacesAndNewlines)
            lastPartialText = ""
            request?.endAudio()
            task?.cancel()
            request = nil
            task = nil
            return text
        }

        if !pending.isEmpty {
            onFinalSegment?(pending)
        }
        onVolatileText?("")
    }

    private func startRecognitionCycle() {
        lock.lock()
        guard !isStopped, let recognizer else {
            lock.unlock()
            return
        }

        let oldPending = lastPartialText.trimmingCharacters(in: .whitespacesAndNewlines)
        lastPartialText = ""
        request?.endAudio()
        task?.cancel()

        let newRequest = SFSpeechAudioBufferRecognitionRequest()
        newRequest.shouldReportPartialResults = true
        newRequest.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition {
            newRequest.requiresOnDeviceRecognition = true
        }
        self.request = newRequest

        let cycleID = UUID()
        let newTask = recognizer.recognitionTask(with: newRequest) { [weak self] result, error in
            guard let self else { return }
            self.handleRecognitionCallback(cycleID: cycleID, result: result, error: error)
        }
        self.task = newTask
        lock.unlock()

        if !oldPending.isEmpty {
            onFinalSegment?(oldPending)
            onVolatileText?("")
        }
    }

    private func handleRecognitionCallback(
        cycleID: UUID,
        result: SFSpeechRecognitionResult?,
        error: Error?
    ) {
        lock.lock()
        if isStopped {
            lock.unlock()
            return
        }
        if let result {
            let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
            if result.isFinal {
                lastPartialText = ""
                lock.unlock()
                onVolatileText?("")
                if !text.isEmpty {
                    onFinalSegment?(text)
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    self?.startRecognitionCycle()
                }
                return
            } else {
                lastPartialText = text
                lock.unlock()
                onVolatileText?(text)
                return
            }
        }

        if error != nil {
            let pending = lastPartialText.trimmingCharacters(in: .whitespacesAndNewlines)
            lastPartialText = ""
            lock.unlock()
            if !pending.isEmpty {
                onFinalSegment?(pending)
                onVolatileText?("")
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.startRecognitionCycle()
            }
            return
        }
        lock.unlock()
    }

    private func startRotationTimer() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 48, repeating: 48)
        timer.setEventHandler { [weak self] in
            self?.startRecognitionCycle()
        }
        timer.resume()
        rotationTimer = timer
    }
}

// MARK: - OpenAI Chunked Audio Transcription API Engine

public final class OpenAIChunkTranscriber: AudioTrackTranscriber, @unchecked Sendable {
    public let speaker: SpeakerSource
    private let settings: AppSettings
    private let gptClient: GPTClient

    private let bufferQueue = DispatchQueue(label: "com.sonote.openai-transcriber")
    private var sampleBuffer: [Float] = []
    private var speechDetectedInChunk = false
    private var silenceSampleCount = 0
    private var isStopped = false

    private var onVolatileText: (@Sendable (String) -> Void)?
    private var onFinalSegment: (@Sendable (String) -> Void)?
    private var onStatusMessage: (@Sendable (String) -> Void)?

    private let targetSampleRate: Int = 16_000
    private let maxChunkSamples: Int = 16_000 * 12     // 12 seconds max per chunk
    private let minChunkSamples: Int = 16_000 * 2      // 2 seconds minimum
    private let silenceFlushSamples: Int = 16_000 * 1  // 1.0s silence flushes utterance
    private let energyThreshold: Float = 0.012

    public init(speaker: SpeakerSource, settings: AppSettings, gptClient: GPTClient = .shared) {
        self.speaker = speaker
        self.settings = settings
        self.gptClient = gptClient
    }

    public func start(
        onVolatileText: @escaping @Sendable (String) -> Void,
        onFinalSegment: @escaping @Sendable (String) -> Void,
        onStatusMessage: @escaping @Sendable (String) -> Void
    ) async throws {
        self.onVolatileText = onVolatileText
        self.onFinalSegment = onFinalSegment
        self.onStatusMessage = onStatusMessage
        self.isStopped = false
    }

    public func append(buffer: AVAudioPCMBuffer) {
        let samples = WAVEncoder.extractMono16kSamples(from: buffer)
        guard !samples.isEmpty else { return }

        bufferQueue.async { [weak self] in
            guard let self, !self.isStopped else { return }

            var sumSq: Float = 0
            for s in samples { sumSq += s * s }
            let rms = sqrt(sumSq / Float(samples.count))

            if rms >= self.energyThreshold {
                self.speechDetectedInChunk = true
                self.silenceSampleCount = 0
            } else {
                self.silenceSampleCount += samples.count
            }

            if self.speechDetectedInChunk {
                self.sampleBuffer.append(contentsOf: samples)
            }

            let reachedMax = self.sampleBuffer.count >= self.maxChunkSamples
            let reachedSilenceBreak = self.sampleBuffer.count >= self.minChunkSamples
                && self.silenceSampleCount >= self.silenceFlushSamples

            if reachedMax || reachedSilenceBreak {
                let chunk = self.sampleBuffer
                self.sampleBuffer.removeAll(keepingCapacity: true)
                self.speechDetectedInChunk = false
                self.silenceSampleCount = 0
                self.dispatchTranscription(samples: chunk)
            }
        }
    }

    public func stop() async {
        let remaining: [Float] = bufferQueue.sync {
            isStopped = true
            let left = speechDetectedInChunk && sampleBuffer.count >= targetSampleRate ? sampleBuffer : []
            sampleBuffer.removeAll()
            speechDetectedInChunk = false
            return left
        }
        if !remaining.isEmpty {
            let wav = WAVEncoder.encodeMono16kWAV(samples: remaining)
            if let text = try? await gptClient.transcribeAudioWAV(
                wavData: wav,
                language: settings.transcriptionLanguage,
                settings: settings
            ), !text.isEmpty {
                onFinalSegment?(text)
            }
        }
        onVolatileText?("")
    }

    private func dispatchTranscription(samples: [Float]) {
        onVolatileText?("正在转写语音片段...")
        let wav = WAVEncoder.encodeMono16kWAV(samples: samples)
        Task { [weak self] in
            guard let self else { return }
            do {
                let text = try await self.gptClient.transcribeAudioWAV(
                    wavData: wav,
                    language: self.settings.transcriptionLanguage,
                    settings: self.settings
                )
                self.onVolatileText?("")
                let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty {
                    self.onFinalSegment?(cleaned)
                }
            } catch {
                self.onVolatileText?("")
                self.onStatusMessage?("OpenAI 转写失败：\(error.localizedDescription)")
            }
        }
    }
}
