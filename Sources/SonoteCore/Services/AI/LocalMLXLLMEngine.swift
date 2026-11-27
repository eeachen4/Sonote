import Foundation
import MLX
import MLXNN
import MLXAudioCore
import HuggingFace
import Tokenizers

public enum LocalMLXLLMError: LocalizedError {
    case invalidModelID(String)
    case missingConfig(URL)
    case emptyGeneration

    public var errorDescription: String? {
        switch self {
        case .invalidModelID(let id): return "无效的本地 MLX 模型 ID：\(id)"
        case .missingConfig(let url): return "模型目录缺少 config.json：\(url.path)"
        case .emptyGeneration: return "本地 MLX 模型未生成有效回复。"
        }
    }
}

/// Built-in 100% offline Apple Silicon LLM summarization & Q&A engine powered by `MLXAudioCore.Qwen2Model`.
/// Runs quantized Qwen2.5-Instruct models directly inside Sonote on Metal GPU with zero external servers
/// and zero API token cost.
public actor LocalMLXLLMEngine {
    public static let shared = LocalMLXLLMEngine()

    private var model: Qwen2Model?
    private var tokenizer: Tokenizer?
    private var loadedModelID: String?
    private var eosTokenIDs: Set<Int> = [151645, 151643] // Qwen2.5 <|im_end|>, <|endoftext|>

    private struct QuantizationSection: Decodable {
        var groupSize: Int = 64
        var bits: Int = 4

        enum CodingKeys: String, CodingKey {
            case groupSize = "group_size"
            case bits
        }

        init(from decoder: any Swift.Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            groupSize = try c.decodeIfPresent(Int.self, forKey: .groupSize) ?? 64
            bits = try c.decodeIfPresent(Int.self, forKey: .bits) ?? 4
        }
    }

    private struct ExtendedConfigMeta: Decodable {
        var quantization: QuantizationSection?
        var eosTokenID: [Int]?

        enum CodingKeys: String, CodingKey {
            case quantization
            case eosTokenID = "eos_token_id"
        }

        init(from decoder: any Swift.Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            quantization = try c.decodeIfPresent(QuantizationSection.self, forKey: .quantization)
            if let arr = try? c.decodeIfPresent([Int].self, forKey: .eosTokenID) {
                eosTokenID = arr
            } else if let single = try? c.decodeIfPresent(Int.self, forKey: .eosTokenID) {
                eosTokenID = [single]
            }
        }
    }

    public init() {}

    public func isLoaded(modelID: String) -> Bool {
        model != nil && loadedModelID == modelID
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
        if directoryContainsSafetensors(mlxAudioDir) { return true }

        let hfModelDir = cacheDir.appendingPathComponent("models/\(trimmed)")
        if directoryContainsSafetensors(hfModelDir) { return true }

        return false
    }

    private static func directoryContainsSafetensors(_ dir: URL) -> Bool {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return false }
        return contents.contains { $0.hasSuffix(".safetensors") }
    }

    public func ensureLoaded(
        modelID: String,
        hfHost: String = "https://huggingface.co"
    ) async throws -> (Qwen2Model, Tokenizer) {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetID = trimmed.isEmpty ? "mlx-community/Qwen2.5-3B-Instruct-4bit" : trimmed

        if let model, let tokenizer, loadedModelID == targetID {
            return (model, tokenizer)
        }

        let modelDir: URL
        let expanded = (targetID as NSString).expandingTildeInPath
        if FileManager.default.fileExists(atPath: (expanded as NSString).appendingPathComponent("config.json")) {
            modelDir = URL(fileURLWithPath: expanded)
        } else {
            guard let repoID = Repo.ID(rawValue: targetID) else {
                throw LocalMLXLLMError.invalidModelID(targetID)
            }
            let hostURL = URL(string: hfHost.trimmingCharacters(in: .whitespacesAndNewlines)) ?? HubClient.defaultHost
            let hfToken = ProcessInfo.processInfo.environment["HF_TOKEN"]
            let client: HubClient = (hfToken?.isEmpty == false)
                ? HubClient(host: hostURL, bearerToken: hfToken!, cache: .default)
                : HubClient(host: hostURL, cache: .default)

            modelDir = try await ModelUtils.resolveOrDownloadModel(
                client: client,
                cache: .default,
                repoID: repoID,
                requiredExtension: "safetensors"
            )
        }

        let configURL = modelDir.appendingPathComponent("config.json")
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            throw LocalMLXLLMError.missingConfig(modelDir)
        }
        let configData = try Data(contentsOf: configURL)
        let qwenConfig = try JSONDecoder().decode(Qwen2Configuration.self, from: configData)
        let meta = try? JSONDecoder().decode(ExtendedConfigMeta.self, from: configData)

        let loadedTokenizer = try await AutoTokenizer.from(modelFolder: modelDir)

        var weights: [String: MLXArray] = [:]
        let files = try FileManager.default.contentsOfDirectory(at: modelDir, includingPropertiesForKeys: nil)
        for file in files where file.pathExtension.lowercased() == "safetensors" {
            let chunk = try MLX.loadArrays(url: file)
            weights.merge(chunk) { _, new in new }
        }

        let qwenModel = Qwen2Model(qwenConfig)
        let sanitized = qwenModel.sanitize(weights: weights)

        if let quant = meta?.quantization {
            quantize(model: qwenModel) { path, _ in
                if sanitized["\(path).scales"] != nil {
                    return (groupSize: quant.groupSize, bits: quant.bits, mode: .affine)
                }
                return nil
            }
        }

        try qwenModel.update(parameters: ModuleParameters.unflattened(sanitized), verify: .noUnusedKeys)
        eval(qwenModel)

        var stopIDs: Set<Int> = [151645, 151643]
        if let cfgEOS = meta?.eosTokenID {
            stopIDs.formUnion(cfgEOS)
        }
        if let tokEOS = loadedTokenizer.eosTokenId {
            stopIDs.insert(tokEOS)
        }

        self.model = qwenModel
        self.tokenizer = loadedTokenizer
        self.loadedModelID = targetID
        self.eosTokenIDs = stopIDs
        return (qwenModel, loadedTokenizer)
    }

    public func complete(
        instructions: String,
        userPrompt: String,
        modelID: String,
        hfHost: String = "https://huggingface.co",
        maxTokens: Int = 1536,
        temperature: Float = 0.2,
        onDelta: (@Sendable (String) -> Void)? = nil
    ) async throws -> GPTCompletionResult {
        let (qwenModel, tok) = try await ensureLoaded(modelID: modelID, hfHost: hfHost)

        let prompt = Self.formatQwenChatML(system: instructions, user: userPrompt)
        let promptTokens = tok.encode(text: prompt)
        guard !promptTokens.isEmpty else {
            throw LocalMLXLLMError.emptyGeneration
        }

        // Prefill prompt in chunks of 512 tokens via KVCacheSimple to keep peak GPU memory low
        let cache = try qwenModel.newCache(parameters: nil)
        let chunkSize = 512
        var cursor = 0
        var lastLogits: MLXArray? = nil

        while cursor < promptTokens.count {
            try Task.checkCancellation()
            let end = min(promptTokens.count, cursor + chunkSize)
            let chunkIDs = Array(promptTokens[cursor..<end])
            let inputArr = MLXArray(chunkIDs).expandedDimensions(axis: 0)
            let logits = qwenModel(inputArr, cache: cache)
            lastLogits = logits[0, -1, 0...]
            eval(lastLogits!)
            cursor = end
        }

        guard var currentLogits = lastLogits else {
            throw LocalMLXLLMError.emptyGeneration
        }

        let sampler: LogitSampler = temperature <= 0.05
            ? ArgMaxSampler()
            : TopPSampler(temperature: temperature, topP: 0.9)

        var generatedIDs: [Int] = []
        var emittedText = ""

        for step in 0..<maxTokens {
            try Task.checkCancellation()
            let nextTokenArr = sampler.sample(logits: currentLogits.expandedDimensions(axis: 0))
            eval(nextTokenArr)
            let nextTokenID = nextTokenArr.item(Int.self)

            if eosTokenIDs.contains(nextTokenID) {
                break
            }

            generatedIDs.append(nextTokenID)

            // Decode incrementally every 2 tokens (cleanly handles multi-byte CJK UTF-8 sequences)
            if step % 2 == 1 || step == maxTokens - 1 {
                let decoded = tok.decode(tokens: generatedIDs)
                if decoded.count > emittedText.count && !decoded.hasSuffix("\u{FFFD}") {
                    let delta = String(decoded.dropFirst(emittedText.count))
                    emittedText = decoded
                    if !delta.isEmpty {
                        onDelta?(delta)
                    }
                }
            }

            let stepInput = MLXArray([nextTokenID]).expandedDimensions(axis: 0)
            let logits = qwenModel(stepInput, cache: cache)
            currentLogits = logits[0, -1, 0...]
        }

        let finalDecoded = tok.decode(tokens: generatedIDs).trimmingCharacters(in: .whitespacesAndNewlines)
        if finalDecoded.count > emittedText.count {
            let tail = String(finalDecoded.dropFirst(emittedText.count))
            if !tail.isEmpty { onDelta?(tail) }
        }
        Memory.clearCache()

        guard !finalDecoded.isEmpty else {
            throw LocalMLXLLMError.emptyGeneration
        }

        let usage = TokenUsage(
            inputTokens: promptTokens.count,
            outputTokens: generatedIDs.count,
            requestCount: 1,
            isEstimated: false
        )
        return GPTCompletionResult(text: finalDecoded, usage: usage)
    }

    public func unload() {
        model = nil
        tokenizer = nil
        loadedModelID = nil
        Memory.clearCache()
    }

    public static func formatQwenChatML(system: String, user: String) -> String {
        """
        <|im_start|>system
        \(system)<|im_end|>
        <|im_start|>user
        \(user)<|im_end|>
        <|im_start|>assistant
        """
    }
}
