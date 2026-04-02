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

        var components: [String] = []
        for item in items {
            components.append("text=\(urlEncode(item.sourceText))")
        }
        components.append("source_lang=EN")
        components.append("target_lang=NL")

        request.httpBody = components.joined(separator: "&").data(using: .utf8)
        return request
    }

    private func urlEncode(_ string: String) -> String {
        string.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? string
    }
}

struct DeepLResponse: Decodable {
    let translations: [Translation]

    struct Translation: Decodable {
        let text: String
    }
}
