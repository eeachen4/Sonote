import Foundation
import MLX
import MLXAudioCore
import MLXAudioVAD
import HuggingFace

public struct DiarizationLabelResult: Sendable {
    public var segments: [TranscriptSegment]
    public var matchedVoiceprintNames: [String]
    public var totalRemoteSpeakersDetected: Int

    public init(segments: [TranscriptSegment], matchedVoiceprintNames: [String], totalRemoteSpeakersDetected: Int) {
        self.segments = segments
        self.matchedVoiceprintNames = matchedVoiceprintNames
        self.totalRemoteSpeakersDetected = totalRemoteSpeakersDetected
    }
}

/// Multi-speaker diarization powered by NVIDIA Sortformer (`MLXAudioVAD`),
/// paired with SpeechBrain ECAPA-TDNN (`VoiceprintService`) for cross-meeting automatic speaker recognition.
public actor SpeakerDiarizerService {
    public static let shared = SpeakerDiarizerService()

    private var model: SortformerModel?
    private var loadedModelID: String?

    public init() {}

    public func ensureLoaded(
        modelID: String = "mlx-community/diar_streaming_sortformer_4spk-v2.1-fp16",
        hfHost: String = "https://huggingface.co"
    ) async throws -> SortformerModel {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetID = trimmed.isEmpty ? "mlx-community/diar_streaming_sortformer_4spk-v2.1-fp16" : trimmed

        if let existing = model, loadedModelID == targetID {
            return existing
        }

        guard let repoID = Repo.ID(rawValue: targetID) else {
            throw NSError(domain: "Sonote.Diarizer", code: 1, userInfo: [NSLocalizedDescriptionKey: "无效的声纹模型 ID：\(targetID)"])
        }

        let hostURL = URL(string: hfHost.trimmingCharacters(in: .whitespacesAndNewlines)) ?? HubClient.defaultHost
        let hfToken = ProcessInfo.processInfo.environment["HF_TOKEN"]
        let client: HubClient = (hfToken?.isEmpty == false)
            ? HubClient(host: hostURL, bearerToken: hfToken!, cache: .default)
            : HubClient(host: hostURL, cache: .default)

        let modelURL = try await ModelUtils.resolveOrDownloadModel(
            client: client,
            cache: .default,
            repoID: repoID,
            requiredExtension: "safetensors"
        )
        let loaded = try SortformerModel.fromModelDirectory(modelURL)
        self.model = loaded
        self.loadedModelID = targetID
        return loaded
    }

    public func diarize(
        samples16k: [Float],
        modelID: String = "mlx-community/diar_streaming_sortformer_4spk-v2.1-fp16",
        hfHost: String = "https://huggingface.co"
    ) async throws -> [DiarizationSegment] {
        guard samples16k.count >= 16_000 else { return [] }
        let sortformer = try await ensureLoaded(modelID: modelID, hfHost: hfHost)
        let audio = MLXArray(samples16k)
        let output = try await sortformer.generate(
            audio: audio,
            sampleRate: 16_000,
            threshold: 0.5,
            minDuration: 0.3,
            mergeGap: 0.4,
            verbose: false
        )
        Memory.clearCache()
        return output.segments
    }

    public func unload() {
        model = nil
        loadedModelID = nil
        Memory.clearCache()
    }

    /// Maps each transcript segment to Sortformer speaker labels ("发言人 1" ... "发言人 4"),
    /// optionally applying a custom name map (e.g. from ECAPA voiceprint matching) and `localUserName` for `.me`.
    public static func assignSpeakerLabels(
        segments: [TranscriptSegment],
        diarization: [DiarizationSegment],
        speakerNameOverrides: [Int: String] = [:],
        localUserName: String = ""
    ) -> [TranscriptSegment] {
        guard !diarization.isEmpty else { return segments }

        var speakerOrder: [Int: Int] = [:]
        var nextIndex = 1
        for d in diarization.sorted(by: { $0.start < $1.start }) {
            if speakerOrder[d.speaker] == nil {
                speakerOrder[d.speaker] = nextIndex
                nextIndex += 1
            }
        }

        let cleanLocalName = localUserName.trimmingCharacters(in: .whitespacesAndNewlines)

        return segments.map { seg in
            if seg.speaker == .me {
                var updated = seg
                if (updated.speakerLabel?.isEmpty ?? true), !cleanLocalName.isEmpty {
                    updated.speakerLabel = cleanLocalName
                }
                return updated
            }

            let t = Float(seg.timestamp)
            var bestSpeaker: Int? = nil
            var bestDistance: Float = 2.5
            for d in diarization {
                if t >= d.start - 0.3 && t <= d.end + 0.3 {
                    bestSpeaker = d.speaker
                    bestDistance = 0
                    break
                }
                let dist = min(abs(t - d.start), abs(t - d.end))
                if dist < bestDistance {
                    bestDistance = dist
                    bestSpeaker = d.speaker
                }
            }
            var updated = seg
            if let spk = bestSpeaker {
                if let resolvedName = speakerNameOverrides[spk], !resolvedName.isEmpty {
                    updated.speakerLabel = resolvedName
                } else if let friendlyIdx = speakerOrder[spk] {
                    updated.speakerLabel = "发言人 \(friendlyIdx)"
                }
            }
            return updated
        }
    }

    /// Runs cross-meeting ECAPA-TDNN voiceprint matching on each Sortformer speaker cluster
    /// against the local voiceprint library, automatically replacing generic `发言人 N` labels with real names.
    public static func assignSpeakerLabelsWithVoiceprints(
        segments: [TranscriptSegment],
        diarization: [DiarizationSegment],
        fullSamples16k: [Float],
        profiles: [VoiceprintProfile],
        matchThreshold: Float = 0.56,
        voiceprintModelID: String = "aufklarer/SpeechBrain-ECAPA-VoxCeleb-20M-MLX",
        hfHost: String = "https://huggingface.co",
        localUserName: String = "",
        autoUnloadVoiceprintModel: Bool = true
    ) async -> DiarizationLabelResult {
        let uniqueSpeakers = Array(Set(diarization.map(\.speaker))).sorted()
        guard !uniqueSpeakers.isEmpty else {
            return DiarizationLabelResult(segments: segments, matchedVoiceprintNames: [], totalRemoteSpeakersDetected: 0)
        }

        var overrides: [Int: String] = [:]
        var matchedNames: [String] = []

        if !profiles.isEmpty && !fullSamples16k.isEmpty {
            // Group intervals per Sortformer speaker ID
            var intervalsBySpeaker: [Int: [(start: TimeInterval, end: TimeInterval)]] = [:]
            for d in diarization {
                intervalsBySpeaker[d.speaker, default: []].append((start: TimeInterval(d.start), end: TimeInterval(d.end)))
            }

            // Extract embeddings for every cluster with enough audio, then greedily assign highest-similarity unique matches
            var candidates: [(speakerID: Int, match: VoiceprintMatch)] = []
            for spk in uniqueSpeakers {
                let clusterSamples = VoiceprintService.extractSpeakerSamples(
                    from: fullSamples16k,
                    intervals: intervalsBySpeaker[spk] ?? [],
                    maxDurationSeconds: 14.0
                )
                guard clusterSamples.count >= 16_000 else { continue }
                if let embedding = try? await VoiceprintService.shared.extractEmbedding(
                    samples16k: clusterSamples,
                    modelID: voiceprintModelID,
                    hfHost: hfHost
                ), let match = VoiceprintMath.bestMatch(for: embedding, in: profiles, threshold: matchThreshold) {
                    candidates.append((speakerID: spk, match: match))
                }
            }

            // Greedy highest-similarity unique assignment so two distinct speakers don't collide on the same profile
            var usedProfiles: Set<UUID> = []
            for item in candidates.sorted(by: { $0.match.similarity > $1.match.similarity }) {
                guard overrides[item.speakerID] == nil, !usedProfiles.contains(item.match.profile.id) else {
                    continue
                }
                overrides[item.speakerID] = item.match.profile.name
                usedProfiles.insert(item.match.profile.id)
                matchedNames.append(item.match.profile.name)
            }

            if autoUnloadVoiceprintModel {
                await VoiceprintService.shared.unload()
            }
        }

        let labeled = assignSpeakerLabels(
            segments: segments,
            diarization: diarization,
            speakerNameOverrides: overrides,
            localUserName: localUserName
        )
        return DiarizationLabelResult(
            segments: labeled,
            matchedVoiceprintNames: matchedNames,
            totalRemoteSpeakersDetected: uniqueSpeakers.count
        )
    }

    /// Unlimited-speaker (>4) diarization via ECAPA-TDNN voiceprint clustering:
    /// extracts a 192-dim speaker embedding for each remote/mixed utterance, matches known local voiceprints first,
    /// and clusters remaining unknown speakers online by cosine similarity (supporting 5~12+ speaker large meetings).
    public static func diarizeByVoiceprintClustering(
        segments: [TranscriptSegment],
        fullSamples16k: [Float],
        meetingDuration: TimeInterval,
        profiles: [VoiceprintProfile],
        matchThreshold: Float = 0.56,
        clusterThreshold: Float = 0.58,
        voiceprintModelID: String = "aufklarer/SpeechBrain-ECAPA-VoxCeleb-20M-MLX",
        hfHost: String = "https://huggingface.co",
        localUserName: String = "",
        autoUnloadVoiceprintModel: Bool = true
    ) async -> DiarizationLabelResult {
        guard !segments.isEmpty, !fullSamples16k.isEmpty else {
            return DiarizationLabelResult(segments: segments, matchedVoiceprintNames: [], totalRemoteSpeakersDetected: 0)
        }

        let bank = OnlineSpeakerClusterBank(
            enrolledProfiles: profiles,
            knownMatchThreshold: matchThreshold,
            newClusterThreshold: clusterThreshold
        )
        let cleanLocal = localUserName.trimmingCharacters(in: .whitespacesAndNewlines)
        var updated = segments

        for idx in segments.indices {
            let seg = segments[idx]
            if seg.speaker == .me {
                if (updated[idx].speakerLabel?.isEmpty ?? true), !cleanLocal.isEmpty {
                    updated[idx].speakerLabel = cleanLocal
                }
                continue
            }

            let nextTs: TimeInterval = (idx + 1 < segments.count)
                ? segments[idx + 1].timestamp
                : max(seg.timestamp + 6.0, meetingDuration)
            let endTs = min(nextTs, seg.timestamp + 12.0)
            guard endTs - seg.timestamp >= 0.85 else { continue }

            let slice = VoiceprintService.extractSpeakerSamples(
                from: fullSamples16k,
                intervals: [(start: seg.timestamp, end: endTs)],
                maxDurationSeconds: 12.0
            )
            guard slice.count >= 12_800 else { continue }

            if let emb = try? await VoiceprintService.shared.extractEmbedding(
                samples16k: slice,
                modelID: voiceprintModelID,
                hfHost: hfHost
            ) {
                let resolved = bank.identifyOrCluster(embedding: emb)
                updated[idx].speakerLabel = resolved
            }
        }

        if autoUnloadVoiceprintModel {
            await VoiceprintService.shared.unload()
        }

        return DiarizationLabelResult(
            segments: updated,
            matchedVoiceprintNames: bank.matchedEnrolledNames,
            totalRemoteSpeakersDetected: bank.totalSpeakerCount
        )
    }
}

