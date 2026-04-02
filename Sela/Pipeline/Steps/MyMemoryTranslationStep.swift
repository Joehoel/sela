import Foundation

enum MyMemoryError: LocalizedError {
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

/// Translates items one-by-one from English to Dutch using the free MyMemory API.
struct MyMemoryTranslationStep: TranslationPipelineStep {
    let name = "Translating…"

    private static let baseURL = "https://api.mymemory.translated.net/get"

    func process(_ items: inout [TranslationItem]) async throws {
        for i in items.indices {
            items[i].currentText = try await translate(items[i].sourceText)
        }
    }

    private func translate(_ text: String) async throws -> String {
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(Self.baseURL)?q=\(encoded)&langpair=en|nl")
        else {
            throw MyMemoryError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)

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

        return decoded.responseData.translatedText
    }
}

private struct MyMemoryResponse: Decodable {
    let responseData: ResponseData
    let quotaFinished: Bool

    struct ResponseData: Decodable {
        let translatedText: String
    }
}
