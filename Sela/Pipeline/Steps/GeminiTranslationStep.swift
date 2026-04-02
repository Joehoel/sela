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

    var name: String {
        switch mode {
        case .translate: "Translating…"
        case .refine: "Refining…"
        }
    }

    init(apiKey: String, mode: TranslationPrompt.Mode = .translate) {
        self.apiKey = apiKey
        self.mode = mode
    }

    private static let endpoint = URL(
        string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
    )!

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

        let lines = try parseResponse(data)

        for index in items.indices where index < lines.count {
            items[index].currentText = lines[index]
        }
    }

    private func buildRequest(systemPrompt: String, userPrompt: String) -> URLRequest {
        var request = URLRequest(url: Self.endpoint)
        request.timeoutInterval = 30
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "systemInstruction": [
                "parts": [["text": systemPrompt]],
            ],
            "contents": [
                [
                    "parts": [["text": userPrompt]],
                ],
            ],
            "generationConfig": [
                "temperature": 0.3,
                "thinkingConfig": ["thinkingBudget": 0],
            ],
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func parseResponse(_ data: Data) throws -> [String] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String
        else {
            throw GeminiError.invalidResponse
        }

        return text
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}
