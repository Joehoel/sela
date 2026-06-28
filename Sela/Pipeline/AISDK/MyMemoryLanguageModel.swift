import Foundation

enum MyMemoryError: LocalizedError, Equatable {
    case quotaExceeded
    case requestFailed(statusCode: Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .quotaExceeded:
            "MyMemory daily quota exceeded. Try again tomorrow or switch engine."
        case let .requestFailed(statusCode):
            "MyMemory request failed (HTTP \(statusCode))."
        case .invalidResponse:
            "MyMemory returned an unexpected response."
        }
    }
}

/// MyMemory (the free REST translation API) as a custom `LanguageModelV3`, routed
/// through the unified `AISDKTranslationStep` like every other engine. It is not
/// an LLM and needs no API key, so the shared `CustomTranslationLanguageModel`
/// base turns the numbered prompt into source lines, calls this `translate(_:)`,
/// and serializes the result into the structured JSON the step expects.
///
/// MyMemory translates one phrase per request, so each line is sent on its own and
/// mapped back onto its source-line number. The transport is injectable so request
/// building and response/error mapping can be tested without the network.
struct MyMemoryLanguageModel: CustomTranslationLanguageModel {
    let provider = "mymemory"
    let modelId = "mymemory"

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

    private static let baseURL = "https://api.mymemory.translated.net/get"

    func translate(_ lines: [CustomTranslationPrompt.SourceLine]) async throws -> [TranslationLine] {
        guard !lines.isEmpty else { return [] }

        var results: [TranslationLine] = []
        results.reserveCapacity(lines.count)
        for line in lines {
            let request = try Self.buildRequest(for: line.text)
            let (data, response) = try await transport(request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw MyMemoryError.invalidResponse
            }
            guard httpResponse.statusCode == 200 else {
                throw MyMemoryError.requestFailed(statusCode: httpResponse.statusCode)
            }

            let decoded = try JSONDecoder().decode(MyMemoryResponse.self, from: data)
            if decoded.quotaFinished {
                throw MyMemoryError.quotaExceeded
            }
            results.append(TranslationLine(number: line.number, text: decoded.responseData.translatedText))
        }
        return results
    }

    /// Builds the unauthenticated GET to the MyMemory endpoint. Exposed for testing.
    /// Uses `URLComponents` so each query value is percent-encoded exactly once —
    /// the `|` in `langpair=en|nl` makes a hand-built `URL(string:)` re-encode the
    /// whole query (double-encoding `q`).
    static func buildRequest(for sourceText: String) throws -> URLRequest {
        guard var components = URLComponents(string: baseURL) else {
            throw MyMemoryError.invalidResponse
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: sourceText),
            URLQueryItem(name: "langpair", value: "en|nl"),
        ]
        guard let url = components.url else {
            throw MyMemoryError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        return request
    }
}

struct MyMemoryResponse: Decodable {
    let responseData: ResponseData
    let quotaFinished: Bool

    struct ResponseData: Decodable {
        let translatedText: String
    }

    private enum CodingKeys: String, CodingKey {
        case responseData
        case quotaFinished
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        responseData = try container.decode(ResponseData.self, forKey: .responseData)
        quotaFinished = try container.decodeIfPresent(Bool.self, forKey: .quotaFinished) ?? false
    }
}