/// Thread-safe online ECAPA-TDNN speaker bank supporting BOTH live real-time speaker identification
/// during active meetings AND unlimited-speaker (>4) large-meeting clustering.
public final class OnlineSpeakerClusterBank: @unchecked Sendable {
    private struct DynamicCluster {
        var label: String
        var centroid: [Float]
        var count: Int
    }

    private let lock = NSLock()
    private let enrolledProfiles: [VoiceprintProfile]
    private let knownMatchThreshold: Float
    private let newClusterThreshold: Float
    private let maxDynamicClusters: Int

    private var dynamicClusters: [DynamicCluster] = []
    private var matchedKnownSet: Set<String> = []
    private var matchedKnownOrdered: [String] = []

    public init(
        enrolledProfiles: [VoiceprintProfile] = [],
        knownMatchThreshold: Float = 0.56,
        newClusterThreshold: Float = 0.58,
        maxDynamicClusters: Int = 12
    ) {
        self.enrolledProfiles = enrolledProfiles
        self.knownMatchThreshold = knownMatchThreshold
        self.newClusterThreshold = newClusterThreshold
        self.maxDynamicClusters = max(2, maxDynamicClusters)
    }

    public var matchedEnrolledNames: [String] {
        lock.withLock { matchedKnownOrdered }
    }

