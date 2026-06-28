import Foundation

enum GoogleTranslateError: LocalizedError, Equatable {
    case requestFailed(statusCode: Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case let .requestFailed(statusCode):
            "Google Translate request failed (HTTP \(statusCode))."
        case .invalidResponse:
            "Google Translate returned an unexpected response."
        }
    }
}

/// Google Translate (the free, unofficial web endpoint) as a custom
/// `LanguageModelV3`, routed through the unified `AISDKTranslationStep` like every
/// other engine. It is not an LLM and needs no API key, so the shared
/// `CustomTranslationLanguageModel` base turns the numbered prompt into source
/// lines, calls this `translate(_:)`, and serializes the result into the
/// structured JSON the step expects.
///
/// Each line is translated with its own request so the translation maps back onto
/// the exact source-line number — the endpoint gives no per-line keys when batched.
/// The transport is injectable so request building and response/error mapping can
/// be tested without the network.
struct GoogleTranslateLanguageModel: CustomTranslationLanguageModel {
    let provider = "google-translate"
    let modelId = "google-translate-web"

    /// Sends a request and returns the raw body + response. Injectable for tests;
    /// defaults to `URLSession.shared`.
    private let transport: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    init(
        transport: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
            try await URLSession.shared.data(for: request)
        }
    ) {
        self.transport = transport
    }

    func translate(_ lines: [CustomTranslationPrompt.SourceLine]) async throws -> [TranslationLine] {
        guard !lines.isEmpty else { return [] }

        // One batched request for the whole song (the free gtx endpoint rate-limits
        // aggressively, so a request per line gets throttled). Lines are joined with
        // newlines and the translated text is split back apart.
        let joined = lines.map(\.text).joined(separator: "\n")
        let request = try Self.buildRequest(for: joined)
        let (data, response) = try await transport(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleTranslateError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw GoogleTranslateError.requestFailed(statusCode: httpResponse.statusCode)
        }

        let parts = try Self.parseTranslation(from: data).components(separatedBy: "\n")

        // Only trust the split when it lines up 1:1; otherwise fall back to the
        // source text per line rather than misaligning translations.
        guard parts.count == lines.count else {
            return lines.map { TranslationLine(number: $0.number, text: $0.text) }
        }
        return zip(lines, parts).map { line, text in
            TranslationLine(number: line.number, text: text.isEmpty ? line.text : text)
        }
    }

    /// Builds the unauthenticated GET to the `gtx` endpoint. Exposed for testing.
    static func buildRequest(for sourceText: String) throws -> URLRequest {
        guard let encoded = sourceText.addingPercentEncoding(withAllowedCharacters: .translationQueryValue),
              let url = URL(
                  string: "https://translate.googleapis.com/translate_a/single?client=gtx&sl=en&tl=nl&dt=t&q=\(encoded)"
              )
        else {
            throw GoogleTranslateError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        return request
    }

    /// Parses the nested-array web response into a single translated string.
    /// Shape: `[[["translated","original",null,…],…],…,"en"]`. The first element
    /// is an array of `[translated, original, …]` segments; concatenating the
    /// `translated` segments reconstructs the line. Exposed for testing.
    static func parseTranslation(from data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let segments = json.first as? [Any]
        else {
            throw GoogleTranslateError.invalidResponse
        }

        return segments.compactMap { segment -> String? in
            guard let pair = segment as? [Any], let text = pair.first as? String else { return nil }
            return text
        }.joined()
    }
}
