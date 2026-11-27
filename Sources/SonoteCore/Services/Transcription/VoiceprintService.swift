import Foundation
import AVFoundation
import MLX
import MLXAudioCore
import MLXAudioCodecs
import HuggingFace

public enum VoiceprintError: LocalizedError {
    case audioTooShort
    case invalidRepository(String)
    case recordingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .audioTooShort:
            return "有效语音时长不足（至少需要 1 秒清晰人声）以提取可靠声纹。"
        case .invalidRepository(let id):
            return "无效的声纹模型仓库 ID：\(id)"
        case .recordingFailed(let msg):
            return "声纹录音失败：\(msg)"
        }
    }
}

/// Persists local speaker voiceprints (`voiceprints.json`) 100% offline inside Sonote app support.
public final class VoiceprintStore: @unchecked Sendable {
    public static let shared = VoiceprintStore()

    public let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(baseDirectory: URL? = nil) {
        let dir: URL
        if let baseDirectory {
            dir = baseDirectory
        } else {
            dir = MeetingStore.defaultBaseDirectory()
        }
        self.fileURL = dir.appendingPathComponent("voiceprints.json")

        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    public func loadProfiles() -> [VoiceprintProfile] {
        guard let data = try? Data(contentsOf: fileURL),
              let profiles = try? decoder.decode([VoiceprintProfile].self, from: data) else {
            return []
        }
        return profiles.sorted { lhs, rhs in
            if lhs.isSelf != rhs.isSelf { return lhs.isSelf }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    public func saveProfiles(_ profiles: [VoiceprintProfile]) {
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let data = try? encoder.encode(profiles) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// Creates a new voiceprint profile or merges the incoming embedding into an existing profile with the same name.
    @discardableResult
    public func upsertProfile(
        name: String,
        role: String = "",
        embedding: [Float],
        isSelf: Bool = false
    ) -> [VoiceprintProfile] {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !embedding.isEmpty else { return loadProfiles() }

        var profiles = loadProfiles()
        if let idx = profiles.firstIndex(where: { $0.name.caseInsensitiveCompare(cleanName) == .orderedSame }) {
            profiles[idx].embedding = VoiceprintMath.mergeEmbeddings(
                existing: profiles[idx].embedding,
                existingCount: profiles[idx].sampleCount,
                incoming: embedding
            )
            profiles[idx].sampleCount += 1
            if !role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                profiles[idx].role = role.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if isSelf { profiles[idx].isSelf = true }
            profiles[idx].updatedAt = Date()
        } else {
            let profile = VoiceprintProfile(
                name: cleanName,
                role: role.trimmingCharacters(in: .whitespacesAndNewlines),
                embedding: embedding,
                sampleCount: 1,
                isSelf: isSelf
            )
            profiles.insert(profile, at: 0)
        }
        saveProfiles(profiles)
        return loadProfiles()
    }

    @discardableResult
    public func renameProfile(id: UUID, newName: String, newRole: String? = nil) -> [VoiceprintProfile] {
        let clean = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return loadProfiles() }
        var profiles = loadProfiles()
        if let idx = profiles.firstIndex(where: { $0.id == id }) {
            profiles[idx].name = clean
            if let newRole {
                profiles[idx].role = newRole.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            profiles[idx].updatedAt = Date()
            saveProfiles(profiles)
        }
        return loadProfiles()
    }

    @discardableResult
    public func deleteProfile(id: UUID) -> [VoiceprintProfile] {
        var profiles = loadProfiles()
        profiles.removeAll { $0.id == id }
        saveProfiles(profiles)
        return loadProfiles()
    }
}

/// On-device Apple Silicon speaker voiceprint extractor powered by SpeechBrain ECAPA-TDNN (`MLXAudioCodecs`),
/// producing L2-normalized 192-dimensional voiceprint embeddings from 16 kHz mono audio.
public actor VoiceprintService {
    public static let shared = VoiceprintService()

    private var encoder: EcapaSpeakerEncoder?
    private var loadedModelID: String?

    public init() {}

    public func ensureLoaded(
        modelID: String = EcapaSpeakerEncoder.defaultRepository,
        hfHost: String = "https://huggingface.co"
    ) async throws -> EcapaSpeakerEncoder {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetID = trimmed.isEmpty ? EcapaSpeakerEncoder.defaultRepository : trimmed

        if let encoder, loadedModelID == targetID {
            return encoder
        }

        // Direct local file/directory support
        let expanded = (targetID as NSString).expandingTildeInPath
        if FileManager.default.fileExists(atPath: expanded) {
            let url = URL(fileURLWithPath: expanded)
            let weightsURL = url.hasDirectoryPath ? url.appendingPathComponent("model.safetensors") : url
            if FileManager.default.fileExists(atPath: weightsURL.path) {
                let loaded = try EcapaSpeakerEncoder.fromWeights(weightsURL)
                self.encoder = loaded
                self.loadedModelID = targetID
                return loaded
            }
        }

        guard let repoID = Repo.ID(rawValue: targetID) else {
            throw VoiceprintError.invalidRepository(targetID)
        }

        let hostURL = URL(string: hfHost.trimmingCharacters(in: .whitespacesAndNewlines)) ?? HubClient.defaultHost
        let hfToken = ProcessInfo.processInfo.environment["HF_TOKEN"]
        let client: HubClient = (hfToken?.isEmpty == false)
            ? HubClient(host: hostURL, bearerToken: hfToken!, cache: .default)
            : HubClient(host: hostURL, cache: .default)

        let localDir = Self.localCacheDirectory(for: targetID)
        try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
        let weightsDest = localDir.appendingPathComponent("model.safetensors")

        if !FileManager.default.isReadableFile(atPath: weightsDest.path) {
            let downloaded = try await client.downloadFile(at: "model.safetensors", from: repoID)
            let resolved = downloaded.resolvingSymlinksInPath()
            try? FileManager.default.removeItem(at: weightsDest)
            try FileManager.default.copyItem(at: resolved, to: weightsDest)
        }

        let loaded = try EcapaSpeakerEncoder.fromWeights(weightsDest)
        self.encoder = loaded
        self.loadedModelID = targetID
        return loaded
    }

    /// Extracts an L2-normalized 192-dim voiceprint embedding from 16 kHz mono audio samples.
    public func extractEmbedding(
        samples16k: [Float],
        modelID: String = EcapaSpeakerEncoder.defaultRepository,
        hfHost: String = "https://huggingface.co"
    ) async throws -> [Float] {
        let minSamples = 12_800 // 0.8s @ 16kHz
        guard samples16k.count >= minSamples else {
            throw VoiceprintError.audioTooShort
        }

        // Use up to 14 seconds of active audio to keep ECAPA inference fast & sharp
        let maxSamples = 16_000 * 14
        let slice = samples16k.count > maxSamples ? Array(samples16k.prefix(maxSamples)) : samples16k

        let enc = try await ensureLoaded(modelID: modelID, hfHost: hfHost)
        let embMLX = try enc.encode(MLXArray(slice))
        eval(embMLX)
        let vec = embMLX.asArray(Float.self)
        Memory.clearCache()
        return VoiceprintMath.l2Normalize(vec)
    }

    public func unload() {
        encoder = nil
        loadedModelID = nil
        Memory.clearCache()
    }

    public static func isModelCachedLocally(modelID: String = EcapaSpeakerEncoder.defaultRepository) -> Bool {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetID = trimmed.isEmpty ? EcapaSpeakerEncoder.defaultRepository : trimmed
        let weights = localCacheDirectory(for: targetID).appendingPathComponent("model.safetensors")
        return FileManager.default.isReadableFile(atPath: weights.path)
    }

    private static func localCacheDirectory(for repoID: String) -> URL {
        let sanitized = repoID.replacingOccurrences(of: "/", with: "_")
        return HubCache.default.cacheDirectory
            .appendingPathComponent("mlx-audio", isDirectory: true)
            .appendingPathComponent(sanitized, isDirectory: true)
    }

    /// Slices and concatenates up to `maxDurationSeconds` of the longest clean intervals for a speaker
    /// from a full 16 kHz mono recording.
    public static func extractSpeakerSamples(
        from fullSamples16k: [Float],
        intervals: [(start: TimeInterval, end: TimeInterval)],
        maxDurationSeconds: Double = 14.0
    ) -> [Float] {
        guard !fullSamples16k.isEmpty, !intervals.isEmpty else { return [] }
        let sampleRate = 16_000.0
        let maxSamples = Int(maxDurationSeconds * sampleRate)

        // Prioritize longer uninterrupted turns for cleaner speaker voiceprints
        let sorted = intervals
            .filter { $0.end - $0.start >= 0.45 }
            .sorted { ($0.end - $0.start) > ($1.end - $1.start) }

        var collected: [Float] = []
        collected.reserveCapacity(min(maxSamples, fullSamples16k.count))

        for interval in sorted {
            let startIdx = max(0, min(fullSamples16k.count, Int(interval.start * sampleRate)))
            let endIdx = max(startIdx, min(fullSamples16k.count, Int(interval.end * sampleRate)))
            guard endIdx > startIdx else { continue }
            let remaining = maxSamples - collected.count
            guard remaining > 0 else { break }
            let takeEnd = min(endIdx, startIdx + remaining)
            collected.append(contentsOf: fullSamples16k[startIdx..<takeEnd])
        }
        return collected
    }
}

/// Short live microphone recorder used in Settings to enroll a 5-second speaker voiceprint sample.
public final class VoiceprintEnrollmentRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var samples16k: [Float] = []
    private var mic: MicrophoneCapture?

    public init() {}

    public func recordSample(
        durationSeconds: TimeInterval = 5.0,
        onProgress: @escaping @Sendable (Double, Float) -> Void
    ) async throws -> [Float] {
        let capture = MicrophoneCapture()
        self.mic = capture
        lock.withLock { samples16k.removeAll(keepingCapacity: true) }

        let start = Date()
        capture.onAudioBuffer = { [weak self] buffer, level in
            guard let self else { return }
            let mono = WAVEncoder.extractMono16kSamples(from: buffer)
            self.lock.withLock {
                self.samples16k.append(contentsOf: mono)
            }
            let frac = min(1.0, max(0.0, Date().timeIntervalSince(start) / max(0.5, durationSeconds)))
            onProgress(frac, level)
        }

        do {
            try await capture.start()
        } catch {
            self.mic = nil
            throw VoiceprintError.recordingFailed(error.localizedDescription)
        }

        let steps = max(1, Int(durationSeconds * 10))
        for step in 1...steps {
            try await Task.sleep(nanoseconds: 100_000_000)
            let frac = min(1.0, Double(step) / Double(steps))
            onProgress(frac, 0)
        }

        capture.stop()
        self.mic = nil

        let recorded = lock.withLock { samples16k }
        guard recorded.count >= 16_000 else {
            throw VoiceprintError.audioTooShort
        }
        return recorded
    }

    public func cancel() {
        mic?.stop()
        mic = nil
    }
}
