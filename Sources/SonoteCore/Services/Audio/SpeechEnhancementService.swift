import Foundation
import MLX
import MLXAudioCore
import MLXAudioSTS
import HuggingFace

/// Neural speech enhancement & noise suppression powered by DeepFilterNet3 (`MLXAudioSTS`),
/// removing keyboard clicks, cafe chatter, air-conditioning hum, and background fan noise
/// in noisy environments while falling back cleanly to lightweight high-pass DSP when offline.
public actor SpeechEnhancementService {
    public static let shared = SpeechEnhancementService()

    private var model: DeepFilterNetModel?
    private var loadedModelID: String?
    private var loadFailed = false

    public init() {}

    public func isModelLoaded() -> Bool {
        model != nil
    }

    public func ensureLoaded(
        modelID: String = DeepFilterNetModel.defaultRepo,
        hfHost: String = "https://huggingface.co"
    ) async -> DeepFilterNetModel? {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetID = trimmed.isEmpty ? DeepFilterNetModel.defaultRepo : trimmed

        if let model, loadedModelID == targetID {
            return model
        }
        if loadFailed && loadedModelID == targetID {
            return nil
        }

        // Support direct local model directory path
        let expanded = (targetID as NSString).expandingTildeInPath
        if FileManager.default.fileExists(atPath: expanded) {
            if let local = try? DeepFilterNetModel.fromLocal(URL(fileURLWithPath: expanded), subfolder: "v3") {
                self.model = local
                self.loadedModelID = targetID
                self.loadFailed = false
                return local
            }
        }

        guard let repoID = Repo.ID(rawValue: targetID) else {
            loadedModelID = targetID
            loadFailed = true
            return nil
        }

        let hostURL = URL(string: hfHost.trimmingCharacters(in: .whitespacesAndNewlines)) ?? HubClient.defaultHost
        let hfToken = ProcessInfo.processInfo.environment["HF_TOKEN"]
        let client: HubClient = (hfToken?.isEmpty == false)
            ? HubClient(host: hostURL, bearerToken: hfToken!, cache: .default)
            : HubClient(host: hostURL, cache: .default)

        do {
            // Download ONLY the v3 subfolder files (config.json + model.safetensors) to avoid downloading v1 & v2
            let localDir = Self.localCacheDirectory(for: targetID)
            try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
            let configDest = localDir.appendingPathComponent("config.json")
            let weightsDest = localDir.appendingPathComponent("model.safetensors")

            if !FileManager.default.isReadableFile(atPath: configDest.path) {
                let downloadedConfig = try await client.downloadFile(at: "v3/config.json", from: repoID)
                let resolvedConfig = downloadedConfig.resolvingSymlinksInPath()
                try? FileManager.default.removeItem(at: configDest)
                try FileManager.default.copyItem(at: resolvedConfig, to: configDest)
            }
            if !FileManager.default.isReadableFile(atPath: weightsDest.path) {
                let downloadedWeights = try await client.downloadFile(at: "v3/model.safetensors", from: repoID)
                let resolvedWeights = downloadedWeights.resolvingSymlinksInPath()
                try? FileManager.default.removeItem(at: weightsDest)
                try FileManager.default.copyItem(at: resolvedWeights, to: weightsDest)
            }

            let loaded = try DeepFilterNetModel.fromLocal(localDir)
            self.model = loaded
            self.loadedModelID = targetID
            self.loadFailed = false
            return loaded
        } catch {
            self.loadedModelID = targetID
            self.loadFailed = true
            return nil
        }
    }

    /// Enhances 16 kHz mono speech samples via DeepFilterNet3 (upsampling to 48 kHz -> neural denoise -> 16 kHz),
    /// or applies lightweight high-pass + soft noise-floor suppression if the neural model is unavailable.
    public func enhance16k(
        samples: [Float],
        modelID: String = DeepFilterNetModel.defaultRepo,
        hfHost: String = "https://huggingface.co"
    ) async -> [Float] {
        guard samples.count >= 1600 else { return samples }

        if let dfn = await ensureLoaded(modelID: modelID, hfHost: hfHost) {
            do {
                let targetRate = Double(dfn.sampleRate) // 48_000
                let samples48k = WAVEncoder.resampleMono(samples: samples, from: 16_000, to: targetRate)
                let enhancedMLX = try dfn.enhance(MLXArray(samples48k))
                eval(enhancedMLX)
                let enhanced48k = enhancedMLX.asArray(Float.self)
                Memory.clearCache()

                if !enhanced48k.isEmpty {
                    let down16k = WAVEncoder.resampleMono(samples: enhanced48k, from: targetRate, to: 16_000)
                    if !down16k.isEmpty {
                        return down16k
                    }
                }
            } catch {
                // Fall through to lightweight DSP enhancer
            }
        }

        return Self.lightweightDSPNoiseSuppress(samples: samples, sampleRate: 16_000)
    }

    public func unload() {
        model = nil
        loadedModelID = nil
        loadFailed = false
        Memory.clearCache()
    }

    public static func isModelCachedLocally(modelID: String = DeepFilterNetModel.defaultRepo) -> Bool {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetID = trimmed.isEmpty ? DeepFilterNetModel.defaultRepo : trimmed
        let dir = localCacheDirectory(for: targetID)
        return FileManager.default.isReadableFile(atPath: dir.appendingPathComponent("config.json").path)
            && FileManager.default.isReadableFile(atPath: dir.appendingPathComponent("model.safetensors").path)
    }

    private static func localCacheDirectory(for repoID: String) -> URL {
        let sanitized = repoID.replacingOccurrences(of: "/", with: "_")
        return HubCache.default.cacheDirectory
            .appendingPathComponent("mlx-audio", isDirectory: true)
            .appendingPathComponent("\(sanitized)_v3", isDirectory: true)
    }

    /// Zero-dependency fallback speech cleaner: 1st-order 90 Hz high-pass filter (removes AC/desk rumble)
    /// + adaptive soft noise-floor attenuation for quiet background hiss.
    public static func lightweightDSPNoiseSuppress(samples: [Float], sampleRate: Float = 16_000) -> [Float] {
        guard samples.count >= 64 else { return samples }

        // 1. 90 Hz high-pass filter removes low-frequency hum/rumble cleanly
        let rc = 1.0 / (2.0 * Float.pi * 90.0)
        let dt = 1.0 / sampleRate
        let alpha = rc / (rc + dt)

        var hp = [Float](repeating: 0, count: samples.count)
        hp[0] = samples[0]
        for i in 1..<samples.count {
            hp[i] = alpha * (hp[i - 1] + samples[i] - samples[i - 1])
        }

        // 2. Estimate noise floor from 15th percentile frame RMS across 20ms frames
        let frameLen = max(1, Int(sampleRate * 0.02))
        var frameRMS: [Float] = []
        var offset = 0
        while offset < hp.count {
            let end = min(hp.count, offset + frameLen)
            var sumSq: Float = 0
            for i in offset..<end { sumSq += hp[i] * hp[i] }
            frameRMS.append(sqrt(sumSq / Float(max(1, end - offset))))
            offset = end
        }
        guard !frameRMS.isEmpty else { return hp }
        let sortedRMS = frameRMS.sorted()
        let noiseFloor = sortedRMS[min(sortedRMS.count - 1, max(0, Int(Float(sortedRMS.count) * 0.15)))]
        let gateThreshold = max(0.004, noiseFloor * 1.8)

        // 3. Smoothly attenuate frames below noise gate threshold (never hard-zero to keep ASR natural)
        var out = hp
        var prevGain: Float = 1.0
        for fIdx in 0..<frameRMS.count {
            let start = fIdx * frameLen
            let end = min(out.count, start + frameLen)
            let rms = frameRMS[fIdx]
            let targetGain: Float = rms >= gateThreshold ? 1.0 : max(0.18, rms / max(gateThreshold, 1e-6))
            let smoothedGain = prevGain * 0.65 + targetGain * 0.35
            prevGain = smoothedGain
            if smoothedGain < 0.99 {
                for i in start..<end {
                    out[i] *= smoothedGain
                }
            }
        }
        return out
    }
}
