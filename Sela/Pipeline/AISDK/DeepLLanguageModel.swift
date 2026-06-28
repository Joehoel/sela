import Foundation

enum DeepLError: LocalizedError, Equatable {
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

/// DeepL as a custom `LanguageModelV3`, routed through the unified
/// `AISDKTranslationStep` like every other engine. It is not an LLM, so the
/// shared `CustomTranslationLanguageModel` base turns the numbered prompt into
/// source lines, calls this `translate(_:)`, and serializes the result into the
/// structured JSON the step expects.
///
/// DeepL keeps its `api-free` endpoint and `model_type` (quality/latency)
/// selection. The transport is injectable so request building and response/error
/// mapping can be tested without the network.
struct DeepLLanguageModel: CustomTranslationLanguageModel {
    let provider = "deepl"
    let modelId: String

    let apiKey: String
    /// DeepL `model_type` (e.g. "latency_optimized", "quality_optimized").
    /// `nil` uses DeepL's account default.
    let modelType: String?

    /// Sends a request and returns the raw body + response. Injectable for tests;
    /// defaults to `URLSession.shared`.
    private let transport: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    init(
        apiKey: String,
        modelType: String? = nil,
        transport: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
            try await URLSession.shared.data(for: request)
        }
    ) {
        self.apiKey = apiKey
        self.modelType = modelType
        self.modelId = modelType ?? "default"
        self.transport = transport
    }

    private static let endpoint = URL(string: "https://api-free.deepl.com/v2/translate")!

    func translate(_ lines: [CustomTranslationPrompt.SourceLine]) async throws -> [TranslationLine] {
        guard !apiKey.isEmpty else { throw DeepLError.missingAPIKey }
        guard !lines.isEmpty else { return [] }

        let request = try buildRequest(for: lines.map(\.text))
        let (data, response) = try await transport(request)

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

        guard decoded.translations.count == lines.count else {
            throw DeepLError.invalidResponse
        }

        // DeepL preserves request order, so zip translations back onto the source
        // lines' numbers — the unified step then maps by number.
        return zip(lines, decoded.translations).map { line, translation in
            TranslationLine(number: line.number, text: translation.text)
        }
    }

    /// Builds the authenticated, form-encoded POST. Exposed for testing.
    func buildRequest(for sourceTexts: [String]) throws -> URLRequest {
        var request = URLRequest(url: Self.endpoint)
        request.timeoutInterval = 30
        request.httpMethod = "POST"
        request.setValue("DeepL-Auth-Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody(for: sourceTexts, modelType: modelType).data(using: .utf8)
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
        string.addingPercentEncoding(withAllowedCharacters: .translationQueryValue) ?? string
    }
}

struct DeepLResponse: Decodable {
    let translations: [Translation]

    struct Translation: Decodable {
        let text: String
    }
}
