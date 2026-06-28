import AISDKProvider
import Foundation
@testable import Sela
import Testing

/// Google Translate implemented as a custom `LanguageModelV3` (see
/// `CustomTranslationModel`). It wraps the free, unofficial web endpoint and
/// stays key-free. These tests cover request building, response parsing, error
/// mapping, and the source-line → `TranslationLine` mapping — all without
/// touching the network (the transport is injected).
struct GoogleTranslateLanguageModelTests {
    // MARK: - Response parsing

    @Test("parses the nested-array web response into a single translated string")
    func parseNestedResponse() throws {
        // Shape: [[["Hallo wereld","Hello world",null,null,...]],null,"en",...]
        let json = """
        [[["Hallo wereld","Hello world",null,null,10]],null,"en"]
        """
        let text = try GoogleTranslateLanguageModel.parseTranslation(from: Data(json.utf8))
        #expect(text == "Hallo wereld")
    }

    @Test("joins multiple sentence segments back into one line")
    func parseMultiSegment() throws {
        let json = """
        [[["Hallo, ","Hi, ",null,null,1],["wereld.","world.",null,null,1]],null,"en"]
        """
        let text = try GoogleTranslateLanguageModel.parseTranslation(from: Data(json.utf8))
        #expect(text == "Hallo, wereld.")
    }

    @Test("a malformed body throws invalidResponse")
    func parseMalformed() {
        #expect(throws: GoogleTranslateError.invalidResponse) {
            _ = try GoogleTranslateLanguageModel.parseTranslation(from: Data("not json".utf8))
        }
    }

    // MARK: - Error types

    @Test("GoogleTranslateError has user-friendly descriptions")
    func errorDescriptions() {
        #expect(GoogleTranslateError.requestFailed(statusCode: 500).errorDescription?.contains("500") == true)
        #expect(GoogleTranslateError.invalidResponse.errorDescription?.contains("unexpected") == true)
    }

    // MARK: - Request building

    @Test("builds a GET to the gtx endpoint with the source text url-encoded")
    func buildsRequest() throws {
        let request = try GoogleTranslateLanguageModel.buildRequest(for: "Hello world")
        #expect(request.httpMethod == nil || request.httpMethod == "GET")
        let url = try #require(request.url?.absoluteString)
        #expect(url.hasPrefix("https://translate.googleapis.com/translate_a/single"))
        #expect(url.contains("client=gtx"))
        #expect(url.contains("sl=en"))
        #expect(url.contains("tl=nl"))
        #expect(url.contains("q=Hello%20world") || url.contains("q=Hello+world"))
    }

    // MARK: - translate() mapping (transport injected — no network)

    @Test("translates lines in one batched request and preserves their numbers")
    func translateMapsByNumber() async throws {
        // All lines go in ONE request joined by newlines; the translated text is
        // split back apart and keyed onto the source-line numbers.
        let model = GoogleTranslateLanguageModel { _ in
            let json = #"[[["Hallo\nWereld","Hello\nWorld",null,null,1]],null,"en"]"#
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
    }

    @Test("a non-200 status maps to GoogleTranslateError.requestFailed")
    func httpFailure() async {
        let model = GoogleTranslateLanguageModel { _ in
            (Data(), Self.response(status: 503))
        }
        await #expect(throws: GoogleTranslateError.requestFailed(statusCode: 503)) {
            _ = try await model.translate([.init(number: 1, text: "Hi")])
        }
    }

    @Test("is key-free — translate works with no configuration")
    func keyFree() async throws {
        let model = GoogleTranslateLanguageModel { _ in
            (Data("[[[\"Hoi\",\"Hi\",null,null,1]],null,\"en\"]".utf8), Self.okResponse)
        }
        let result = try await model.translate([.init(number: 7, text: "Hi")])
        #expect(result == [TranslationLine(number: 7, text: "Hoi")])
    }

    @Test("empty source lines short-circuit without a request")
    func emptyLines() async throws {
        let captured = TransportCapture()
        let model = GoogleTranslateLanguageModel { request in
            captured.store(request)
            return (Data(), Self.okResponse)
        }
        let result = try await model.translate([])
        #expect(result.isEmpty)
        #expect(captured.wasCalled == false)
    }

    // MARK: - Helpers

    static let okResponse = response(status: 200)

    static func response(status: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://translate.googleapis.com/translate_a/single")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
    }
}

/// Thread-safe capture of whether the injected transport was invoked. Shared by
/// the Google Translate and MyMemory custom-model tests.
final class TransportCapture: @unchecked Sendable {
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
}
