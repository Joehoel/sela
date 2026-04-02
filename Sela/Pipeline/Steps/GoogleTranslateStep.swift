import Foundation

enum GoogleTranslateError: LocalizedError {
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

/// Batch-translates items from English to Dutch using the unofficial Google Translate endpoint.
struct GoogleTranslateStep: TranslationPipelineStep {
    let name = "Translating…"

    func process(_ items: inout [TranslationItem]) async throws {
        guard !items.isEmpty else { return }

        let combined = items.map(\.sourceText).joined(separator: "\n")
        let translated = try await translate(combined)
        let lines = translated.components(separatedBy: "\n")

        for i in items.indices {
            items[i].currentText = i < lines.count ? lines[i] : items[i].sourceText
        }
    }

    private func translate(_ text: String) async throws -> String {
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://translate.googleapis.com/translate_a/single?client=gtx&sl=en&tl=nl&dt=t&q=\(encoded)")
        else {
            throw GoogleTranslateError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleTranslateError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw GoogleTranslateError.requestFailed(statusCode: httpResponse.statusCode)
        }

        // Response is nested arrays: [[["translated","original",null,null,null],...],...,null,"en"]
        guard let json = try JSONSerialization.jsonObject(with: data) as? [Any],
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
