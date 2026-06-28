import AISDKProvider
import Foundation
@testable import Sela
import Testing

/// DeepL implemented as a custom `LanguageModelV3` (see `CustomTranslationModel`).
/// These tests cover request building (incl. `model_type`), response parsing,
/// error mapping, and the source-line → `TranslationLine` mapping — all without
/// touching the network (the transport is injected).
struct DeepLLanguageModelTests {
    // MARK: - Response parsing

    @Test("parses valid DeepL response")
    func parseValidResponse() throws {
        let json = """
        {"translations":[{"text":"Hallo wereld"},{"text":"Goedemorgen"}]}
        """
        let data = try #require(json.data(using: .utf8))
        let response = try JSONDecoder().decode(DeepLResponse.self, from: data)
        #expect(response.translations.count == 2)
        #expect(response.translations[0].text == "Hallo wereld")
        #expect(response.translations[1].text == "Goedemorgen")
    }

    @Test("parses single translation response")
    func parseSingleTranslation() throws {
        let json = """
        {"translations":[{"text":"Test vertaling"}]}
        """
        let data = try #require(json.data(using: .utf8))
        let response = try JSONDecoder().decode(DeepLResponse.self, from: data)
        #expect(response.translations.count == 1)
        #expect(response.translations[0].text == "Test vertaling")
    }

    // MARK: - Error types

    @Test("DeepLError has user-friendly descriptions")
    func errorDescriptions() {
        #expect(DeepLError.missingAPIKey.errorDescription?.contains("not configured") == true)
        #expect(DeepLError.authenticationFailed.errorDescription?.contains("invalid") == true)
        #expect(DeepLError.rateLimitExceeded.errorDescription?.contains("rate limit") == true)
        #expect(DeepLError.requestFailed(statusCode: 500).errorDescription?.contains("500") == true)
        #expect(DeepLError.invalidResponse.errorDescription?.contains("unexpected") == true)
    }

    @Test("missing API key throws before any request")
    func missingAPIKey() async {
        let model = DeepLLanguageModel(apiKey: "")
        await #expect(throws: DeepLError.self) {
            _ = try await model.translate([.init(number: 1, text: "Hello")])
        }
    }

    // MARK: - Request body / model_type

    @Test("form body omits model_type when none is selected")
    func formBodyWithoutModelType() {
        let body = DeepLLanguageModel.formBody(for: ["Hello"], modelType: nil)
        #expect(body.contains("text=Hello"))
        #expect(body.contains("source_lang=EN"))
        #expect(body.contains("target_lang=NL"))
        #expect(!body.contains("model_type"))
    }

    @Test("form body includes model_type when selected")
    func formBodyWithModelType() {
        let body = DeepLLanguageModel.formBody(for: ["Hello"], modelType: "quality_optimized")
        #expect(body.contains("model_type=quality_optimized"))
    }

    @Test("builds an authenticated POST to the api-free endpoint")
    func buildsRequest() throws {
        let model = DeepLLanguageModel(apiKey: "secret-key", modelType: "latency_optimized")
        let request = try model.buildRequest(for: ["Hello", "World"])
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api-free.deepl.com/v2/translate")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "DeepL-Auth-Key secret-key")
        let body = try #require(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        #expect(body.contains("text=Hello"))
        #expect(body.contains("text=World"))
        #expect(body.contains("model_type=latency_optimized"))
    }

    // MARK: - translate() mapping (transport injected — no network)

    @Test("maps DeepL translations back onto numbered source lines, preserving order")
    func translateMapsByOrder() async throws {
        let captured = RequestCapture()
        let model = DeepLLanguageModel(apiKey: "k", modelType: "quality_optimized") { request in
            captured.store(request)
            let json = """
            {"translations":[{"text":"Hallo"},{"text":"Wereld"}]}
            """
            return (Data(json.utf8), Self.okResponse)
        }

        let result = try await model.translate([
            .init(number: 1, text: "Hello"),
            .init(number: 2, text: "World"),
        ])

        #expect(result == [
            TranslationLine(number: 1, text: "Hallo"),
            TranslationLine(number: 2, text: "Wereld"),
        ])

        // The model_type selection is preserved on the wire.
        let body = captured.body()
        #expect(body.contains("model_type=quality_optimized"))
        #expect(body.contains("text=Hello"))
        #expect(body.contains("text=World"))
    }

    @Test("authentication failure maps to DeepLError.authenticationFailed")
    func authFailure() async {
        let model = DeepLLanguageModel(apiKey: "bad") { _ in
            (Data(), Self.response(status: 403))
        }
        await #expect(throws: DeepLError.authenticationFailed) {
            _ = try await model.translate([.init(number: 1, text: "Hi")])
        }
    }

    @Test("rate-limit status maps to DeepLError.rateLimitExceeded")
    func rateLimit() async {
        let model = DeepLLanguageModel(apiKey: "k") { _ in
            (Data(), Self.response(status: 429))
        }
        await #expect(throws: DeepLError.rateLimitExceeded) {
            _ = try await model.translate([.init(number: 1, text: "Hi")])
        }
    }

    @Test("other HTTP failures map to DeepLError.requestFailed")
    func otherFailure() async {
        let model = DeepLLanguageModel(apiKey: "k") { _ in
            (Data(), Self.response(status: 500))
        }
        await #expect(throws: DeepLError.requestFailed(statusCode: 500)) {
            _ = try await model.translate([.init(number: 1, text: "Hi")])
        }
    }

    @Test("a translation-count mismatch maps to DeepLError.invalidResponse")
    func countMismatch() async {
        let model = DeepLLanguageModel(apiKey: "k") { _ in
            let json = #"{"translations":[{"text":"Hallo"}]}"#
            return (Data(json.utf8), Self.okResponse)
        }
        await #expect(throws: DeepLError.invalidResponse) {
            _ = try await model.translate([
                .init(number: 1, text: "Hello"),
                .init(number: 2, text: "World"),
            ])
        }
    }

    @Test("empty source lines short-circuit without a request")
    func emptyLines() async throws {
        let captured = RequestCapture()
        let model = DeepLLanguageModel(apiKey: "k") { request in
            captured.store(request)
            return (Data(), Self.okResponse)
        }
        let result = try await model.translate([])
        #expect(result.isEmpty)
        #expect(captured.wasCalled == false)
    }

    // MARK: - Helpers

    private static let okResponse = response(status: 200)

    private static func response(status: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api-free.deepl.com/v2/translate")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
    }
}

/// Thread-safe capture of the request handed to the injected transport.
private final class RequestCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var request: URLRequest?

    var wasCalled: Bool {
        lock.lock(); defer { lock.unlock() }
        return request != nil
    }

    func store(_ request: URLRequest) {
        lock.lock(); defer { lock.unlock() }
        self.request = request
    }

    func body() -> String {
        lock.lock(); defer { lock.unlock() }
        return request?.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}
