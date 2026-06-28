import Foundation

enum DeepLError: LocalizedError {
    case missingAPIKey
    case authenticationFailed
    case rateLimitExceeded
    case requestFailed(statusCode: Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "DeepL API key is not configured. Set it in Settings."
        case .authenticationFailed:
            "DeepL API key is invalid. Check your key in Settings."
        case .rateLimitExceeded:
            "DeepL rate limit exceeded. Try again later."
        case let .requestFailed(statusCode):
            "DeepL request failed (HTTP \(statusCode))."
        case .invalidResponse:
            "DeepL returned an unexpected response."
        }
    }
}

/// Batch-translates items from English to Dutch using the DeepL API.
struct DeepLTranslationStep: TranslationPipelineStep {
    let name = "Translating…"
    let apiKey: String
    /// DeepL `model_type` (e.g. "latency_optimized", "quality_optimized").
    /// `nil` uses DeepL's account default.
    let modelType: String?

    init(apiKey: String, modelType: String? = nil) {
        self.apiKey = apiKey
        self.modelType = modelType
    }

    private static let endpoint = URL(string: "https://api-free.deepl.com/v2/translate")!

    func process(_ items: inout [TranslationItem]) async throws {
        guard !apiKey.isEmpty else { throw DeepLError.missingAPIKey }

        let request = try buildRequest(for: items)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DeepLError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 403:
            throw DeepLError.authenticationFailed
        case 429, 529:
            throw DeepLError.rateLimitExceeded
        default:
            throw DeepLError.requestFailed(statusCode: httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(DeepLResponse.self, from: data)

        guard decoded.translations.count == items.count else {
            throw DeepLError.invalidResponse
        }

        for (index, translation) in decoded.translations.enumerated() {
            items[index].currentText = translation.text
        }
    }

    private func buildRequest(for items: [TranslationItem]) throws -> URLRequest {
        var request = URLRequest(url: Self.endpoint)
        request.timeoutInterval = 30
        request.httpMethod = "POST"
        request.setValue("DeepL-Auth-Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody(for: items.map(\.sourceText), modelType: modelType).data(using: .utf8)
        return request
    }

    /// Builds the form-encoded request body. Exposed for testing.
    static func formBody(for sourceTexts: [String], modelType: String?) -> String {
        var components = sourceTexts.map { "text=\(urlEncode($0))" }
        components.append("source_lang=EN")
        components.append("target_lang=NL")
        if let modelType, !modelType.isEmpty {
            components.append("model_type=\(urlEncode(modelType))")
        }
        return components.joined(separator: "&")
    }

    private static func urlEncode(_ string: String) -> String {
        string.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? string
    }
}

struct DeepLResponse: Decodable {
    let translations: [Translation]

    struct Translation: Decodable {
        let text: String
    }
}
