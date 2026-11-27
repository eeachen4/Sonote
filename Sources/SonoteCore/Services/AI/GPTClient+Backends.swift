import Foundation

// MARK: - Streaming LLM Provider Backends (Codex, OpenAI/Domestic, Anthropic Claude, Google Gemini)

extension GPTClient {

    // MARK: - Backend 1: ChatGPT Codex Responses API (SSE)

    func callCodexResponses(
        oauth: CodexOAuthCredential,
        model: String,
        instructions: String,
        userPrompt: String,
        onDelta: (@Sendable (String) -> Void)?
    ) async throws -> GPTCompletionResult {
        guard let url = URL(string: Self.codexResponsesURL) else {
            throw GPTClientError.invalidEndpoint(Self.codexResponsesURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(oauth.accessToken)", forHTTPHeaderField: "Authorization")
        if let accountID = oauth.accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("responses=experimental", forHTTPHeaderField: "OpenAI-Beta")
        request.setValue("codex_cli_rs", forHTTPHeaderField: "originator")

        let payload: [String: Any] = [
            "model": model,
            "instructions": instructions,
            "input": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "input_text",
                            "text": userPrompt
                        ]
                    ]
                ]
            ],
            "store": false,
            "stream": true
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GPTClientError.emptyResponse
        }

        guard (200...299).contains(http.statusCode) else {
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
                if errorBody.count > 400 { break }
            }
            throw GPTClientError.httpError(http.statusCode, errorBody.isEmpty ? "请检查本机 Codex 登录状态或所选模型是否可用" : errorBody)
        }

        var accumulated = ""
        var completedFallback = ""
        var reportedUsage: TokenUsage?

        for try await line in bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("data:") else { continue }
            let jsonString = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if jsonString == "[DONE]" { break }

            let parsed = Self.parseCodexSSEDataLine(jsonString)
            if let errorMessage = parsed.errorMessage {
                throw GPTClientError.httpError(400, errorMessage)
            }
            if let delta = parsed.delta, !delta.isEmpty {
                accumulated += delta
                onDelta?(delta)
            }
            if let full = parsed.completedText, !full.isEmpty {
                completedFallback = full
            }
            if let usage = parsed.usage {
                reportedUsage = usage
            }
        }

        let finalText = accumulated.isEmpty ? completedFallback : accumulated
        guard !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GPTClientError.emptyResponse
        }
        let finalUsage = reportedUsage ?? TokenUsage.estimate(prompt: instructions + "\n" + userPrompt, completion: finalText)
        return GPTCompletionResult(text: finalText, usage: finalUsage)
    }

    // MARK: - Backend 2: Standard OpenAI / DeepSeek / Qwen / Domestic Compatible Chat Completions

    func callOpenAIChatCompletions(
        apiKey: String,
        baseURL: String,
        model: String,
        instructions: String,
        userPrompt: String,
        includeStreamUsage: Bool,
        onDelta: (@Sendable (String) -> Void)?
    ) async throws -> GPTCompletionResult {
        let endpoint = "\(baseURL)/chat/completions"
        guard let url = URL(string: endpoint) else {
            throw GPTClientError.invalidEndpoint(endpoint)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        if !apiKey.isEmpty && apiKey != "local-no-key" {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var payload: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": [
                ["role": "system", "content": instructions],
                ["role": "user", "content": userPrompt]
            ]
        ]
        if includeStreamUsage {
            payload["stream_options"] = ["include_usage": true]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GPTClientError.emptyResponse
        }

        guard (200...299).contains(http.statusCode) else {
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
                if errorBody.count > 400 { break }
            }
            throw GPTClientError.httpError(http.statusCode, errorBody.isEmpty ? "请检查 API Key、Base URL 与模型名称" : errorBody)
        }

        var accumulated = ""
        var rawBuffer = ""
        var reportedUsage: TokenUsage?

        for try await line in bytes.lines {
            rawBuffer += line + "\n"
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("data:") else { continue }
            let jsonString = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if jsonString == "[DONE]" { break }

            let chunk = Self.parseChatCompletionsSSEChunk(jsonString)
            if let delta = chunk.delta, !delta.isEmpty {
                accumulated += delta
                onDelta?(delta)
            }
            if let usage = chunk.usage {
                reportedUsage = usage
            }
        }

        // Fallback if a proxy ignored stream=true and returned a regular JSON object
        if accumulated.isEmpty,
           let data = rawBuffer.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let choices = json["choices"] as? [[String: Any]],
               let message = choices.first?["message"] as? [String: Any],
               let content = message["content"] as? String {
                accumulated = content
            }
            if reportedUsage == nil, let usageDict = json["usage"] as? [String: Any] {
                reportedUsage = Self.parseUsageDict(usageDict)
            }
        }

        guard !accumulated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GPTClientError.emptyResponse
        }
        let finalUsage = reportedUsage ?? TokenUsage.estimate(prompt: instructions + "\n" + userPrompt, completion: accumulated)
        return GPTCompletionResult(text: accumulated, usage: finalUsage)
    }

    // MARK: - Backend 3: Anthropic Claude Messages API (SSE)

    func callAnthropicMessages(
        apiKey: String,
        baseURL: String,
        model: String,
        instructions: String,
        userPrompt: String,
        onDelta: (@Sendable (String) -> Void)?
    ) async throws -> GPTCompletionResult {
        let endpoint = "\(baseURL)/messages"
        guard let url = URL(string: endpoint) else {
            throw GPTClientError.invalidEndpoint(endpoint)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "stream": true,
            "system": instructions,
            "messages": [
                ["role": "user", "content": userPrompt]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GPTClientError.emptyResponse
        }
        guard (200...299).contains(http.statusCode) else {
            var errBody = ""
            for try await line in bytes.lines {
                errBody += line
                if errBody.count > 400 { break }
            }
            throw GPTClientError.httpError(http.statusCode, errBody.isEmpty ? "请检查 Claude API Key 与模型名称" : errBody)
        }

        var accumulated = ""
        var inputTokens = 0
        var outputTokens = 0
        var cachedTokens = 0

        for try await line in bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("data:") else { continue }
            let jsonStr = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
            let parsed = Self.parseAnthropicSSEDataLine(jsonStr)
            if let err = parsed.errorMessage {
                throw GPTClientError.httpError(400, err)
            }
            if let delta = parsed.delta, !delta.isEmpty {
                accumulated += delta
                onDelta?(delta)
            }
            if let inp = parsed.inputTokens { inputTokens = max(inputTokens, inp) }
            if let out = parsed.outputTokens { outputTokens = max(outputTokens, out) }
            if let cached = parsed.cachedTokens { cachedTokens = max(cachedTokens, cached) }
        }

        guard !accumulated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GPTClientError.emptyResponse
        }
        let usage: TokenUsage
        if inputTokens > 0 || outputTokens > 0 {
            usage = TokenUsage(inputTokens: inputTokens, outputTokens: outputTokens, cachedTokens: cachedTokens, requestCount: 1, isEstimated: false)
        } else {
            usage = TokenUsage.estimate(prompt: instructions + "\n" + userPrompt, completion: accumulated)
        }
        return GPTCompletionResult(text: accumulated, usage: usage)
    }

    // MARK: - Backend 4: Google Gemini Stream API (SSE)

    func callGoogleGemini(
        apiKey: String,
        baseURL: String,
        model: String,
        instructions: String,
        userPrompt: String,
        onDelta: (@Sendable (String) -> Void)?
    ) async throws -> GPTCompletionResult {
        let encodedModel = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
        let encodedKey = apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? apiKey
        let endpoint = "\(baseURL)/models/\(encodedModel):streamGenerateContent?alt=sse&key=\(encodedKey)"
        guard let url = URL(string: endpoint) else {
            throw GPTClientError.invalidEndpoint(endpoint)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "system_instruction": [
                "parts": [["text": instructions]]
            ],
            "contents": [
                [
                    "role": "user",
                    "parts": [["text": userPrompt]]
                ]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GPTClientError.emptyResponse
        }
        guard (200...299).contains(http.statusCode) else {
            var errBody = ""
            for try await line in bytes.lines {
                errBody += line
                if errBody.count > 400 { break }
            }
            throw GPTClientError.httpError(http.statusCode, errBody.isEmpty ? "请检查 Gemini API Key 与模型名称" : errBody)
        }

        var accumulated = ""
        var reportedUsage: TokenUsage?

        for try await line in bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("data:") else { continue }
            let jsonStr = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
            let chunk = Self.parseGeminiSSEDataLine(jsonStr)
            if let delta = chunk.delta, !delta.isEmpty {
                accumulated += delta
                onDelta?(delta)
            }
            if let usage = chunk.usage {
                reportedUsage = usage
            }
        }

        guard !accumulated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GPTClientError.emptyResponse
        }
        let finalUsage = reportedUsage ?? TokenUsage.estimate(prompt: instructions + "\n" + userPrompt, completion: accumulated)
        return GPTCompletionResult(text: accumulated, usage: finalUsage)
    }
}
