import Foundation

enum GeminiError: LocalizedError {
    case missingAPIKey
    case authenticationFailed
    case rateLimitExceeded
    case requestFailed(statusCode: Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Gemini API key is not configured. Set it in Settings."
        case .authenticationFailed:
            "Gemini API key is invalid. Check your key in Settings."
        case .rateLimitExceeded:
            "Gemini rate limit exceeded. Try again later."
        case let .requestFailed(statusCode):
            "Gemini request failed (HTTP \(statusCode))."
        case .invalidResponse:
            "Gemini returned an unexpected response."
        }
    }
}

/// Batch-translates or refines items using the Google Gemini API.
struct GeminiTranslationStep: TranslationPipelineStep {
    let apiKey: String
    let mode: TranslationPrompt.Mode
    let model: String

    var name: String {
        switch mode {
        case .translate: "Translating…"
        case .refine: "Refining…"
        }
    }

    init(apiKey: String, mode: TranslationPrompt.Mode = .translate, model: String = "gemini-2.5-flash") {
        self.apiKey = apiKey
        self.mode = mode
        self.model = model
    }

    /// The `generateContent` endpoint for a given model id.
    static func endpointURL(for model: String) -> URL {
        URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
    }

    func process(_ items: inout [TranslationItem]) async throws {
        guard !apiKey.isEmpty else { throw GeminiError.missingAPIKey }
        guard !items.isEmpty else { return }

        let prompt = TranslationPrompt(mode: mode)
        let systemPrompt = prompt.systemPrompt(for: items.count)
        let userPrompt = prompt.buildUserPrompt(from: items)

        let request = buildRequest(systemPrompt: systemPrompt, userPrompt: userPrompt)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 400:
            throw GeminiError.authenticationFailed
        case 403:
            throw GeminiError.authenticationFailed
        case 429:
            throw GeminiError.rateLimitExceeded
        default:
            throw GeminiError.requestFailed(statusCode: httpResponse.statusCode)
        }

        let text = try parseResponseText(data)
        TranslationResponseMapper.apply(text, to: &items)
    }

    /// The `thinkingBudget` to request for a model, or `nil` to omit
    /// `thinkingConfig` entirely.
    ///
    /// Only the 2.5 Flash tier reliably supports disabling thinking
    /// (`thinkingBudget: 0`) for lower latency. Reasoning models — 2.5 Pro and
    /// the thinking-first Gemini 3.x family — reject budget 0 with
    /// "Budget 0 is invalid. This model only works in thinking mode", so we omit
    /// the config and let them use their default thinking mode.
    static func thinkingBudget(for model: String) -> Int? {
        switch model {
        case "gemini-2.5-flash", "gemini-2.5-flash-lite": 0
        default: nil
        }
    }

    /// Builds the request JSON body. Exposed for testing.
    static func requestBody(systemPrompt: String, userPrompt: String, model: String) -> [String: Any] {
        var generationConfig: [String: Any] = ["temperature": 0.3]
        if let budget = thinkingBudget(for: model) {
            generationConfig["thinkingConfig"] = ["thinkingBudget": budget]
        }
        return [
            "systemInstruction": ["parts": [["text": systemPrompt]]],
            "contents": [["parts": [["text": userPrompt]]]],
            "generationConfig": generationConfig,
        ]
    }

    private func buildRequest(systemPrompt: String, userPrompt: String) -> URLRequest {
        var request = URLRequest(url: Self.endpointURL(for: model))
        request.timeoutInterval = 30
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(
            withJSONObject: Self.requestBody(systemPrompt: systemPrompt, userPrompt: userPrompt, model: model)
        )
        return request
    }

    private func parseResponseText(_ data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String
        else {
            throw GeminiError.invalidResponse
        }
        return text
    }
}
