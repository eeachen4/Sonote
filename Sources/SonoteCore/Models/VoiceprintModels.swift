import Foundation

/// A locally persisted speaker voiceprint profile storing an L2-normalized 192-dim ECAPA-TDNN embedding.
public struct VoiceprintProfile: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var role: String
    public var embedding: [Float]
    public var sampleCount: Int
    public var isSelf: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        role: String = "",
        embedding: [Float],
        sampleCount: Int = 1,
        isSelf: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.embedding = VoiceprintMath.l2Normalize(embedding)
        self.sampleCount = max(1, sampleCount)
        self.isSelf = isSelf
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct VoiceprintMatch: Equatable, Sendable {
    public var profile: VoiceprintProfile
    public var similarity: Float

    public init(profile: VoiceprintProfile, similarity: Float) {
        self.profile = profile
        self.similarity = similarity
    }
}

/// Pure, deterministic speaker embedding vector math utilities.
public enum VoiceprintMath {
    public static func l2Normalize(_ vector: [Float]) -> [Float] {
        guard !vector.isEmpty else { return [] }
        var sumSq: Float = 0
        for v in vector { sumSq += v * v }
        let norm = sqrt(sumSq)
        guard norm > 1e-12 else { return vector }
        return vector.map { $0 / norm }
    }

    public static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard !a.isEmpty, a.count == b.count else { return -1 }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denom = sqrt(normA) * sqrt(normB)
        guard denom > 1e-12 else { return -1 }
        return max(-1.0, min(1.0, dot / denom))
    }

    /// Merges a new sample embedding into an existing profile via weighted running average + L2 normalization.
    public static func mergeEmbeddings(
        existing: [Float],
        existingCount: Int,
        incoming: [Float]
    ) -> [Float] {
        let normIncoming = l2Normalize(incoming)
        guard !existing.isEmpty, existing.count == normIncoming.count else {
            return normIncoming
        }
        let normExisting = l2Normalize(existing)
        let weightOld = Float(max(1, min(existingCount, 20)))
        var merged = [Float](repeating: 0, count: normExisting.count)
        for i in 0..<merged.count {
            merged[i] = (normExisting[i] * weightOld + normIncoming[i]) / (weightOld + 1.0)
        }
        return l2Normalize(merged)
    }

    public static func bestMatch(
        for embedding: [Float],
        in profiles: [VoiceprintProfile],
        threshold: Float = 0.56,
        excludingProfileIDs: Set<UUID> = []
    ) -> VoiceprintMatch? {
        guard !embedding.isEmpty, !profiles.isEmpty else { return nil }
        let query = l2Normalize(embedding)
        var best: VoiceprintMatch?
        for profile in profiles where !excludingProfileIDs.contains(profile.id) {
            let sim = cosineSimilarity(query, profile.embedding)
            if sim >= threshold, sim > (best?.similarity ?? -1) {
                best = VoiceprintMatch(profile: profile, similarity: sim)
            }
        }
        return best
    }
}