    public var totalSpeakerCount: Int {
        lock.withLock { matchedKnownSet.count + dynamicClusters.count }
    }

    /// Identifies an utterance embedding against enrolled voiceprints first;
    /// if unknown, assigns to the closest dynamic speaker cluster or spawns a new `发言人 N`.
    public func identifyOrCluster(embedding: [Float]) -> String {
        let query = VoiceprintMath.l2Normalize(embedding)
        guard !query.isEmpty else { return "发言人" }

        return lock.withLock {
            // 1. Match against persistent enrolled voiceprint library first
            if let known = VoiceprintMath.bestMatch(
                for: query,
                in: enrolledProfiles,
                threshold: knownMatchThreshold
            ) {
                if !matchedKnownSet.contains(known.profile.name) {
                    matchedKnownSet.insert(known.profile.name)
                    matchedKnownOrdered.append(known.profile.name)
                }
                return known.profile.name
            }

            // 2. Match against existing dynamic clusters from this meeting
            var bestIdx: Int? = nil
            var bestSim: Float = -1
            for idx in dynamicClusters.indices {
                let sim = VoiceprintMath.cosineSimilarity(query, dynamicClusters[idx].centroid)
                if sim > bestSim {
                    bestSim = sim
                    bestIdx = idx
                }
            }

            if let idx = bestIdx, bestSim >= newClusterThreshold {
                dynamicClusters[idx].centroid = VoiceprintMath.mergeEmbeddings(
                    existing: dynamicClusters[idx].centroid,
                    existingCount: dynamicClusters[idx].count,
                    incoming: query
                )
                dynamicClusters[idx].count += 1
                return dynamicClusters[idx].label
            }

            // 3. Create a new speaker cluster up to maxDynamicClusters (e.g. 12)
            if dynamicClusters.count < maxDynamicClusters {
                let label = "发言人 \(dynamicClusters.count + 1)"
                dynamicClusters.append(DynamicCluster(label: label, centroid: query, count: 1))
                return label
            }

            // Cap reached: assign to nearest dynamic cluster
            if let idx = bestIdx {
                return dynamicClusters[idx].label
            }
            return "发言人 1"
        }
    }
}
